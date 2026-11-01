#!/usr/bin/env bash
# emergency-rollback-identityless.sh —— 退回"不带发布身份"的旧版（带外应急通道）。
#
# 适用场景：线上是 R4（带 identity），而唯一可信的回滚目标是生产旧版 3e8e15f（没有 release_id 能力）。
# 标准 cutover 不允许把无身份版本当回滚目标（无法证明"正在服务的是它"），所以这里走显式带外通道：
# 写清楚它证明不了什么，并把"证明不了"本身写进回执。
#
# 与标准回滚的分界（不许混用）：
#   - 标准回滚：ws-prep.sh verify 登记 → cutover.sh（WS_MODE=rollback + WS_ROLLBACK_TO 两把钥匙），
#     要求目标带 identity；成功后 running release_id == 目标身份。
#   - 本脚本：只用于 identity 缺失的旧版。成功判据只能是"公网面健康 + 旧版面形状 + 诊断面无 release_id"，
#     不能声称"已证明是那一份字节在服务"。
#
# 用法（生产）：
#   sudo WS_ALLOW_IDENTITYLESS_ROLLBACK=yes WS_ROOT=/opt/world-space WS_TARGET_SHA=3e8e15f1... \
#        WS_RESTART_CMD="systemctl restart world-space" \
#        bash docs/v2/release-c500f3d/emergency-rollback-identityless.sh
#
# 退出码：0 OK / 2 用法 / 3 前置判据不过（零写入）/ 4 服务未起（现场保留，不删任何东西）
set -uo pipefail

ROOT=${WS_ROOT:-/opt/world-space}
TARGET=${WS_TARGET_SHA:-}
RESTART=${WS_RESTART_CMD:-systemctl restart world-space}
PUBLIC_PORT=${WS_PUBLIC_PORT:-3200}
OPS_PORT=${WS_OPS_PORT:-3201}
STATE="$ROOT/state"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
log() { printf '%s\n' "$*"; }
abort() { log "EMERGENCY_ROLLBACK=ABORT_$1  $2"; exit 3; }

[ "${WS_ALLOW_IDENTITYLESS_ROLLBACK:-}" = "yes" ] \
  || abort SECOND_KEY_MISSING "带外回退必须显式给 WS_ALLOW_IDENTITYLESS_ROLLBACK=yes（这是第二把钥匙，防误用）"
grep -Eq '^[0-9a-f]{40}$' <<<"$TARGET" \
  || abort TARGET_INVALID "WS_TARGET_SHA 必须是完整 40 位提交号：'$TARGET'"
[ -d "$ROOT" ] || abort ROOT_MISSING "WS_ROOT=$ROOT 不存在"
[ -d "$ROOT/releases/$TARGET" ] && [ ! -L "$ROOT/releases/$TARGET" ] \
  || abort TARGET_TREE_MISSING "发布目录不存在或不是真实目录：$ROOT/releases/$TARGET"
REL=$(cd "$ROOT/releases/$TARGET" 2>/dev/null && pwd -P) || abort TARGET_TREE_MISSING "读不了目标树"
REL_ROOT=$(cd "$ROOT/releases" 2>/dev/null && pwd -P) || abort RELEASES_MISSING "读不了 $ROOT/releases"
case "$REL" in "$REL_ROOT"/*) ;; *) abort PATH_ESCAPE "目标树物理位置 $REL 不在 $ROOT/releases 内" ;; esac
# 目标必须"确实没有身份能力"：有 identity 的版本必须走标准回滚，不许用这条通道绕过两把钥匙
[ -f "$REL/server/world.mjs" ] || abort TARGET_TREE_MISSING "目标树里没有 server/world.mjs"
if grep -q 'release_id_scheme' "$REL/server/world.mjs" 2>/dev/null; then
  abort TARGET_HAS_IDENTITY "目标树带发布身份能力（$TARGET）：请走标准回滚 cutover.sh（WS_MODE=rollback + WS_ROLLBACK_TO）"
fi

jget() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const v=j[process.argv[1]];console.log(typeof v==="undefined"?"":String(v))}catch(e){console.log("")}})' "$1"; }
ops_json() { curl -s --max-time 3 "http://127.0.0.1:$OPS_PORT/healthz" 2>/dev/null || true; }
pub_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:$PUBLIC_PORT${1:-/healthz}" 2>/dev/null || echo 000; }

PRE_CURRENT=$(readlink "$ROOT/current" 2>/dev/null || true)
PRE_LIVE_SHA=$(printf '%s' "$PRE_CURRENT" | sed -n 's#.*/releases/\([0-9a-f]\{40\}\)$#\1#p')
PRE_OPS=$(ops_json)
PRE_PID=$(printf '%s' "$PRE_OPS" | jget pid)
PRE_ID=$(printf '%s' "$PRE_OPS" | jget release_id)
PRE_PUB=$(pub_code /healthz)
[ "$PRE_PUB" = "200" ] || abort PRE_SERVICE_NOT_HEALTHY "回退前公网面 /healthz=$PRE_PUB（不是 200）：先排查，别在坏现场上再叠一层"
[ -n "$PRE_LIVE_SHA" ] || abort PRE_LIVE_UNKNOWN "current 不是 releases/<40位提交号> 形状：'$PRE_CURRENT'"

mkdir -p "$STATE" || abort STATE_UNWRITABLE "写不了 $STATE"
REC="$STATE/emergency-rollback-$(date -u +%Y%m%dT%H%M%SZ).txt"
write_receipt() { # write_receipt <status> <service> <extra>
  {
    printf 'status=%s\n' "$1"
    printf 'at=%s\n' "$NOW"
    printf 'mode=emergency-rollback-identityless\n'
    printf 'from_sha=%s\n' "$PRE_LIVE_SHA"
    printf 'from_release_id=%s\n' "${PRE_ID:-unidentified}"
    printf 'from_pid=%s\n' "${PRE_PID:-unknown}"
    printf 'target_sha=%s\n' "$TARGET"
    printf 'target_release_id=unidentified\n'
    printf 'service=%s\n' "$2"
    printf 'identity_verified=no\n'
    printf '%s\n' "$3"
    printf 'receipt=%s\n' "$REC"
  } > "$REC" 2>/dev/null || true
}
# 先落回执再动手：任何一步失败，事后都能查到"当时从哪来、要去哪、做到哪一步"
write_receipt IN_PROGRESS pending "step=receipt-written"

ln -sfn "$ROOT/releases/$TARGET" "$ROOT/current" \
  || { write_receipt SWITCH_FAILED down "step=switch-current"; log "EMERGENCY_ROLLBACK=SWITCH_FAILED  current 没换成功，仍指向 $PRE_CURRENT"; exit 4; }
NOW_CURRENT=$(readlink "$ROOT/current")
[ "$NOW_CURRENT" = "$ROOT/releases/$TARGET" ] \
  || { write_receipt SWITCH_UNVERIFIED down "step=verify-current"; log "EMERGENCY_ROLLBACK=SWITCH_UNVERIFIED  current=$NOW_CURRENT"; exit 4; }

printf '%s' "$TARGET" > "$STATE/approved-sha" || true
printf 'sha=%s\nmode=emergency-rollback\nrelease_line=v2\nrelease_id=unidentified\nrollback_to=%s\n' \
  "$TARGET" "$PRE_LIVE_SHA" > "$STATE/approved-meta.txt" 2>/dev/null || true

bash -c "$RESTART" >/dev/null 2>&1
RESTART_RC=$?
UP=no
for i in $(seq 1 60); do
  [ "$(pub_code /healthz)" = "200" ] && { UP=yes; break; }
  sleep 0.5
done
POST_OPS=$(ops_json)
POST_PID=$(printf '%s' "$POST_OPS" | jget pid)
POST_ID=$(printf '%s' "$POST_OPS" | jget release_id)

if [ "$UP" != "yes" ]; then
  write_receipt SERVICE_DOWN down "step=restart restart_rc=$RESTART_RC current=$NOW_CURRENT"
  log "EMERGENCY_ROLLBACK=FAILED_SERVICE_DOWN  restart_rc=$RESTART_RC current=$NOW_CURRENT；现场保留（不删文件、不自动再试）"
  exit 4
fi
if [ -n "$POST_ID" ]; then
  # 旧版不该自报身份；若报了，说明换错了树 —— 留现场交人判断，不继续
  write_receipt UNEXPECTED_IDENTITY up "step=verify-identity release_id=$POST_ID restart_rc=$RESTART_RC"
  log "EMERGENCY_ROLLBACK=FAILED_UNEXPECTED_IDENTITY  目标自报 release_id=$POST_ID（本应无身份）；现场保留"
  exit 4
fi

write_receipt OK up "step=done restart_rc=$RESTART_RC from_pid=${PRE_PID:-?} to_pid=${POST_PID:-?} public_healthz=200"
log "EMERGENCY_ROLLBACK=OK  target=$TARGET  from=$PRE_LIVE_SHA  identity=absent  public_healthz=200  pid=${POST_PID:-?}"
log "  注意：本通道只能证明'旧版面在服务'，不能证明'是那一份字节'（旧版没有身份能力）。回执=$REC"
exit 0
