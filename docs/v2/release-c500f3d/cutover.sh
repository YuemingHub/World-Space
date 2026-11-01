#!/usr/bin/env bash
# World Space 切流（Founder 明示批准后执行）
#
# 边界（写死在这里，不给临场判断留缝）：
#   动：/opt/world-space/current 符号链接、world-space.service 的一次重启、（可选）session 签名密钥轮换
#   不动：DNS、解析记录、nginx 站点配置、其它任何站点、共享账本、旧 release 目录
#   绝不：把 current 指向无访问门的旧版本（85c7b91 / 6e73725 / main Pages 都不是退路）
#
# 两条路径必须可区分：
#   升级   WS_MODE=upgrade（默认）：批准点必须能解析成同一个提交、发布目录必须逐文件等于该提交的树、
#          必须是双面版本、必须自带发布身份测量、必须包含发布线（写死 refs/heads/v2）的最新提交、
#          且必须是当前线上版本的后代。
#          任何一条不成立 → CUTOVER=ABORT_*，退出码 3，零写入（不换 current、不重启、不留档）。
#   回滚   WS_MODE=rollback 且 WS_ROLLBACK_TO=<40 位提交号>：两把钥匙必须同时给出，且都等于批准点。
#          目标必须是当前线上版本的祖先（真正的"往回走"）。
#
# 发布身份闭环（2026-11-01 R3 P0）：
#   CUTOVER=OK 的含义只能是「批准的这份字节正在服务」。为此应用在诊断面自报
#   release_id（对自身发布树做的内容摘要）+ started_at_ms；本脚本用 release-id.mjs
#   对**已逐文件核对过的发布树**算出同一个摘要，交给核验器比对。身份缺失、旧进程、
#   新旧不一致、无法核实，一律不给 OK。身份来自运行代码/发布产物，不来自本脚本的声明。
#
# 关站条件收窄：
#   只有核验器返回 5（公网面确实探测不到服务，且真的探测过）才允许 emergency close。
#   返回 2/3/4/7 代表「判据不过」「两面矛盾」或「身份不可核实」——保留现场等人判断。
#
# 同时兼容两种 release：
#   dual_face（healthz-only 及以后）    公网面只应有 {"ok":true}，详细诊断在 3201
#   legacy_single_face（e8284c4 及更早）诊断字段仍在公网面上、没有 3201 —— 这是旧版回滚状态，
#     但它没有发布身份物证，本工具**不会**给它 OK（核验器返回 7）；先把身份能力带上线。
set -uo pipefail
# 只用真实对象关系判断祖先：replace refs 可以在 root 可写的缓存里伪造"谁是谁的祖先"
export GIT_NO_REPLACE_OBJECTS=1

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="${WS_ROOT:-/opt/world-space}"
STATE="$ROOT/state"
CACHE="${WS_CACHE:-$ROOT/.git-cache/World-Space.git}"
RELEASE_LINE="v2"                               # 写死：残留的 WS_RELEASE_LINE 不能静默换线
EMERG="${WS_EMERG:-/usr/local/bin/world-space-emergency.sh}"
VERIFY="${WS_VERIFY:-/usr/local/bin/ws-verify-faces.sh}"
VERIFY_SHA_FILE="${WS_VERIFY_SHA_FILE:-$HERE/ws-verify-faces.sh.sha256}"
MODE="${WS_MODE:-upgrade}"                      # upgrade | rollback，必须显式二选一
ROLLBACK_TO="${WS_ROLLBACK_TO:-}"               # 回滚的第二把钥匙：必须与批准点相同
ROTATE_SECRET="${WS_ROTATE_SECRET:-0}"          # 默认 0 = 不轮换（现有登录不掉线）；只有显式 WS_ROTATE_SECRET=1 才轮换
RESTART_CMD="${WS_RESTART_CMD:-systemctl restart world-space.service}"
PID_CMD="${WS_PID_CMD:-systemctl show -p MainPID --value world-space.service}"
PUBLIC_PORT="${WS_PUBLIC_PORT:-3200}"
OPS_PORT="${WS_OPS_PORT:-3201}"
POLL_TRIES="${WS_POLL_TRIES:-200}"              # 200 × 0.2s ≈ 40s 上限
IDENTITY_TOOL="$HERE/release-id.mjs"
FACE_PROBE="$HERE/face-probe.mjs"
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/ws-cutover.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT

now_ns() { # 纳秒时间戳；不认 %N 的平台退化成整秒而不是产出垃圾串
  local v; v=$(date +%s%N 2>/dev/null || echo "")
  case "$v" in
    ''|*[!0-9]*) v=$(( $(date +%s) * 1000000000 )) ;;
  esac
  printf '%s' "$v"
}
now_ms() { printf '%s' "$(( $(now_ns) / 1000000 ))"; }

abort() { # abort <大写下划线原因> <人话说明>   —— 退出码 3：判据不过，零写入
  echo "CUTOVER=ABORT_$1  $2"
  exit 3
}
is_sha()   { printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$'; }
is_hex64() { printf '%s' "$1" | grep -Eq '^[0-9a-f]{64}$'; }
real_dir() { ( cd "$1" 2>/dev/null && pwd -P ); }
sha256_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# ── 0. 用法与边界：在写任何东西之前全部验一遍 ──────────────────────────
# 轮询次数是"健康/不可用"的唯一证据来源；非法值不能让循环一次都不跑就判不可用。
case "$POLL_TRIES" in
  ''|*[!0-9]*) abort USAGE_ERROR "WS_POLL_TRIES=$POLL_TRIES 不是正整数（必须 ≥1）" ;;
esac
[ "$POLL_TRIES" -ge 1 ] 2>/dev/null || abort USAGE_ERROR "WS_POLL_TRIES=$POLL_TRIES 必须 ≥1"
if [ -n "${WS_RELEASE_LINE:-}" ] && [ "${WS_RELEASE_LINE}" != "v2" ]; then
  abort RELEASE_LINE_OVERRIDE "WS_RELEASE_LINE=${WS_RELEASE_LINE}：发布线写死 v2，不允许用环境变量换线"
fi

[ -d "$ROOT" ] || abort ROOT_MISSING "WS_ROOT=$ROOT 不存在"
ROOT_REAL=$(real_dir "$ROOT") || abort ROOT_MISSING "读不了 WS_ROOT=$ROOT"
[ -d "$ROOT/releases" ] && [ ! -L "$ROOT/releases" ] \
  || abort RELEASES_NOT_DIRECTORY "$ROOT/releases 必须是一个真实目录（不允许是符号链接或有其它东西占位）"
RELEASES_REAL=$(real_dir "$ROOT/releases") || abort RELEASES_NOT_DIRECTORY "读不了 $ROOT/releases"
[ "$RELEASES_REAL" = "$ROOT_REAL/releases" ] \
  || abort PATH_ESCAPE "$ROOT/releases 的物理位置是 $RELEASES_REAL，不在 ROOT 内（$ROOT_REAL/releases）"

SHA=$(cat "$STATE/approved-sha" 2>/dev/null || true)
is_sha "$SHA" || abort APPROVED_SHA_INVALID "state/approved-sha 不是完整的 40 位提交号：'${SHA:-<空>}'（先跑 ws-prep.sh verify 登记批准的候选）"

# 批准记录必须与本轮实际策略对得上：只有 SHA 一个值无法区分"升级批准"和"回滚批准"。
META="$STATE/approved-meta.txt"
[ -f "$META" ] || abort APPROVAL_RECORD_MISSING "缺少 $META：批准记录不完整，重新跑 ws-prep.sh verify 登记"
meta_get() { grep -E "^$1=" "$META" 2>/dev/null | head -1 | cut -d= -f2- || true; }
[ "$(meta_get sha)" = "$SHA" ] || abort APPROVAL_RECORD_MISMATCH "$META 里的 sha 与 approved-sha 不一致"
[ "$(meta_get mode)" = "$MODE" ] || abort APPROVAL_RECORD_MISMATCH "$META 记录的是 mode=$(meta_get mode)，本轮是 $MODE"
[ "$(meta_get release_line)" = "v2" ] || abort APPROVAL_RECORD_MISMATCH "$META 记录的发布线不是 v2"

REL="$ROOT/releases/$SHA"
[ -d "$REL" ] && [ ! -L "$REL" ] || abort RELEASE_TREE_MISSING "批准树不存在或不是真实目录：$REL"
REL_REAL=$(real_dir "$REL") || abort RELEASE_TREE_MISSING "读不了批准树 $REL"
[ "$REL_REAL" = "$RELEASES_REAL/$SHA" ] \
  || abort PATH_ESCAPE "批准树的物理位置是 $REL_REAL，不等于 $RELEASES_REAL/$SHA"

# current 的身份 = **位置 + 名字**：只认 $ROOT/releases/<40hex>，不能靠 basename 猜。
LIVE_RAW=$(readlink "$ROOT/current" 2>/dev/null || true)
LIVE_SHA=""
if [ -n "$LIVE_RAW" ]; then
  LIVE_SHA=$(basename "$LIVE_RAW")
  [ "$LIVE_RAW" = "$ROOT/releases/$LIVE_SHA" ] && is_sha "$LIVE_SHA" \
    || abort LIVE_IDENTITY_UNKNOWN "current 指向 $LIVE_RAW，不是 $ROOT/releases/<40位提交号> 的形状"
  [ -d "$ROOT/releases/$LIVE_SHA" ] && [ ! -L "$ROOT/releases/$LIVE_SHA" ] \
    || abort LIVE_IDENTITY_UNKNOWN "current 指向的发布树不存在或不是真实目录：$ROOT/releases/$LIVE_SHA"
  [ "$(real_dir "$ROOT/releases/$LIVE_SHA")" = "$RELEASES_REAL/$LIVE_SHA" ] \
    || abort PATH_ESCAPE "current 指向的发布树物理位置逃出了 releases（$LIVE_SHA）"
fi
if [ "$MODE" = upgrade ] && [ -z "$LIVE_SHA" ]; then
  abort LIVE_IDENTITY_UNKNOWN "没有可识别的 current（$ROOT/current 不存在或不是符号链接），升级无法判断这是不是一次前进"
fi

[ -x "$EMERG" ]  || abort EMERGENCY_MISSING "关站脚本不在位（$EMERG），切流前必须先装好回滚方案"
[ -f "$VERIFY" ] || abort VERIFIER_MISSING "双面核验器不在位（$VERIFY）"
[ -f "$IDENTITY_TOOL" ] || abort IDENTITY_TOOL_MISSING "发布身份工具不在位（$IDENTITY_TOOL）"
[ -f "$FACE_PROBE" ]    || abort FACE_PROBE_MISSING "面形状探针不在位（$FACE_PROBE）"
command -v git >/dev/null 2>&1 || abort GIT_MISSING "本机没有 git，无法验证目标身份"
command -v node >/dev/null 2>&1 || abort NODE_MISSING "本机没有 node，无法计算发布身份"
[ -d "$CACHE" ]  || abort GIT_CACHE_MISSING "本机 git 缓存不在位（$CACHE）；先跑 ws-prep.sh fetch"
case "$MODE" in upgrade|rollback) ;; *) abort MODE_INVALID "WS_MODE=$MODE（只认 upgrade 或 rollback）" ;; esac

# Git 祖先关系可被两类元数据伪造：replace refs（环境变量已关，但仍拒绝其存在）与 info/grafts。
if [ -n "$(git -C "$CACHE" for-each-ref --format='%(refname)' refs/replace 2>/dev/null)" ]; then
  abort GIT_METADATA_TAMPERED "git 缓存里存在 refs/replace：祖先关系可被伪造，先清理缓存再切流"
fi
[ ! -e "$CACHE/info/grafts" ] \
  || abort GIT_METADATA_TAMPERED "git 缓存里存在 info/grafts：祖先关系可被伪造，先清理缓存再切流"

# 核验器版本绑定：旧 verifier 的退出码契约可能不同，不能让它冒充被接受的版本。
VERIFY_HASH=$(sha256_of "$VERIFY")
is_hex64 "$VERIFY_HASH" || abort VERIFIER_IDENTITY_UNKNOWN "算不出核验器哈希（$VERIFY）"
VERIFY_EXPECT=$(awk 'NR==1{print $1}' "$VERIFY_SHA_FILE" 2>/dev/null || true)
[ -n "$VERIFY_EXPECT" ] || VERIFY_EXPECT="${WS_VERIFY_SHA256:-}"
is_hex64 "$VERIFY_EXPECT" || abort VERIFIER_IDENTITY_UNKNOWN "没有可用的核验器期望哈希（$VERIFY_SHA_FILE 或 WS_VERIFY_SHA256）"
[ "$VERIFY_HASH" = "$VERIFY_EXPECT" ] \
  || abort VERIFIER_IDENTITY_MISMATCH "核验器哈希 $VERIFY_HASH ≠ 期望 $VERIFY_EXPECT：装错版本，拒绝切流"

resolve_commit() { # <sha> → 打印该提交的完整 SHA；解析不了返回 1
  git -C "$CACHE" cat-file -e "$1^{commit}" 2>/dev/null || return 1
  git -C "$CACHE" rev-parse "$1^{commit}" 2>/dev/null
}
is_ancestor() { git -C "$CACHE" merge-base --is-ancestor "$1" "$2" 2>/dev/null; }

commit_world_blob() { # <sha> → 临时文件路径（提交里的 server/world.mjs）
  local out="$TMPD/world-$1.mjs"
  git -C "$CACHE" cat-file blob "$1:server/world.mjs" > "$out" 2>/dev/null || return 1
  printf '%s' "$out"
}
face_of_commit() { # dual_face | legacy_single_face —— 去掉注释/字符串后看代码能力
  local f; f=$(commit_world_blob "$1") || { printf 'unknown'; return 1; }
  node "$FACE_PROBE" "$f" 2>/dev/null
}
identity_capability_of_commit() { # identity_v1 | no_identity
  local f; f=$(commit_world_blob "$1") || { printf 'unknown'; return 1; }
  node "$FACE_PROBE" "$f" identity 2>/dev/null
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
echo "核验器：$VERIFY（sha256=$VERIFY_HASH，已绑定）"

# ── 切换前预检：身份 / 发布树 / 面形状 / 发布线 / 前后代关系。全部通过才允许写任何东西 ──
TGT_SHA=$(resolve_commit "$SHA") || abort TARGET_IDENTITY_UNKNOWN "批准点 $SHA 在本机 git 缓存里解析不到（未知版本不许上线）"
[ "$TGT_SHA" = "$SHA" ] || abort TARGET_IDENTITY_MISMATCH "批准点解析成了另一个提交（$TGT_SHA）"

git -C "$CACHE" cat-file -e "$SHA:server/world.mjs" 2>/dev/null \
  || abort TARGET_NOT_A_RELEASE "该提交里没有 server/world.mjs，不是 World Space 发布树"
TARGET_FACE=$(face_of_commit "$SHA") || abort TARGET_NOT_A_RELEASE "读不出目标的面形状"
TARGET_ID_CAP=$(identity_capability_of_commit "$SHA")
TARGET_FACADE=$(facade_of_commit "$SHA")
echo "目标面形状（读提交里的代码，已去注释/字符串）：$TARGET_FACE  身份能力：$TARGET_ID_CAP  门面：$TARGET_FACADE"
if [ "$MODE" = upgrade ] && [ "$TARGET_FACE" = legacy_single_face ]; then
  abort LEGACY_AS_UPGRADE "升级路径不接受 legacy 单面旧版；回滚旧版必须显式 WS_MODE=rollback + WS_ROLLBACK_TO"
fi
[ "$TARGET_ID_CAP" = identity_v1 ] \
  || abort IDENTITY_UNSUPPORTED_BY_TARGET "目标代码不带发布身份测量（release_id）：无法证明正在服务的是它，不允许切流"
[ "$TARGET_FACADE" = invalid ] && abort FACADE_INVALID "目标树里的 web/v2/public/index.html 存在但不是完整门面（<8000 字节或缺物证）"
if [ -n "${WS_EXPECT_FACE:-}" ] && [ "$WS_EXPECT_FACE" != "$TARGET_FACE" ]; then
  abort FACE_MISMATCH "WS_EXPECT_FACE=$WS_EXPECT_FACE 与目标实际面 $TARGET_FACE 不一致"
fi

VR=0; verify_release_tree "$SHA" || VR=$?
[ "$VR" = 2 ] && abort RELEASE_TREE_SYMLINK "发布树 $REL 含符号链接或特殊文件（只允许普通文件；符号链接可把发布树之外的文件带进公网）"
[ "$VR" = 0 ] || abort RELEASE_TREE_MISMATCH "发布目录 $REL 与该提交的树不一致（缺文件/多文件/内容被改）"

# 发布身份：对"已逐文件核对过的树"做内容测量。核验器会拿同一个值比对运行中的进程。
EXPECT_RELEASE_ID=$(node "$IDENTITY_TOOL" "$REL" 2>/dev/null || true)
is_hex64 "$EXPECT_RELEASE_ID" || abort IDENTITY_COMPUTE_FAILED "算不出目标树的发布身份（$REL）"
META_REL_ID=$(meta_get release_id)
if [ -n "$META_REL_ID" ] && [ "$META_REL_ID" != "$EXPECT_RELEASE_ID" ]; then
  abort APPROVAL_RECORD_MISMATCH "批准记录里的 release_id=$META_REL_ID 与发布树实算 $EXPECT_RELEASE_ID 不一致"
fi
echo "目标发布身份：$EXPECT_RELEASE_ID"

LIVE_RELEASE_ID=""
if [ -n "$LIVE_SHA" ]; then
  LIVE_REL="$ROOT/releases/$LIVE_SHA"
  LIVE_RELEASE_ID=$(node "$IDENTITY_TOOL" "$LIVE_REL" 2>/dev/null || true)
  LIVE_RESOLVED=$(resolve_commit "$LIVE_SHA") || abort LIVE_IDENTITY_UNKNOWN "当前线上版本 $LIVE_SHA 在本机 git 缓存里解析不到（无法判断前后代关系）"
  [ "$LIVE_RESOLVED" = "$LIVE_SHA" ] || abort LIVE_IDENTITY_MISMATCH "当前线上版本解析成了另一个提交（$LIVE_RESOLVED）"
fi

if [ "$MODE" = upgrade ]; then
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
  [ "$(meta_get rollback_to)" = "$ROLLBACK_TO" ] \
    || abort APPROVAL_RECORD_MISMATCH "批准记录里的 rollback_to=$(meta_get rollback_to) 与 WS_ROLLBACK_TO=$ROLLBACK_TO 不一致"
  [ -n "$LIVE_SHA" ] || abort ROLLBACK_NO_LIVE "没有 current，无法判断要回滚到哪个版本之前"
  [ "$LIVE_SHA" = "$SHA" ] && abort ALREADY_LIVE "批准点就是当前线上版本，无需回滚"
  is_ancestor "$SHA" "$LIVE_SHA" || abort ROLLBACK_NOT_ANCESTOR "回滚目标 $SHA 不是当前线上版本 $LIVE_SHA 的祖先（这不是往回走）"
  echo "  WARN: 回滚路径：允许上线旧版（${TARGET_FACE}），这是显式授权且可留档的路径。"
fi

mkdir -p "$STATE" || abort STATE_UNWRITABLE "写不了 $STATE"

# 交给核验器的绑定信息：目标树（判门面物证/算身份）、公网口、诊断口、批准身份
export WS_TARGET_REL="$REL" WS_PUBLIC_PORT="$PUBLIC_PORT" WS_OPS_PORT="$OPS_PORT"
export WS_EXPECT_RELEASE_ID="$EXPECT_RELEASE_ID"

# 1) 可选：轮换 session 签名密钥，让此前泄漏过／打印过的令牌全部失效
if [ "$ROTATE_SECRET" = "1" ]; then
  echo "=== 1) 轮换会话签名密钥（作废所有旧令牌）==="
  head -c 48 /dev/urandom | base64 > "$ROOT/etc/session-secret.txt"
  chmod 600 "$ROOT/etc/session-secret.txt"; chown wsapp:wsapp "$ROOT/etc/session-secret.txt" 2>/dev/null || true
  echo "  已重写（值不回显）。所有账号需要重新登录一次，口令不变。"
else
  echo "=== 1) 跳过 session 密钥轮换（WS_ROTATE_SECRET 未设置或为 0：现有登录令牌继续有效）==="
fi

# ── 写后动作 ────────────────────────────────────────────────────────────
switch_verified() { # <abs target> → current 恰好指向它才算成功
  ln -sfn "$1" "$ROOT/current" 2>/dev/null || true
  [ -L "$ROOT/current" ] && [ "$(readlink "$ROOT/current" 2>/dev/null || true)" = "$1" ]
}
restore_live_verified() { # 把 current 退回旧版，并**自证**结果
  [ -n "$LIVE_SHA" ] || return 1
  switch_verified "$ROOT/releases/$LIVE_SHA"
}
current_state() { # 人话描述 current 的真实状态（不美化）
  if [ -L "$ROOT/current" ]; then printf '%s' "$(readlink "$ROOT/current")"
  elif [ -e "$ROOT/current" ]; then printf '非符号链接(%s)' "$ROOT/current"
  else printf '不存在'; fi
}

POLL_ATTEMPTS=0
poll_health() { # 真探测；返回 0=有响应 1=整个窗口都探测不到
  local i=0
  POLL_ATTEMPTS=0
  while [ "$i" -lt "$POLL_TRIES" ]; do
    i=$((i+1)); POLL_ATTEMPTS=$((POLL_ATTEMPTS+1))
    if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PUBLIC_PORT/healthz"; then return 0; fi
    sleep 0.2
  done
  return 1
}
probe_scene_identity() { # <expect_release_id> → 0 仅当诊断面在、身份=期望、pid=重启前 pid
  local want=$1 body pid rid
  body=$(curl -s --max-time 3 "http://127.0.0.1:$OPS_PORT/healthz" 2>/dev/null) || return 1
  pid=$(printf '%s' "$body" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).pid)}catch(e){console.log("ERR")}})' 2>/dev/null || echo ERR)
  rid=$(printf '%s' "$body" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).release_id)}catch(e){console.log("ERR")}})' 2>/dev/null || echo ERR)
  [ -n "$PRE_PID" ] && [ "$pid" = "$PRE_PID" ] || return 1
  is_hex64 "$want" && [ "$rid" = "$want" ] || return 1
  return 0
}
write_receipt() { # <status> <verify_exit> <current_after> <restored> <recovery_s>
  local f="$STATE/cutover-$(date +%Y%m%d-%H%M%S).txt"
  { date -u +%FT%TZ
    echo "status=$1"
    echo "approved=$SHA"
    echo "previous=$LIVE_SHA"
    echo "mode=$MODE"
    echo "rollback_to=$([ -n "$ROLLBACK_TO" ] && echo "$ROLLBACK_TO" || echo -)"
    echo "target_face=$TARGET_FACE"
    echo "target_facade=$TARGET_FACADE"
    echo "target_release_id=$EXPECT_RELEASE_ID"
    echo "verifier_sha256=$VERIFY_HASH"
    echo "recovery_s=$5"
    echo "verify_exit=$2"
    echo "poll_attempts=$POLL_ATTEMPTS"
    echo "restore_verified=$4"
    echo "current_after=$3"
    echo "session_secret_rotated=$ROTATE_SECRET"
  } > "$f"
  echo "  留档：$f"
}

# 2) 切版本 + 重启，并量出真实中断时长
echo "=== 2) 换 current 并重启 ==="
if ! switch_verified "$REL"; then
  # 三种真实状态分开记：current 从未变更 / 主动退回并核实 / 退回失败。
  # "yes" 只表示"确实执行了退回并读回 current 核对过"，不能用来美化一次没发生的恢复。
  if [ -n "$LIVE_SHA" ] && [ "$(current_state)" = "$ROOT/releases/$LIVE_SHA" ]; then
    NOW=$(current_state)
    echo "CUTOVER=FAILED_SWITCH  无法把 current 指向 $REL；current 未变更，仍指向旧版 $LIVE_SHA（恢复核实=unchanged，无需恢复）"
    write_receipt FAILED_SWITCH - "$NOW" unchanged -
  else
    RESTORED=no; restore_live_verified && RESTORED=yes
    NOW=$(current_state)
    echo "CUTOVER=FAILED_SWITCH  无法把 current 指向 $REL；恢复核实=$RESTORED，现在 current=$NOW"
    write_receipt FAILED_SWITCH - "$NOW" "$RESTORED" -
  fi
  exit 1
fi
echo "  current: $([ -n "$LIVE_SHA" ] && echo "$LIVE_SHA" || echo none) -> $(basename "$(readlink "$ROOT/current")")"
T_START_MS=$(now_ms)
T0=$(now_ns)
PRE_PID=$($PID_CMD 2>/dev/null || true)
export WS_EXPECT_START_AFTER="$T_START_MS"
RESTART_RC=0
$RESTART_CMD || RESTART_RC=$?
T1=$(now_ns)
REC=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.2f", (b-a)/1000000000}')

if [ "$RESTART_RC" != 0 ]; then
  # 重启命令失败：先把 current 退回旧版，再**证明**退回了哪里、谁在服务。
  RESTORED=no; restore_live_verified && RESTORED=yes
  if poll_health; then SCENE=health_ok; else SCENE=health_down; fi
  NOW=$(current_state)
  if [ "$RESTORED" = yes ] && [ "$SCENE" = health_ok ] && probe_scene_identity "$LIVE_RELEASE_ID"; then
    echo "CUTOVER=FAILED_RESTART_SCENE_PRESERVED  重启命令退出码 $RESTART_RC；已核实旧版 $LIVE_SHA 仍在服务（identity=$LIVE_RELEASE_ID，pid=${PRE_PID:-?}）；不关站"
    write_receipt FAILED_RESTART_SCENE_PRESERVED "$RESTART_RC" "$NOW" "$RESTORED" "$REC"
    exit 1
  fi
  if [ "$SCENE" = health_ok ]; then
    echo "CUTOVER=FAILED_RESTART_SCENE_UNVERIFIED  重启命令退出码 $RESTART_RC；探测有响应，但无法证明服务的是旧版（恢复核实=$RESTORED，current=$NOW；可能是端口被别的进程占用）；不关站"
    write_receipt FAILED_RESTART_SCENE_UNVERIFIED "$RESTART_RC" "$NOW" "$RESTORED" "$REC"
    exit 1
  fi
  echo "=== 重启失败且公网面在轮询窗口内没起来（探测 $POLL_ATTEMPTS 次）→ 按 §10 关站 ==="
  "$EMERG" close
  echo "CUTOVER=FAILED_RESTART_AND_CLOSED  重启命令退出码 $RESTART_RC，恢复探测失败；恢复核实=$RESTORED，current=$NOW"
  write_receipt FAILED_RESTART_AND_CLOSED "$RESTART_RC" "$NOW" "$RESTORED" "$REC"
  exit 1
fi

if ! poll_health; then
  echo "=== 公网面在轮询窗口内探测不到（真探测 $POLL_ATTEMPTS 次）→ 按 §10 关站 ==="
  "$EMERG" close
  echo "CUTOVER=FAILED_AND_CLOSED  重启命令退出码 0 但公网面不可用；现场留在此状态等人判断"
  write_receipt FAILED_AND_CLOSED 5 "$(current_state)" no "$REC"
  exit 1
fi
echo "  恢复探测：成功（$REC 秒；探测 $POLL_ATTEMPTS 次）"

# 3) 双面核验（只读）。按退出码动作，不读中文。
echo "=== 3) 双面核验 ==="
WS_EXPECT_PID=$($PID_CMD 2>/dev/null || true)
export WS_EXPECT_PID
VC=5
bash "$VERIFY"; VC=$?
echo "  核验退出码：$VC"

case "$VC" in
  0)
    echo "=== 切流完成 ==="
    echo "CUTOVER=OK  线上现在是 $SHA（路径 $MODE，面形状 $TARGET_FACE，release_id=$EXPECT_RELEASE_ID）"
    write_receipt OK 0 "$(current_state)" - "$REC"
    echo "  关站（一条命令）：$EMERG close"
    echo "  撤销关站：$EMERG restore"
    echo "  版本级回退只允许在本系列内含发布身份的提交之间进行；回滚旧版用 WS_MODE=rollback + WS_ROLLBACK_TO"
    exit 0 ;;
  5)
    echo "=== 公网面确实不可用：按 §10 宁可关站，也不回无门公开版（不把 current 切回 $LIVE_SHA）==="
    "$EMERG" close
    echo "CUTOVER=FAILED_AND_CLOSED  现场留在此状态等人判断，不自动重试"
    write_receipt FAILED_AND_CLOSED 5 "$(current_state)" no "$REC"
    exit 1 ;;
  7)
    echo "=== 身份不可核实（退出码 7）：保留现场，不关站 ==="
    echo "  旧版单面没有诊断面，无法证明正在服务的是批准提交；不给 OK。"
    echo "CUTOVER=FAILED_IDENTITY_UNVERIFIABLE  现在 current=$(current_state)"
    write_receipt FAILED_IDENTITY_UNVERIFIABLE 7 "$(current_state)" no "$REC"
    exit 1 ;;
  *)
    echo "=== 核验未过（退出码 $VC）：保留现场，不关站 ==="
    echo "  这一类代表判据不过、两面矛盾或运行身份与批准版本不一致，不代表服务挂了。"
    echo "  关站会把一次可诊断的部署变成没人看得见的 503；要关，由人判断之后再关。"
    echo "  现在 current=$(current_state)  撤销用：$EMERG restore"
    echo "CUTOVER=FAILED_SCENE_PRESERVED"
    write_receipt FAILED_SCENE_PRESERVED "$VC" "$(current_state)" no "$REC"
    exit 1 ;;
esac
