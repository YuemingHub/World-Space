#!/usr/bin/env bash
# 改登录口令（产品本身没有"改密码"功能，所以这是唯一入口；改完即时生效，不用重启）
#
# 纪律：
#   口令从标准输入进来，全程不回显、不进命令行参数、不进 shell 历史
#   屏幕上只出现它的 sha256 前 12 位（用来日后确认"是同一个口令"，反推不出口令）
#   装好之后必须用一次真实登录验过，验不过就原样退回旧文件——
#   最怕的是"我以为改好了"结果把唯一能进门的账号锁在外面
#
# 用法（服务器上，root）：
#   set-password.sh <user_id> <username> < 口令文件
#   口令文件可以是纯一行口令，也可以是「密码：xxx」这种带标签的写法。
set -uo pipefail

UID_WANT="${1:-}"; UNAME="${2:-}"
[ -n "$UID_WANT" ] && [ -n "$UNAME" ] || { echo "用法: set-password.sh <user_id> <username> < 口令文件" >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "需要 root" >&2; exit 1; }

ROOT=/opt/world-space
PRIV=$ROOT/etc
USERS=$PRIV/users.json
REL=$ROOT/releases/$(cat "$ROOT/state/approved-sha" 2>/dev/null)
SVC=127.0.0.1:3200
[ -f "$USERS" ] || { echo "FAIL: 找不到 $USERS" >&2; exit 1; }
[ -f "$REL/scripts/hash-password.mjs" ] || { echo "FAIL: 发布树里没有 hash 工具（$REL）" >&2; exit 1; }

BK=$PRIV/users.json.bak-pw-$(date +%Y%m%d-%H%M%S)
cp -p "$USERS" "$BK"; chmod 600 "$BK"; chown wsapp:wsapp "$BK" 2>/dev/null || true
echo "  已备份用户文件：$(basename "$BK")"

RAW=$(cat)   # 从标准输入收全，不打印

# 造候选：整份去掉首尾空白/BOM；再按行取；再取冒号后面的部分。去重后依次试。
cands_file=$(mktemp); tmpdir=$(mktemp -d); chmod 700 "$tmpdir"
printf '%s' "$RAW" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const clean = x => x.replace(/^\uFEFF/,"").replace(/^[\s\uFEFF]+|[\s\uFEFF]+$/g,"").replace(/\r/g,"");
  const out=[]; const push=v=>{ v=clean(v); if(v && !out.includes(v)) out.push(v); };
  push(s);
  for (const line of s.split("\n")) {
    push(line);
    const m=line.match(/[:：]\s*(.+)$/); if (m) push(m[1]);
  }
  // 长的先试：带标签的整行往往是误取，纯口令行更短且不含空格
  out.sort((a,b)=>a.length-b.length);
  process.stdout.write(out.join("\n") + "\n");
});' > "$cands_file"

n=$(grep -c . "$cands_file" || true)
echo "  从你给的文件里得到 $n 种候选读法（值不显示）："
i=0; found=""
while IFS= read -r cand || [ -n "$cand" ]; do
  [ -z "$cand" ] && continue
  i=$((i+1))
  len=${#cand}
  fp=$(printf %s "$cand" | sha256sum | cut -c1-12)
  if [ "$len" -lt 8 ]; then echo "    候选 $i：不足 8 位，产品会拒绝这种口令，跳过"; continue; fi
  echo "    候选 $i：指纹 $fp"
  # 装这把
  REC=$(printf %s "$cand" | node "$REL/scripts/hash-password.mjs" "$UID_WANT" "$UNAME") || { echo "      装不下：hash 工具拒了"; continue; }
  REC="$REC" node -e '
    const fs=require("fs"); const f=process.argv[1];
    const j=JSON.parse(fs.readFileSync(f,"utf8")); const rec=JSON.parse(process.env.REC);
    let hit=false; j.users=j.users.map(u=>{ if(u.user_id===rec.user_id){hit=true; return rec;} return u; });
    if(!hit) j.users.push(rec);
    fs.writeFileSync(f, JSON.stringify(j,null,2)+"\n");
  ' "$USERS" || { echo "      写入失败"; continue; }
  chmod 600 "$USERS"; chown wsapp:wsapp "$USERS" 2>/dev/null || true
  # 用一次真实登录验它（用户文件每次请求都重读，所以立刻生效）
  printf '{"username":"%s","password":%s}' "$UNAME" "$(printf %s "$cand" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s)))')" > "$tmpdir/l.json"
  code=$(curl -s -o "$tmpdir/l.out" -w '%{http_code}' --max-time 10 -X POST -H 'content-type: application/json' \
         --data-binary @"$tmpdir/l.json" "http://$SVC/api/auth/login")
  rm -f "$tmpdir/l.json"
  if [ "$code" = "200" ]; then echo "      真实登录验证：200 ✓ 就是这一种读法"; found="$fp"; break; fi
  echo "      真实登录验证：$code（不对，换下一种读法）"
done < "$cands_file"

rm -f "$cands_file"; rm -rf "$tmpdir"

if [ -z "$found" ]; then
  cp -p "$BK" "$USERS"; chmod 600 "$USERS"; chown wsapp:wsapp "$USERS" 2>/dev/null || true
  echo "FAIL: $n 种读法没有一个能登录，已原样退回旧口令（旧口令仍然可用）" >&2
  echo "      请确认文件里就是你要设的口令本身（一行、别加别的字），再跑一次" >&2
  exit 1
fi

echo "=== 完成 ==="
echo "  $UID_WANT（用户名 $UNAME）的口令已生效，指纹 $found（反推不出口令）"
echo "  旧令牌不受影响（签名密钥没换），但已登录的设备下次请求会照常通过"
echo "  备份留在 $(basename "$BK")；确认你自己登录没问题后，可以让我把它和 first-login.txt 一起抹掉"
