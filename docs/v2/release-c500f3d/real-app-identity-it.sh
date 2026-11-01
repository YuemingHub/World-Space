#!/usr/bin/env bash
# real-app-identity-it.sh —— 真应用身份闭环集成测试（不是假面 fixture，跑发布树里真实的 server/world.mjs）。
#
# 证明的是 P0 的闭环：进程自报的 release_id 必须等于"对批准发布树独立算出的 release_id"，
# 且身份不符 / 旧进程 / pid 不符三种情形都拿不到 exit 0。
#
# 前置：REL 指向一棵由 git archive <commit> 解出的发布树（默认 /approve），树里带着
#       docs/v2/release-c500f3d/release-id.mjs 与 ws-verify-faces.sh。
# 用法：REL=/path/to/release-tree bash real-app-identity-it.sh
# 退出码：0 = 全部断言成立；非 0 = 断言不成立项数。
set -u
REL=${REL:-/approve}
TOOL="$REL/docs/v2/release-c500f3d"
PUB=3200
OPS=3201
FAILS=0
ck() { # ck <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf 'PASS %-42s = %s\n' "$1" "$2";
  else printf 'FAIL %-42s = %s (expect %s)\n' "$1" "$2" "$3"; FAILS=$((FAILS+1)); fi
}
jget() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log(j[process.argv[1]]??"")}catch(e){console.log("ERR")}})' "$1"; }

echo "=== 0) 准备：用户文件 + session 密钥（一律在发布树之外） ==="
CFG=${CFG:-$(mktemp -d /tmp/idt-cfg.XXXXXX)}; STAT=${STAT:-$(mktemp -d /tmp/idt-state.XXXXXX)}
mkdir -p "$CFG" "$STAT"
printf '%s' 'fixture-password-123' | node "$REL/scripts/hash-password.mjs" u_demo demo > /tmp/u.json \
  || { echo "FAIL hash-password"; exit 1; }
node -e 'const fs=require("fs");const u=JSON.parse(fs.readFileSync("/tmp/u.json","utf8"));fs.writeFileSync(process.argv[1]+"/users.json",JSON.stringify({users:[u]},null,2))' "$CFG"
node -e 'console.log(require("crypto").randomBytes(36).toString("base64url"))' > $CFG/secret
ls -l $CFG/users.json $CFG/secret
SECLEN=$(node -e 'console.log(require("fs").readFileSync(process.argv[1]+"/secret","utf8").trim().length)' "$CFG")
ck "session_secret_length_ge_32" "$SECLEN" "$( [ "$SECLEN" -ge 32 ] && echo "$SECLEN" )"

echo "=== 1) 独立算出批准树身份（与运行进程无关） ==="
APPROVED_ID=$(node "$TOOL/release-id.mjs" "$REL")
echo "APPROVED_RELEASE_ID=$APPROVED_ID"
printf '%s' "$APPROVED_ID" | grep -Eq '^[0-9a-f]{64}$' && echo "PASS approved_tree_identity_shape" || { echo FAIL approved_tree_identity_shape; FAILS=$((FAILS+1)); }

echo "=== 2) 启动真应用（发布树内代码，0 本地补丁） ==="
START_AFTER=$(( $(date +%s%3N) - 2000 ))
echo "$START_AFTER" > /tmp/start-after
setsid env WS_HOST=127.0.0.1 WS_PORT=$PUB WS_OPS_PORT=$OPS \
  WS_PROVIDER=stub WS_SEARCH=fixture WS_STATE_FILE=$STAT/budget.json \
  WS_AUTH_USERS_FILE=$CFG/users.json WS_SESSION_SECRET_FILE=$CFG/secret \
  WS_RATE_LIMIT=1000 \
  node "$REL/server/world.mjs" > /tmp/app.log 2>&1 &
echo $! > /tmp/app.pid
APP_PID=$(cat /tmp/app.pid)
echo "APP_PID=$APP_PID  START_AFTER=$START_AFTER"
for i in $(seq 1 60); do
  curl -s -o /dev/null -w '' "http://127.0.0.1:$PUB/healthz" && break
  sleep 0.25
done
echo "--- app.log (head) ---"; head -20 /tmp/app.log
curl -s "http://127.0.0.1:$PUB/healthz"; echo
OPSBODY=$(curl -s "http://127.0.0.1:$OPS/healthz")
echo "--- ops/healthz ---"; printf '%s\n' "$OPSBODY"

echo "=== 3) 运行中身份 vs 批准树身份 ==="
RUN_ID=$(printf '%s' "$OPSBODY" | jget release_id)
RUN_SCHEME=$(printf '%s' "$OPSBODY" | jget release_id_scheme)
RUN_PID=$(printf '%s' "$OPSBODY" | jget pid)
RUN_START=$(printf '%s' "$OPSBODY" | jget started_at_ms)
RUN_FACE=$(printf '%s' "$OPSBODY" | jget diagnostic_face)
echo "RUNNING: id=$RUN_ID scheme=$RUN_SCHEME pid=$RUN_PID started=$RUN_START face=$RUN_FACE"
ck "runtime_release_id_equals_approved_tree" "$RUN_ID" "$APPROVED_ID"
ck "runtime_release_id_scheme" "$RUN_SCHEME" "world-release-tree-v1"
ck "runtime_pid_is_the_process_we_started" "$RUN_PID" "$APP_PID"
ck "runtime_diagnostic_face" "$RUN_FACE" "ops-v1"
if [ -n "$RUN_START" ] && [ "$RUN_START" -ge "$START_AFTER" ]; then echo "PASS runtime_started_after_cutover = $RUN_START >= $START_AFTER"; else echo "FAIL runtime_started_after_cutover = $RUN_START"; FAILS=$((FAILS+1)); fi

echo "=== 4) 核验器（WS_TARGET_REL=发布树）→ 期望 exit 0 ==="
WS_TARGET_REL="$REL" WS_EXPECT_PID="$APP_PID" WS_EXPECT_START_AFTER="$START_AFTER" \
WS_GATE_BASE="http://127.0.0.1:$PUB" WS_RESOLVE_HOST="" \
bash "$TOOL/ws-verify-faces.sh" > /tmp/verify-green.log 2>&1
RC=$?
cat /tmp/verify-green.log
ck "verifier_exit_equals_0" "$RC" "0"

echo "=== 5) 反例 F：树被改一个字节（模拟"跑的不是批准的那份字节"）→ 期望 exit 2 ==="
BAD="${REL}-bad"
rm -rf "$BAD"; cp -a "$REL" "$BAD"
printf '\n// tamper: one extra line\n' >> "$BAD/server/world.mjs"
WS_TARGET_REL="$BAD" WS_EXPECT_PID="$APP_PID" WS_EXPECT_START_AFTER="$START_AFTER" \
WS_GATE_BASE="http://127.0.0.1:$PUB" WS_RESOLVE_HOST="" \
bash "$TOOL/ws-verify-faces.sh" > /tmp/verify-mismatch.log 2>&1
RC=$?
cat /tmp/verify-mismatch.log
ck "verifier_exit_equals_2" "$RC" "2"
grep -q "ops_release_id_matches_approved *FAIL" /tmp/verify-mismatch.log && echo "PASS mismatch_reported_as_identity_fail" || { echo "FAIL mismatch_reported_as_identity_fail"; FAILS=$((FAILS+1)); }

echo "=== 6) 反例 B：进程是旧进程（期望启动时间在未来）→ 期望 exit 2 ==="
FUTURE=$(( $(date +%s%3N) + 30000 ))
WS_TARGET_REL="$REL" WS_EXPECT_PID="$APP_PID" WS_EXPECT_START_AFTER="$FUTURE" \
WS_GATE_BASE="http://127.0.0.1:$PUB" WS_RESOLVE_HOST="" \
bash "$TOOL/ws-verify-faces.sh" > /tmp/verify-oldproc.log 2>&1
RC=$?
cat /tmp/verify-oldproc.log
ck "verifier_exit_equals_2 (old process)" "$RC" "2"
grep -q "ops_started_after_cutover *FAIL" /tmp/verify-oldproc.log && echo "PASS old_process_reported" || { echo "FAIL old_process_reported"; FAILS=$((FAILS+1)); }

echo "=== 7) 反例：pid 不符（诊断面不属于被核验进程）→ 期望 exit 2 ==="
WS_TARGET_REL="$REL" WS_EXPECT_PID="$((APP_PID+1))" WS_EXPECT_START_AFTER="$START_AFTER" \
WS_GATE_BASE="http://127.0.0.1:$PUB" WS_RESOLVE_HOST="" \
bash "$TOOL/ws-verify-faces.sh" > /tmp/verify-pid.log 2>&1
RC=$?
ck "verifier_exit_equals_2 (pid mismatch)" "$RC" "2"
grep -q "ops_pid_matches_service *FAIL" /tmp/verify-pid.log && echo "PASS pid_mismatch_reported" || { echo "FAIL pid_mismatch_reported"; FAILS=$((FAILS+1)); }

echo "=== 8) 收尾：杀掉本次启动的进程 ==="
kill "$APP_PID" 2>/dev/null
sleep 0.5
kill -0 "$APP_PID" 2>/dev/null && { echo "FAIL app still alive"; FAILS=$((FAILS+1)); } || echo "PASS app stopped"

echo "=== 汇总 ==="
echo "REAL_APP_IDENTITY_IT_FAILS=$FAILS"
[ "$FAILS" -eq 0 ] && echo "REAL_APP_IDENTITY_IT=PASS" || echo "REAL_APP_IDENTITY_IT=FAIL"
exit "$FAILS"
