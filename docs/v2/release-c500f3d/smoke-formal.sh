#!/usr/bin/env bash
# World Space V0.1 — §12 正式配置 localhost smoke（服务器本机实例，公网不经过这里）
#
# 三条纪律：
#   1. 明文口令只从 first-login.txt 在进程内读进变量，绝不 echo、绝不进日志
#   2. 中文载荷一律 UTF-8 落盘后 --data-binary @file（直传中文会被 GBK 破坏：
#      服务端收到乱码 → 模型诚实拒绝 → 结论全废而且失败照样计费）
#   3. 只跑 127.0.0.1:3210；nginx / DNS / current / 公网服务一概不碰
#
# 判定器约定（本轮踩过坑，写死在这里）：
#   ck  <名字> <1=通过 / 0=失败> <证据>
#   ckz <名字> <命令退出码 0=成功> <证据>     ← 凡是用 $? 的地方一律走 ckz
#   上一版把 shell 的 0=成功 直接喂给"1=通过"的判定器，结果 12 条 ✗ 里 7 条是假的，
#   而真正该红的"第一轮 502"被记成了 ✓ ——假绿比假红危险，所以本文件开头先自检判定器。
set -uo pipefail

ROOT=/opt/world-space
REL=$ROOT/releases/c500f3d76601abb263511cb622efd38379e8b959
SMOKE_ENV=$ROOT/shared/env/world-space.v01-smoke.env
PRIV=$ROOT/etc
OUT=$ROOT/state/smoke
PORT=3210
H="http://127.0.0.1:$PORT"
mkdir -p "$OUT"
PID=""
pass=0; fail=0

ck() {
  if [ "$2" = "1" ]; then echo "  ✓ $1"; pass=$((pass+1));
  else echo "  ✗ $1 —— $3"; fail=$((fail+1)); fi
}
ckz() { ck "$1" "$([ "$2" = 0 ] && echo 1 || echo 0)" "$3"; }

cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; }
trap cleanup EXIT

# 注：--rejudge 分支放在"判定器自检"之后——重判也必须先用自测过的尺子，不能绕过自检。

# ---- 判定器自检：反了就整轮作废，不许继续产出任何 PASS/FAIL ----
_sp=$pass; _sf=$fail
_t=$pass; ck "（自检）真通过应记 ✓" 1 "" >/dev/null
[ "$pass" = "$((_t+1))" ] || { echo "FATAL: 判定器 ck 不可信"; exit 9; }
_t=$fail; ck "（自检）真失败应记 ✗" 0 "" >/dev/null
[ "$fail" = "$((_t+1))" ] || { echo "FATAL: 判定器 ck 不可信"; exit 9; }
_t=$pass; ckz "（自检）退出码 0 应记 ✓" 0 "" >/dev/null
[ "$pass" = "$((_t+1))" ] || { echo "FATAL: 判定器 ckz 不可信"; exit 9; }
_t=$pass; (exit 3); ckz "（自检）退出码非 0 应记 ✗" $? "" >/dev/null
[ "$pass" = "$_t" ] || { echo "FATAL: 判定器把失败记成了通过"; exit 9; }
pass=$_sp; fail=$_sf
echo "判定器自检通过（4 项，含"绝不把失败记成通过"）"

# ---- --rejudge：只重判已抓到的响应，不再发任何真实请求（省一次付费）----
# 拿旧文件冒充本轮结果是最容易犯的错，所以先卡三道：新鲜度、不是错误响应、两轮都有 next_action。
if [ "${1:-}" = "--rejudge" ]; then
  echo "=== 只重判已抓到的两轮回路（不起实例、不发请求、不花钱）==="
  for f in round1 round2; do
    [ -s "$OUT/$f.json" ] || { echo "FAIL: 缺 $OUT/$f.json，无法重判"; exit 1; }
    age=$(( $(date +%s) - $(stat -c %Y "$OUT/$f.json") ))
    [ "$age" -lt 10800 ] || { echo "FAIL: $f.json 是 $((age/60)) 分钟前抓的，拒绝当本轮结果"; exit 1; }
    echo "  $f.json：$age 秒前抓取，$(wc -c < "$OUT/$f.json") 字节"
  done
  node -e '
    const p="/opt/world-space/state/smoke/";
    const r1=require(p+"round1.json"), r2=require(p+"round2.json");
    const t1=(r1.next_action||{}).text||"", t2=(r2.next_action||{}).text||"";
    const m=r2.meta||{};
    if(r1.error||r2.error){console.log("  ✗ 有一轮是错误响应: "+JSON.stringify(r1.error||r2.error));process.exit(1);}
    if(!t1||!t2){console.log("  ✗ 某一轮没有 next_action，不能判通过");process.exit(1);}
    console.log("  第一轮:",JSON.stringify(t1).slice(0,70));
    console.log("  第二轮:",JSON.stringify(t2).slice(0,70));
    console.log("  receipt_ingested =",m.receipt_ingested,"| receipt_status =",m.receipt_status,"| search_calls =",m.search_calls);
    const ok = m.receipt_ingested===true && !!t2 && t1!==t2;
    require("fs").writeFileSync(p+".r2ok", ok?"1":"0");
    console.log(ok ? "  ✓ 第二轮吸收了回执、且没有重答第一轮" : "  ✗ 判定不通过");
    process.exit(ok?0:1);
  '
  RC=$?
  ck "（重判）第二轮 receipt_ingested=true 且行动真的改变" "$([ "$RC" = 0 ] && echo 1 || echo 0)" "见 $OUT/round2.json"
  node -e 'const j=require("/opt/world-space/state/smoke/round1.json");process.exit((j.meta||{}).search_calls>0?0:1)' 2>/dev/null
  ckz "（重判）第一轮真的发生了搜索调用（新 key 走通）" $? "round1.meta.search_calls 不大于 0"
  echo "PASS=$pass FAIL=$fail"
  [ "$fail" = 0 ] && echo "REJUDGE=PASS（判的是本轮已抓到的真实响应字节，未再产生任何调用）" \
                  || echo "REJUDGE=FAIL"
  exit $((fail>0?1:0))
fi

# ---------- 起实例 ----------
set -a; . "$SMOKE_ENV"; set +a
cd "$REL"
node server/world.mjs > "$OUT/instance.log" 2>&1 &
PID=$!
sleep 2
HZ=$(curl -s --max-time 8 "$H/healthz")
echo "healthz: $HZ"
echo "$HZ" | grep -q '"auth":"ready"'; ckz "auth=ready（正式配置，不是桩）" $? "$HZ"
[ "$(echo "$HZ" | grep -c '"auth":"ready"')" = 1 ] || { echo "认证没起来，停"; exit 1; }

# ---------- 未登录 ----------
echo "=== 未登录 ==="
c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$H/")
loc=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 8 "$H/")
ck "GET / → 302" "$([ "$c" = "302" ] && echo 1 || echo 0)" "实际 $c"
ck "重定向目标是 /login" "$([ -n "$loc" ] && echo "$loc" | grep -q '/login' && echo 1 || echo 0)" "$loc"
api=$(curl -s -o "$OUT/unauth.json" -w '%{http_code}' --max-time 8 -X POST -H 'content-type: application/json' \
      -d '{"intent":"smoke unauth probe"}' "$H/api/world")
ck "POST /api/world 未登录 → 401" "$([ "$api" = "401" ] && echo 1 || echo 0)" "$api $(head -c 120 "$OUT/unauth.json")"

# ---------- 错误登录 ----------
echo "=== 错误口令 / 不存在的账号 ==="
bad=$(curl -s -o "$OUT/badlogin.json" -w '%{http_code}' --max-time 8 -X POST -H 'content-type: application/json' \
      -d '{"username":"ymai","password":"this-is-wrong-123"}' "$H/api/auth/login")
grep -q '账号或密码不正确' "$OUT/badlogin.json"; BADTXT=$?
ck "错误口令 → 401 且口径是「账号或密码不正确。」" \
   "$([ "$bad" = "401" ] && [ "$BADTXT" = 0 ] && echo 1 || echo 0)" "http=$bad 正文=$(head -c 120 "$OUT/badlogin.json")"
nosuch=$(curl -s -o "$OUT/badlogin2.json" -w '%{http_code}' --max-time 8 -X POST -H 'content-type: application/json' \
      -d '{"username":"nosuchuser","password":"whatever-1234"}' "$H/api/auth/login")
cmp -s "$OUT/badlogin.json" "$OUT/badlogin2.json"; SAMEBODY=$?
ck "「没这个账号」与「密码错」逐字节一致（不泄露账号是否存在）" \
   "$([ "$nosuch" = "401" ] && [ "$SAMEBODY" = 0 ] && echo 1 || echo 0)" \
   "nosuch=$nosuch cmp=$SAMEBODY $(head -c 100 "$OUT/badlogin2.json")"

# ---------- 正确登录 A ----------
echo "=== 正确登录（A = u-owner）==="
PWA=$(sed -n 's/^A 账号.*密码: //p' "$PRIV/first-login.txt")
ck "从私有文件读到 A 的口令（值不回显）" "$([ -n "$PWA" ] && echo 1 || echo 0)" "sed 没匹配到，检查 first-login.txt 行格式"
node -e 'const p=JSON.stringify({username:"ymai",password:process.argv[1]});require("fs").writeFileSync(process.argv[2],p)' "$PWA" "$OUT/loginA.json"
CODE=$(curl -s -D "$OUT/loginA.hdr" -o "$OUT/loginA.body" -w '%{http_code}' --max-time 10 -X POST \
  -H 'content-type: application/json' --data-binary @"$OUT/loginA.json" "$H/api/auth/login")
ck "登录返回 200/302" "$([ "$CODE" = "200" ] || [ "$CODE" = "302" ] && echo 1 || echo 0)" "$CODE $(head -c 80 "$OUT/loginA.body")"
CKA=$(grep -i '^set-cookie:' "$OUT/loginA.hdr" | head -1 | tr -d '\r')
FLAGS=$(echo "$CKA" | grep -oiE 'httponly|secure|samesite=lax|path=/' | sort -u | tr '\n' ' ')
echo "  Set-Cookie 旗标: $FLAGS"
echo "$CKA" | grep -qi 'httponly';     ckz "Cookie HttpOnly" $? "$CKA"
echo "$CKA" | grep -qi 'secure';       ckz "Cookie Secure（WS_COOKIE_SECURE=1 生效）" $? "$CKA"
echo "$CKA" | grep -qi 'samesite=lax'; ckz "Cookie SameSite=Lax" $? "$CKA"
echo "$CKA" | grep -qiE 'password|口令'; NOCP=$?
ck "Cookie 里没有口令字样（只装身份）" "$([ "$NOCP" = 1 ] && echo 1 || echo 0)" "命中口令字样"
TOKA=$(echo "$CKA" | sed -n 's/^[Ss]et-[Cc]ookie: \([^;]*\)=\([^;]*\);.*/\1=\2/p')
ME=$(curl -s --max-time 8 -H "Cookie: $TOKA" "$H/api/auth/me")
echo "  A 的身份: $ME"
echo "$ME" | grep -q 'u-owner'; ckz "/api/auth/me 认到 u-owner" $? "$ME"
PAGE=$(curl -s --max-time 8 -H "Cookie: $TOKA" "$H/")
echo "$PAGE" | grep -q '你现在想做成什么'; ckz "登录后首页出现「你现在想做成什么？」" $? "页面里没这句话"

# ---------- 真实 Outcome Loop 两轮（上游 429 时按 45s 间隔重试，最多 3 次）----------
post_round() { # post_round <载荷文件> <输出文件>  → 回写 HTTP 码到全局 RD_CODE
  local payload="$1" outj="$2" n=0 code
  while [ "$n" -lt 3 ]; do
    n=$((n+1))
    code=$(curl -s --max-time 150 -H "Cookie: $TOKA" -H 'content-type: application/json' \
           --data-binary @"$payload" "$H/api/world" -o "$outj" -w '%{http_code}')
    RD_ATTEMPTS=$n
    if [ "$code" = "200" ]; then RD_CODE=$code; return 0; fi
    echo "    第 $n 次 HTTP $code：$(head -c 90 "$outj")"
    [ "$code" = "502" ] || { RD_CODE=$code; return 1; }
    sleep 40
  done
  RD_CODE=$code; return 1
}

echo "=== 真实模型 + 真实搜索：两轮回路（会产生真实花费）==="
rm -f "$OUT/.r2ok"   # 开跑前清一次：既不拿旧结果当本轮结论，也不会误删本轮刚写的标记
cat > "$OUT/intent1.json" <<'JSON'
{"intent":"我们小区门口的路灯坏了两个星期，晚上老人小孩走路不安全，我想让相关部门来修"}
JSON
SKIPPED=0
if [ "${1:-}" = "--no-loop" ]; then
  echo "  ⏭  SKIPPED ×3：第一轮行动 / search_calls / 第二轮回执改变"
  echo "       （--no-loop 只验认证与边界，不花钱；这三项必须由完整那一轮判，记绿无效）"
  SKIPPED=3
else
T0=$(date +%s); post_round "$OUT/intent1.json" "$OUT/round1.json"; R1=$?
echo "  第一轮 HTTP=${RD_CODE:-?} 尝试 $RD_ATTEMPTS 次 耗时 $(( $(date +%s) - T0 ))s"
node -e '
const j=require("/opt/world-space/state/smoke/round1.json"); const a=j.next_action||{};
console.log("  next_action:", JSON.stringify(a.text||"").slice(0,100));
console.log("  done_when  :", JSON.stringify(a.done_when||"").slice(0,80), "| mode:", a.mode||"(空)");
process.exit(a.text && a.text.length>4 ? 0 : 1);
' 2>/dev/null; ckz "第一轮拿到真实行动（next_action 非空）" $? "见 $OUT/round1.json"
node -e 'const j=require("/opt/world-space/state/smoke/round1.json");const m=j.meta||{};
process.exit((m.search_calls||0)>0 ? 0 : 1)' 2>/dev/null
ckz "第一轮真的发生了搜索调用（meta.search_calls>0 → 新 key 走通）" $? \
  "meta=$(node -e 'const j=require("/opt/world-space/state/smoke/round1.json");console.log(JSON.stringify(j.meta||{}))' 2>/dev/null)"

cat > "$OUT/intent2.json" <<'JSON'
{"intent":"我们小区门口的路灯坏了两个星期，晚上老人小孩走路不安全，我想让相关部门来修",
 "receipt":{"status":"stuck","text":"打了物业电话，对方说路灯不归他们管，让我去找别的部门，没有给任何编号或书面答复"}}
JSON
T0=$(date +%s); post_round "$OUT/intent2.json" "$OUT/round2.json"; R2=$?
echo "  第二轮 HTTP=${RD_CODE:-?} 尝试 $RD_ATTEMPTS 次 耗时 $(( $(date +%s) - T0 ))s"
node -e '
const r1=require("/opt/world-space/state/smoke/round1.json"), r2=require("/opt/world-space/state/smoke/round2.json");
const m=r2.meta||{}, t1=(r1.next_action||{}).text||"", t2=(r2.next_action||{}).text||"";
console.log("  receipt_ingested =", m.receipt_ingested, "| receipt_status =", m.receipt_status);
console.log("  第二轮行动:", JSON.stringify(t2).slice(0,100));
console.log("  与第一轮不同:", t2 && t1 !== t2);
require("fs").writeFileSync("/opt/world-space/state/smoke/.r2ok", (m.receipt_ingested===true && t2 && t1!==t2)?"1":"0");
' 2>/dev/null
ck "第二轮 receipt_ingested=true 且行动真的改变（没重答第一轮）" \
   "$([ -f "$OUT/.r2ok" ] && [ "$(cat "$OUT/.r2ok")" = 1 ] && echo 1 || echo 0)" "见 $OUT/round2.json"
fi

# ---------- 退出与吊销 ----------
echo "=== logout 与旧 cookie 吊销 ==="
curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 -X POST -H "Cookie: $TOKA" "$H/api/auth/logout" > "$OUT/logout.code"
AFTER=$(curl -s -o "$OUT/after-logout.json" -w '%{http_code}' --max-time 8 -X POST -H "Cookie: $TOKA" \
        -H 'content-type: application/json' --data-binary @"$OUT/intent1.json" "$H/api/world")
ck "logout 后旧 cookie 调 /api/world → 401（服务端真吊销）" "$([ "$AFTER" = "401" ] && echo 1 || echo 0)" "$AFTER"
ROOTC=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Cookie: $TOKA" "$H/")
ck "logout 后旧 cookie 打开首页 → 送回 /login" "$([ "$ROOTC" = "302" ] && echo 1 || echo 0)" "$ROOTC"
curl -s -D - -o /dev/null --max-time 8 "$H/" | grep -i '^cache-control' | tr -d '\r' | tee "$OUT/cc.txt"
grep -qi 'no-store' "$OUT/cc.txt"; ckz "页面响应带 no-store（后退不显示上一次内容）" $? "$(cat "$OUT/cc.txt")"

# ---------- B 用户与身份隔离 ----------
echo "=== B 登录与身份隔离 ==="
PWB=$(sed -n 's/^B 账号.*密码: //p' "$PRIV/first-login.txt")
node -e 'const p=JSON.stringify({username:"test",password:process.argv[1]});require("fs").writeFileSync(process.argv[2],p)' "$PWB" "$OUT/loginB.json"
curl -s -D "$OUT/loginB.hdr" -o /dev/null --max-time 10 -X POST -H 'content-type: application/json' \
  --data-binary @"$OUT/loginB.json" "$H/api/auth/login"
TOKB=$(echo "$(grep -i '^set-cookie:' "$OUT/loginB.hdr" | head -1 | tr -d '\r')" | sed -n 's/^[Ss]et-[Cc]ookie: \([^;]*\)=\([^;]*\);.*/\2/p')
[ -n "$TOKB" ] || { echo "  （TOKB 取空，检查 B 的 Set-Cookie 是否下发）"; }
MEB=$(curl -s --max-time 8 -H "Cookie: ws_sess=$TOKB" "$H/api/auth/me")
echo "  B 的身份: $MEB"
echo "$MEB" | grep -q 'u-guest'; ckz "B 认到 u-guest（与 A 不同主）" $? "$MEB"
ck "A 与 B 是两个不同的会话令牌" "$([ -n "$TOKB" ] && [ "$TOKA" != "ws_sess=$TOKB" ] && echo 1 || echo 0)" "TOKB 为空或两者相同"
XCOOKIE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Cookie: ws_sess=${TOKB%.*}.tampered" "$H/api/auth/me")
ck "篡改签名后的 cookie 一律不认" "$([ "$XCOOKIE" = "401" ] && echo 1 || echo 0)" "$XCOOKIE"
grep -oE "ws\.loop\.v1:[^,;)]{0,28}" "$REL/web/v2/app.js" | head -2 | sed 's/^/  前端回路键前缀: /'

# ---------- CORS ----------
echo "=== CORS / 来源边界 ==="
EVIL=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -X POST -H 'content-type: application/json' \
       -H 'Origin: https://evil.example' -d '{"intent":"cors probe"}' "$H/api/world")
ck "陌生来源 https://evil.example → 403" "$([ "$EVIL" = "403" ] && echo 1 || echo 0)" "$EVIL"
GOODH=$(curl -s -D - -o /dev/null --max-time 8 -X POST -H 'content-type: application/json' \
        -H 'Origin: https://ymai.fun' -d '{"intent":"cors probe"}' "$H/api/world" | tr -d '\r')
echo "$GOODH" | grep -i '^access-control-allow-origin' | tail -1 | sed 's/^/  正式来源: /'
echo "$GOODH" | grep -qi "access-control-allow-origin: \*"; WILD=$?
ck "响应里不存在 access-control-allow-origin: '*'" "$([ "$WILD" = 1 ] && echo 1 || echo 0)" "命中通配"
echo "$GOODH" | grep -qi 'access-control-allow-credentials'; CREDC=$?
ck "不下发 access-control-allow-credentials（跨源带凭据在浏览器层不可能）" \
   "$([ "$CREDC" = 1 ] && echo 1 || echo 0)" "命中 allow-credentials"

# ---------- 预算与账本 ----------
echo "=== 预算（两份账本相加才是真实月度花费）==="
for pair in "本机实例:$PORT" "公网实例:3200"; do
  name=${pair%%:*}; p=${pair##*:}
  curl -s --max-time 8 "http://127.0.0.1:$p/healthz" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
console.log(`  ${process.argv[1]}: today=${j.today_calls} month_cost=¥${j.month_cost_rmb} cap=${j.daily_cap}/day ¥${j.monthly_cap_rmb}/month fail_closed=${j.fail_closed} auth=${j.auth}`);});' "$name"
done

cleanup; PID=""
echo "=== 汇总 ==="
echo "PASS=$pass FAIL=$fail SKIPPED=$SKIPPED"
if [ "$SKIPPED" != 0 ]; then
  echo "LOCAL_SMOKE=PARTIAL（跳过 $SKIPPED 项真实回路检查）—— 这一轮**不能**当验收，只证明认证与边界没坏"
elif [ "$fail" = 0 ]; then
  echo "LOCAL_SMOKE=PASS（服务器本机正式配置实例，含真实两轮回路与搜索）"
else
  echo "LOCAL_SMOKE=FAIL（见上面 ✗ 行，不许把 ✗ 当历史噪音）"
fi
