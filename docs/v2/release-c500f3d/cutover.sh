#!/usr/bin/env bash
# World Space 切流（Founder 明示批准后执行）
#
# 边界（写死在这里，不给临场判断留缝）：
#   动：/opt/world-space/current 符号链接、world-space.service 的一次重启、（可选）session 签名密钥轮换
#   不动：DNS、解析记录、nginx 站点配置、其它任何站点、共享账本、旧 release 目录
#   绝不：把 current 指向无访问门的旧版本（85c7b91 / 6e73725 / main Pages 都不是退路）
#
# 两条路径必须可区分（2026-11-01 收紧 P0-A）：
#   升级   WS_MODE=upgrade（默认）：批准点必须能解析成同一个提交对象、发布目录必须逐文件等于该提交的树、
#          必须是双面版本、必须包含发布线（refs/heads/v2）的最新提交、且必须是当前线上版本的后代。
#          任何一条不成立 → CUTOVER=ABORT_*，退出码 3，零写入（不换 current、不重启、不留档）。
#   回滚   WS_MODE=rollback 且 WS_ROLLBACK_TO=<40 位提交号>：两把钥匙必须同时给出，且都等于批准点。
#          目标必须是当前线上版本的祖先（真正的"往回走"）。这是唯一允许把 legacy 单面放上线的路径。
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
#     不是新版的失败：打印 WARN=LEGACY_SINGLE_FACE，按旧版规则继续验门。它只允许出现在回滚路径。
set -uo pipefail
# 只用真实对象关系判断祖先：replace refs 可以在 root 可写的缓存里伪造"谁是谁的祖先"
export GIT_NO_REPLACE_OBJECTS=1

ROOT="${WS_ROOT:-/opt/world-space}"
STATE="$ROOT/state"
CACHE="${WS_CACHE:-$ROOT/.git-cache/World-Space.git}"
RELEASE_LINE="${WS_RELEASE_LINE:-v2}"           # 发布线：升级目标必须包含它的最新提交
EMERG="${WS_EMERG:-/usr/local/bin/world-space-emergency.sh}"
VERIFY="${WS_VERIFY:-/usr/local/bin/ws-verify-faces.sh}"
MODE="${WS_MODE:-upgrade}"                      # upgrade | rollback，必须显式二选一
ROLLBACK_TO="${WS_ROLLBACK_TO:-}"               # 回滚的第二把钥匙：必须与批准点相同
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

abort() { # abort <大写下划线原因> <人话说明>   —— 退出码 3：判据不过，零写入
  echo "CUTOVER=ABORT_$1  $2"
  exit 3
}

is_sha() { printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$'; }

SHA=$(cat "$STATE/approved-sha" 2>/dev/null || true)
is_sha "$SHA" || abort APPROVED_SHA_INVALID "state/approved-sha 不是完整的 40 位提交号：'${SHA:-<空>}'（先跑 ws-prep.sh verify 登记批准的候选）"
REL=$ROOT/releases/$SHA
LIVE=$(readlink "$ROOT/current" 2>/dev/null || echo none)
LIVE_SHA=""
[ "$LIVE" = none ] || LIVE_SHA=$(basename "$LIVE")

[ -d "$REL" ]    || abort RELEASE_TREE_MISSING "批准树不存在 $REL"
[ -x "$EMERG" ]  || abort EMERGENCY_MISSING "关站脚本不在位（$EMERG），切流前必须先装好回滚方案"
[ -f "$VERIFY" ] || abort VERIFIER_MISSING "双面核验器不在位（$VERIFY）"
command -v git >/dev/null 2>&1 || abort GIT_MISSING "本机没有 git，无法验证目标身份"
[ -d "$CACHE" ]  || abort GIT_CACHE_MISSING "本机 git 缓存不在位（$CACHE）；先跑 ws-prep.sh fetch"
case "$MODE" in upgrade|rollback) ;; *) abort MODE_INVALID "WS_MODE=$MODE（只认 upgrade 或 rollback）" ;; esac
# 升级必须知道"从哪来"：current 缺失/不是符号链接时，前后代关系无从判断，不能当成"从零升级"
if [ "$MODE" = upgrade ]; then
  [ -L "$ROOT/current" ] && [ -n "$LIVE_SHA" ] \
    || abort LIVE_IDENTITY_UNKNOWN "没有可识别的 current（$ROOT/current 不存在或不是符号链接），无法判断这是不是一次前进"
fi

resolve_commit() { # <sha> → 打印该提交的完整 SHA；解析不了返回 1
  git -C "$CACHE" cat-file -e "$1^{commit}" 2>/dev/null || return 1
  git -C "$CACHE" rev-parse "$1^{commit}" 2>/dev/null
}
is_ancestor() { git -C "$CACHE" merge-base --is-ancestor "$1" "$2" 2>/dev/null; }

face_of_commit() { # dual_face | legacy_single_face（读提交里的代码，不读可被改的工作副本）
  local n
  n=$(git -C "$CACHE" cat-file blob "$1:server/world.mjs" 2>/dev/null | grep -c 'opsPort' || true)
  [ "${n:-0}" -gt 0 ] && printf 'dual_face' || printf 'legacy_single_face'
}

facade_of_commit() { # none | valid | invalid（公开门面物证，同样读提交对象）
  local size blob
  size=$(git -C "$CACHE" cat-file -s "$1:web/v2/public/index.html" 2>/dev/null) || { printf 'none'; return; }
  [ "${size:-0}" -ge 8000 ] || { printf 'invalid'; return; }
  blob=$(git -C "$CACHE" cat-file blob "$1:web/v2/public/index.html" 2>/dev/null) || { printf 'invalid'; return; }
  printf '%s' "$blob" | grep -q '你想做什么事' || { printf 'invalid'; return; }
  printf '%s' "$blob" | grep -q 'id="btn-write"'  || { printf 'invalid'; return; }
  printf '%s' "$blob" | grep -q '</html>'          || { printf 'invalid'; return; }
  printf 'valid'
}

verify_release_tree() { # <sha>：发布目录必须逐文件等于该提交的树（运行期暂存 var/ eval/out/ 除外）
  # 返回 0=一致，1=内容/清单不符，2=含符号链接或特殊文件
  local sha=$1 want_list have_list p w h irregular
  # 符号链接必须单独判：find -type f 看不见它，Node 却会顺着它把发布树之外的文件发到公网
  irregular=$(cd "$REL" && find . \( -type l -o \( ! -type f ! -type d \) \) -print 2>/dev/null | head -1)
  [ -z "$irregular" ] || return 2
  [ -z "$(git -C "$CACHE" ls-tree -r "$sha" | awk '$1=="120000"{print $4; exit}')" ] || return 2
  want_list=$(git -C "$CACHE" ls-tree -r --name-only "$sha" | sort)
  have_list=$(cd "$REL" && find . -type f | sed 's|^\./||' | grep -vE '^(var|eval/out)/' | sort)
  [ "$want_list" = "$have_list" ] || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    w=$(git -C "$CACHE" cat-file blob "$sha:$p" 2>/dev/null | sha256sum | cut -d' ' -f1)
    h=$(sha256sum "$REL/$p" 2>/dev/null | cut -d' ' -f1)
    [ -n "$w" ] && [ "$w" = "$h" ] || return 1
  done <<< "$want_list"
  return 0
}

echo "批准点：$SHA"
echo "当前线上：$([ -n "$LIVE_SHA" ] && echo "$LIVE_SHA" || echo "<未设置>")"
echo "路径：$MODE$([ "$MODE" = rollback ] && echo " → $ROLLBACK_TO")"

# ── 切换前预检：身份 / 发布树 / 面形状 / 发布线 / 前后代关系。全部通过才允许写任何东西 ──
TGT_SHA=$(resolve_commit "$SHA") || abort TARGET_IDENTITY_UNKNOWN "批准点 $SHA 在本机 git 缓存里解析不到（未知版本不许上线）"
[ "$TGT_SHA" = "$SHA" ] || abort TARGET_IDENTITY_MISMATCH "批准点解析成了另一个提交（$TGT_SHA）"

git -C "$CACHE" cat-file -e "$SHA:server/world.mjs" 2>/dev/null \
  || abort TARGET_NOT_A_RELEASE "该提交里没有 server/world.mjs，不是 World Space 发布树"
TARGET_FACE=$(face_of_commit "$SHA")
TARGET_FACADE=$(facade_of_commit "$SHA")
echo "目标面形状（读提交里的代码）：$TARGET_FACE  门面：$TARGET_FACADE"
[ "$TARGET_FACADE" = invalid ] && abort FACADE_INVALID "目标树里的 web/v2/public/index.html 存在但不是完整门面（<8000 字节或缺物证）"
if [ -n "${WS_EXPECT_FACE:-}" ] && [ "$WS_EXPECT_FACE" != "$TARGET_FACE" ]; then
  abort FACE_MISMATCH "WS_EXPECT_FACE=$WS_EXPECT_FACE 与目标实际面 $TARGET_FACE 不一致"
fi

VR=0; verify_release_tree "$SHA" || VR=$?
[ "$VR" = 2 ] && abort RELEASE_TREE_SYMLINK "发布树 $REL 含符号链接或特殊文件（只允许普通文件；符号链接可把发布树之外的文件带进公网）"
[ "$VR" = 0 ] || abort RELEASE_TREE_MISMATCH "发布目录 $REL 与该提交的树不一致（缺文件/多文件/内容被改）"

if [ -n "$LIVE_SHA" ]; then
  LIVE_RESOLVED=$(resolve_commit "$LIVE_SHA") || abort LIVE_IDENTITY_UNKNOWN "当前线上版本 $LIVE_SHA 在本机 git 缓存里解析不到（无法判断前后代关系）"
  [ "$LIVE_RESOLVED" = "$LIVE_SHA" ] || abort LIVE_IDENTITY_MISMATCH "当前线上版本解析成了另一个提交（$LIVE_RESOLVED）"
fi

if [ "$MODE" = upgrade ]; then
  [ "$TARGET_FACE" = legacy_single_face ] && abort LEGACY_AS_UPGRADE "升级路径不接受 legacy 单面旧版；回滚旧版必须显式 WS_MODE=rollback + WS_ROLLBACK_TO"
  git -C "$CACHE" rev-parse --verify -q "refs/heads/$RELEASE_LINE^{commit}" >/dev/null 2>&1 \
    || abort RELEASE_LINE_UNKNOWN "本机缓存里没有发布线 refs/heads/$RELEASE_LINE，无法判断候选是否在发布线上"
  is_ancestor "refs/heads/$RELEASE_LINE" "$SHA" || abort NOT_IN_RELEASE_LINE "候选 $SHA 不包含发布线 $RELEASE_LINE 的最新提交（不在预期发布线上）"
  if [ -n "$LIVE_SHA" ]; then
    [ "$LIVE_SHA" = "$SHA" ] && abort ALREADY_LIVE "批准点就是当前线上版本，无需切流"
    is_ancestor "$LIVE_SHA" "$SHA" || abort VERSION_REGRESSION "批准点不是当前线上版本的后代（版本回退或分叉）"
  fi
else
  [ -n "$ROLLBACK_TO" ] || abort ROLLBACK_TARGET_REQUIRED "回滚必须显式给出 WS_ROLLBACK_TO=<40 位提交号>（第二把钥匙）"
  [ "$ROLLBACK_TO" = "$SHA" ] || abort ROLLBACK_TARGET_MISMATCH "WS_ROLLBACK_TO=$ROLLBACK_TO 与批准点 $SHA 不一致（两把钥匙必须指向同一个版本）"
  [ -n "$LIVE_SHA" ] || abort ROLLBACK_NO_LIVE "没有 current，无法判断要回滚到哪个版本之前"
  [ "$LIVE_SHA" = "$SHA" ] && abort ALREADY_LIVE "批准点就是当前线上版本，无需回滚"
  is_ancestor "$SHA" "$LIVE_SHA" || abort ROLLBACK_NOT_ANCESTOR "回滚目标 $SHA 不是当前线上版本 $LIVE_SHA 的祖先（这不是往回走）"
  echo "  WARN: 回滚路径：允许上线旧版（${TARGET_FACE}），这是显式授权且可留档的路径。"
fi

# 交给核验器的绑定信息：目标树（判门面物证）、公网口、诊断口
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
ln -sfn "$REL" "$ROOT/current" 2>/dev/null || true
if [ "$(readlink "$ROOT/current" 2>/dev/null || true)" != "$REL" ]; then
  [ -n "$LIVE_SHA" ] && ln -sfn "$ROOT/releases/$LIVE_SHA" "$ROOT/current" 2>/dev/null
  echo "CUTOVER=FAILED_SWITCH  无法把 current 指向 $REL（current 可能不是符号链接）；已退回 ${LIVE_SHA:-none}"
  exit 1
fi
echo "  current: $([ -n "$LIVE_SHA" ] && echo "$LIVE_SHA" || echo none) -> $(basename "$(readlink "$ROOT/current")")"
T0=$(now_ns)
RESTART_RC=0
$RESTART_CMD || RESTART_RC=$?
if [ "$RESTART_RC" != 0 ]; then
  # 重启命令失败：新版本没有生效。把 current 退回运行中的旧版本，避免"链接指新、进程跑旧"的假一致。
  [ -n "$LIVE_SHA" ] && ln -sfn "$ROOT/releases/$LIVE_SHA" "$ROOT/current" 2>/dev/null
  OK=no
  for _ in $(seq 1 "$POLL_TRIES"); do
    if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PUBLIC_PORT/healthz"; then OK=yes; break; fi
    sleep 0.2
  done
  if [ "$OK" = yes ]; then
    echo "CUTOVER=FAILED_RESTART_SCENE_PRESERVED  重启命令退出码 $RESTART_RC；新版本未生效，current 已退回 ${LIVE_SHA:-none}（不关站）"
    exit 1
  fi
  echo "=== 重启失败且公网面在轮询窗口内没起来 → 按 §10 关站 ==="
  "$EMERG" close
  echo "CUTOVER=FAILED_RESTART_AND_CLOSED  重启命令退出码 $RESTART_RC，恢复探测仍失败"
  exit 1
fi
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
  echo "previous=$LIVE_SHA"
  echo "mode=$MODE"
  echo "rollback_to=$([ -n "$ROLLBACK_TO" ] && echo "$ROLLBACK_TO" || echo -)"
  echo "target_face=$TARGET_FACE"
  echo "target_facade=$TARGET_FACADE"
  echo "recovery_s=$REC"
  echo "verify_exit=$VC"
  echo "session_secret_rotated=$ROTATE_SECRET"
} > "$REC_FILE"
echo "  留档：$REC_FILE"

case "$VC" in
  0)
    echo "=== 切流完成 ==="
    echo "CUTOVER=OK  线上现在是 $SHA（路径 $MODE，面形状 $TARGET_FACE）"
    echo "  关站（一条命令）：$EMERG close"
    echo "  撤销关站：$EMERG restore"
    echo "  版本级回退只允许在本系列内含访问门的提交之间进行；回滚旧版用 WS_MODE=rollback + WS_ROLLBACK_TO"
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
