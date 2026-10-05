#!/usr/bin/env bash
# World Space 切流（Founder 明示批准后执行）
#
# 边界（写死在这里，不给临场判断留缝）：
#   动：/opt/world-space/current 符号链接、world-space.service 的一次重启、（可选）session 签名密钥轮换
#   不动：DNS、解析记录、nginx 站点配置、其它任何站点、共享账本、旧 release 目录
#   绝不：把 current 指向无访问门的旧版本（85c7b91 / 6e73725 / main Pages 都不是退路）
#
# 关站条件收窄（2026-10-05 改的就是这一条）：
#   只有 ws-verify-faces.sh 返回 5（公网面确实探测不到服务）才允许 emergency close。
#   返回 2/3/4 代表「我的判据不过」或「两个面自相矛盾」——那是**保留现场等人判断**的状态。
#   旧版把这些一并送去关站，会在一次正确部署上把站点自己关掉：healthz-only 版本把
#   auth／search_keys／fail_closed 从公网 3200 挪到 loopback 3201 之后，旧断言在公网面上
#   必然找不到它们 → 误判失败 → 自动 503。
#
# 同时兼容两种 release：
#   dual_face（healthz-only 及以后）    公网面只应有 {"ok":true}，详细诊断在 3201
#   legacy_single_face（e8284c4 及更早）诊断字段仍在公网面上、没有 3201 —— 这是**旧版回滚状态**，
#     不是新版的失败：打印 WARN=LEGACY_SINGLE_FACE，按旧版规则继续验门。
set -uo pipefail

ROOT="${WS_ROOT:-/opt/world-space}"
STATE="$ROOT/state"
EMERG="${WS_EMERG:-/usr/local/bin/world-space-emergency.sh}"
VERIFY="${WS_VERIFY:-/usr/local/bin/ws-verify-faces.sh}"
ROTATE_SECRET="${WS_ROTATE_SECRET:-0}"          # 默认 0 = 不轮换（现有登录不掉线）；只有显式 WS_ROTATE_SECRET=1 才轮换
RESTART_CMD="${WS_RESTART_CMD:-systemctl restart world-space.service}"
PID_CMD="${WS_PID_CMD:-systemctl show -p MainPID --value world-space.service}"
PUBLIC_PORT="${WS_PUBLIC_PORT:-3200}"
OPS_PORT="${WS_OPS_PORT:-3201}"
POLL_TRIES="${WS_POLL_TRIES:-200}"              # 200 × 0.2s ≈ 40s 上限
# 纳秒时间戳；某些 Windows/BusyBox 的 date 不认 %N，退化成整秒而不是产出垃圾串
now_ns() {
  local v; v=$(date +%s%N 2>/dev/null || echo "")
  case "$v" in
    ''|*[!0-9]*) v=$(( $(date +%s) * 1000000000 )) ;;
  esac
  printf '%s' "$v"
}
SHA=$(cat "$STATE/approved-sha" 2>/dev/null || true)
REL=$ROOT/releases/$SHA
LIVE=$(readlink "$ROOT/current" 2>/dev/null || echo none)

[ -n "$SHA" ]    || { echo "FAIL: 没有登记批准点（先跑 ws-prep.sh verify）"; exit 1; }
[ -d "$REL" ]    || { echo "FAIL: 批准树不存在 $REL"; exit 1; }
[ -x "$EMERG" ]  || { echo "FAIL: 关站脚本不在位，切流前必须先装好回滚方案"; exit 1; }
[ -f "$VERIFY" ] || { echo "FAIL: 双面核验器不在位（$VERIFY）"; exit 1; }

echo "批准点：$SHA"
echo "当前线上：$(basename "$LIVE")"

# 0) 切之前先读目标代码，判它该是哪个面（静态探针，不碰服务）
TARGET_FACE=legacy_single_face
if [ "$(grep -c 'opsPort' "$REL/server/world.mjs" 2>/dev/null || true)" -gt 0 ]; then TARGET_FACE=dual_face; fi
echo "目标面形状（读代码）：$TARGET_FACE"
if [ "$TARGET_FACE" = "legacy_single_face" ]; then
  echo "  WARN: 目标是旧版单面，诊断字段仍在公网上（未登录可读 provider／预算／用量）。"
fi
export WS_TARGET_REL="$REL" WS_PUBLIC_PORT="$PUBLIC_PORT" WS_OPS_PORT="$OPS_PORT"

# 1) 可选：轮换 session 签名密钥，让此前泄漏过／打印过的令牌全部失效
if [ "$ROTATE_SECRET" = "1" ]; then
  echo "=== 1) 轮换会话签名密钥（作废所有旧令牌）==="
  head -c 48 /dev/urandom | base64 > "$ROOT/etc/session-secret.txt"
  chmod 600 "$ROOT/etc/session-secret.txt"; chown wsapp:wsapp "$ROOT/etc/session-secret.txt"
  echo "  已重写（值不回显）。所有账号需要重新登录一次，口令不变。"
else
  echo "=== 1) 跳过 session 密钥轮换（WS_ROTATE_SECRET 未设置或为 0：现有登录令牌继续有效）==="
fi

# 2) 切版本 + 重启，并量出真实中断时长
echo "=== 2) 换 current 并重启 ==="
ln -sfn "$REL" "$ROOT/current"
echo "  current: $(basename "$LIVE") -> $(basename "$(readlink "$ROOT/current")")"
T0=$(now_ns)
$RESTART_CMD
OK=no
for _ in $(seq 1 "$POLL_TRIES"); do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PUBLIC_PORT/healthz"; then OK=yes; break; fi
  sleep 0.2
done
T1=$(now_ns)
REC=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.2f", (b-a)/1000000000}')
echo "  恢复探测：$([ "$OK" = yes ] && echo 成功 || echo 失败)（$REC 秒）"

# 3) 双面核验（只读）。按退出码动作，不读中文。
echo "=== 3) 双面核验 ==="
export WS_EXPECT_PID
WS_EXPECT_PID=$($PID_CMD 2>/dev/null || true)
VC=5
if [ "$OK" = "yes" ]; then
  bash "$VERIFY"; VC=$?
else
  echo "  公网面在轮询窗口内没起来 → 按不可用处理（这是唯一允许关站的情形）"
fi
echo "  核验退出码：$VC"

# 4) 留档（不写响应正文：里面有花费数字，没必要落在 state 里）
mkdir -p "$STATE"
REC_FILE="$STATE/cutover-$(date +%Y%m%d-%H%M%S).txt"
{ date -u +%FT%TZ
  echo "approved=$SHA"
  echo "previous=$(basename "$LIVE")"
  echo "target_face=$TARGET_FACE"
  echo "recovery_s=$REC"
  echo "verify_exit=$VC"
  echo "session_secret_rotated=$ROTATE_SECRET"
} > "$REC_FILE"
echo "  留档：$REC_FILE"

case "$VC" in
  0)
    echo "=== 切流完成 ==="
    echo "CUTOVER=OK  线上现在是 $SHA（面形状 $TARGET_FACE）"
    echo "  关站（一条命令）：$EMERG close"
    echo "  撤销关站：$EMERG restore"
    echo "  版本级回退只允许在本系列内含访问门的提交之间进行，$LIVE 不是安全回滚目标"
    exit 0 ;;
  5)
    echo "=== 公网面确实不可用：按 §10 宁可关站，也不回无门公开版（不把 current 切回 $LIVE）==="
    "$EMERG" close
    echo "CUTOVER=FAILED_AND_CLOSED  现场留在此状态等人判断，不自动重试"
    exit 1 ;;
  *)
    echo "=== 核验未过（退出码 $VC）：保留现场，不关站 ==="
    echo "  这一类代表判据不过或两个面自相矛盾，不代表服务挂了。"
    echo "  关站会把一次可诊断的部署变成没人看得见的 503；要关，由人判断之后再关。"
    echo "  现在 current=$(basename "$(readlink "$ROOT/current")")  撤销用：$EMERG restore"
    echo "CUTOVER=FAILED_SCENE_PRESERVED"
    exit 1 ;;
esac
