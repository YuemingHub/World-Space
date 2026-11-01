#!/usr/bin/env bash
# 公网真实冒烟：经 nginx + TLS 走完整用户路径（切流之后跑）
#
# 为什么还要单独跑这一遍：之前那一轮直连 127.0.0.1:3210，绕过了 nginx。
# 真实用户走的是 https://ymai.fun → nginx → Node，Secure cookie、X-Forwarded 头、
# 反代超时这些只有从公网这一侧才测得到。
set -uo pipefail
P=443
H="https://ymai.fun"
R="--resolve ymai.fun:443:127.0.0.1"
OUT=/opt/world-space/state/public
PRIV=/opt/world-space/etc
mkdir -p "$OUT"
pass=0; fail=0
ck() { if [ "$2" = "1" ]; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1 —— $3"; fail=$((fail+1)); fi; }
ckz() { ck "$1" "$([ "$2" = 0 ] && echo 1 || echo 0)" "$3"; }

echo "=== 未登录 ==="
rc=$(curl -s $R -o /dev/null -w '%{http_code}' --max-time 20 "$H/")
ck "GET / → 302 到登录页" "$([ "$rc" = "302" ] && echo 1 || echo 0)" "$rc"
api=$(curl -s $R -o "$OUT/unauth.json" -w '%{http_code}' --max-time 20 -X POST \
     -H 'content-type: application/json' -d '{"intent":"public probe"}' "$H/api/world")
ck "未登录 POST /api/world → 401（无门版本这里是 200，那正是本次发布要修的）" \
   "$([ "$api" = "401" ] && echo 1 || echo 0)" "$api $(head -c 80 "$OUT/unauth.json")"

echo "=== 登录（真实口令，值不回显）==="
PW=$(sed -n 's/^A 账号.*密码: //p' "$PRIV/first-login.txt")
node -e 'const fs=require("fs");fs.writeFileSync("/tmp/pl.json",JSON.stringify({username:"ymai",password:process.argv[1]}))' "$PW"
code=$(curl -s $R -D "$OUT/login.hdr" -o /dev/null -w '%{http_code}' --max-time 20 -X POST \
  -H 'content-type: application/json' --data-binary @/tmp/pl.json "$H/api/auth/login")
rm -f /tmp/pl.json
ck "正确口令登录 → $code" "$([ "$code" = "200" ] && echo 1 || echo 0)" "$(grep -ci '^set-cookie' "$OUT/login.hdr") 行 set-cookie（令牌值不外泄）"
CK=$(grep -i '^set-cookie:' "$OUT/login.hdr" | head -1 | tr -d '\r')
for f in httponly secure samesite=lax; do echo "$CK" | grep -qi "$f"; ckz "TLS 下发的 cookie 带 $f" $? ""; done
TOK=$(echo "$CK" | sed -n 's/^[Ss]et-[Cc]ookie: \([^;]*\)=\([^;]*\);.*/\1=\2/p')
page=$(curl -s $R -H "Cookie: $TOK" --max-time 20 "$H/")
echo "$page" | grep -q '你现在想做成什么'; ckz "登录后首页出现「你现在想做成什么？」" $? "页面无此句"
me=$(curl -s $R -H "Cookie: $TOK" --max-time 20 "$H/api/auth/me")
echo "$me" | grep -q 'u-owner'; ckz "身份认到 u-owner（经 nginx）" $? "$me"

echo "=== 真实两轮回路（经 nginx，会产生真实花费）==="
cat > "$OUT/i1.json" <<'JSON'
{"intent":"我家老人在小区里被坏路灯绊过一次，我想让物业或相关部门把这条路灯修好"}
JSON
post() { n=0; while [ "$n" -lt 4 ]; do n=$((n+1))
    c=$(curl -s $R -H "Cookie: $TOK" -H 'content-type: application/json' \
        --data-binary @"$1" "$H/api/world" -o "$2" -w '%{http_code}' --max-time 180)
    [ "$c" = "200" ] && return 0
    echo "    第 $n 次 HTTP $c：$(head -c 80 "$2")"; ATTEMPTS=$n
    [ "$c" = "502" ] || return 1; sleep 45
  done; return 1; }
ATTEMPTS=0
t0=$(date +%s); post "$OUT/i1.json" "$OUT/r1.json"; r1=$?
echo "  第一轮 HTTP=$c 尝试 $((ATTEMPTS+1)) 次 耗时 $(( $(date +%s) - t0 ))s"
node -e 'const j=require("/opt/world-space/state/public/r1.json");const a=j.next_action||{};
console.log("  行动:",JSON.stringify(a.text||"").slice(0,90));console.log("  做完:",JSON.stringify(a.done_when||"").slice(0,80),"| mode:",a.mode||"");
process.exit(a.text&&a.done_when?0:1)' 2>/dev/null; ckz "第一轮拿到真实行动与可验证的 done_when" $? "见 r1.json"
node -e 'const j=require("/opt/world-space/state/public/r1.json");process.exit(((j.meta||{}).search_calls||0)>0?0:1)' 2>/dev/null
ckz "公网这一轮真的发生了搜索（钥匙有效）" $? "meta=$(node -e 'const j=require("/opt/world-space/state/public/r1.json");console.log(JSON.stringify(j.meta||{}))' 2>/dev/null)"

cat > "$OUT/i2.json" <<'JSON'
{"intent":"我家老人在小区里被坏路灯绊过一次，我想让物业或相关部门把这条路灯修好",
 "receipt":{"status":"stuck","text":"物业说路灯归市政管，让我自己打热线，没有给任何编号"}}
JSON
ATTEMPTS=0; t0=$(date +%s); post "$OUT/i2.json" "$OUT/r2.json"; r2=$?
echo "  第二轮 HTTP=$c 尝试 $((ATTEMPTS+1)) 次 耗时 $(( $(date +%s) - t0 ))s"
node -e '
const r1=require("/opt/world-space/state/public/r1.json"), r2=require("/opt/world-space/state/public/r2.json");
const t1=(r1.next_action||{}).text||"", t2=(r2.next_action||{}).text||"", m=r2.meta||{};
console.log("  receipt_ingested =",m.receipt_ingested,"| status =",m.receipt_status,"| 两轮长度",t1.length,t2.length);
console.log("  第二轮行动:",JSON.stringify(t2).slice(0,90));
require("fs").writeFileSync("/opt/world-space/state/public/.ok",(m.receipt_ingested===true&&t1&&t2&&t1!==t2)?"1":"0");
' 2>/dev/null
ck "第二轮吸收了回执、且没把第一轮重答一遍" \
   "$([ -f "$OUT/.ok" ] && [ "$(cat "$OUT/.ok")" = 1 ] && echo 1 || echo 0)" "见 r2.json"

echo "=== 刷新恢复与退出 ==="
page2=$(curl -s $R -H "Cookie: $TOK" --max-time 20 "$H/")
echo "$page2" | grep -q '你现在想做成什么'; ckz "刷新后仍回到自己的页面（正文由本人本机回路恢复）" $? ""
curl -s $R -o /dev/null -w '  logout → %{http_code}\n' -X POST -H "Cookie: $TOK" --max-time 20 "$H/api/auth/logout"
after=$(curl -s $R -o /dev/null -w '%{http_code}' -X POST -H "Cookie: $TOK" \
        -H 'content-type: application/json' --data-binary @"$OUT/i1.json" "$H/api/world" --max-time 20)
ck "退出后旧 cookie 调接口 → 401（令牌已在服务端吊销）" "$([ "$after" = "401" ] && echo 1 || echo 0)" "$after"

echo "=== 账本 ==="
curl -s --max-time 10 http://127.0.0.1:3200/healthz | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(`  线上 today=${j.today_calls} month=¥${j.month_cost_rmb} cap=${j.daily_cap}/¥${j.monthly_cap_rmb} fail_closed=${j.fail_closed} auth=${j.auth} keys=${j.search_keys}`);});'
echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ] && echo "PUBLIC_SMOKE=PASS" || echo "PUBLIC_SMOKE=FAIL"
