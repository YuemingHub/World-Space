#!/usr/bin/env bash
# ops-selftest.sh —— 切流工具链的回归自测（离线假面，0 外网、0 生产接触）
#
# 覆盖三件事，每件都配红绿一对（只见过一种状态的判据不算验证过）：
#   A. ws-verify-faces.sh 对双面/单面、字段缺失、身份不符、门失效的分类与退出码；
#      以及匿名首页的两种合法物证（新版门面 200 / 旧版回滚 302）与各自的红侧
#   B. cutover.sh 的关站边界：只有"公网面确实不可用"才允许 close；
#      新版诊断面出问题必须留现场不关站（这正是 2026-10-05 的兼容性缺口）；
#      以及轮换默认值：未设置 = 不轮换（默认 0），显式 WS_ROTATE_SECRET=1 才轮换
#   C. ws-env-put.sh 对无换行文件的安全性（我把 WS_SEARCH_KEY_2 改坏过的那一类事故）
#
# 用法：bash ops-selftest.sh          （退出码 0 = 全部通过）
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
VERIFY="$HERE/ws-verify-faces.sh"
ENVPUT="$HERE/ws-env-put.sh"
FIXTURE="$HERE/ops-fixture-face.mjs"
T=$(mktemp -d)
PIDS=""
FAILED=0
TOTAL=0
# 测试端口基址可换：共享机器上不能假设某几个端口一定空着
BASE=${WS_TEST_PORT_BASE:-4711}
P1=$((BASE));     O1=$((BASE+1))
PB=$((BASE+10));  OB=$((BASE+11))
DEAD1=$((BASE+88)); DEAD2=$((BASE+89))
FREE_OK=1
for p in $P1 $O1 $PB $OB $DEAD1 $DEAD2; do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$p/" 2>/dev/null; then
    printf 'FAIL  端口 %s 已被占用（这台机器上有别的服务/会话在跑）——换 WS_TEST_PORT_BASE 再跑\n' "$p"; FREE_OK=0
  fi
done
[ "$FREE_OK" = "1" ] || exit 6
printf '测试端口基址 %s（%s 对已确认空闲）\n' "$BASE" "3"

cleanup() {
  for p in $PIDS; do kill "$p" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT

# 假 ss：把「监听表」变成可控输入，这样 loopback 这项判据既能判绿也能判红
printf '#!/usr/bin/env bash\nprintf "LISTEN 0 511 127.0.0.1:%s 0.0.0.0:*\\n" %s\n' "$O1" "$O1" > "$T/ss-loop"
printf '#!/usr/bin/env bash\nprintf "LISTEN 0 511 0.0.0.0:%s 0.0.0.0:*\\n" %s\n'   "$O1" "$O1" > "$T/ss-wide"
printf '#!/usr/bin/env bash\nexit 1\n'                                            > "$T/ss-missing"
chmod +x "$T/ss-loop" "$T/ss-wide" "$T/ss-missing"

# 静态探针的输入：一个"新版"发布树（代码里真有诊断面 + 身份测量），一个"旧版"发布树（都没有）。
# 注意：判据读的是**代码 token**（face-probe.mjs 先去掉注释/字符串），
# 所以这里必须写成真代码，不能只写 `const CFG = { opsPort: 3201 }` 这种注释级形状。
DUAL_SRC=$(cat <<'JS'
const http = require('node:http');
const WS_OPS_PORT = Number(process.env.WS_OPS_PORT || 3201);
const RELEASE_ID_SCHEME = 'world-release-tree-v1';
function computeReleaseId() { return 'synthetic-fixture'; }
function handler(req, res) { res.end('{"ok":true}'); }
http.createServer(handler).listen(3200);
http.createServer(handler).listen(WS_OPS_PORT);
JS
)
LEGACY_SRC='const CFG = { webDir: 1 };'
mkdir -p "$T/rel-dual/server" "$T/rel-legacy/server"
printf '%s\n' "$DUAL_SRC"   > "$T/rel-dual/server/world.mjs"
printf '%s\n' "$LEGACY_SRC" > "$T/rel-legacy/server/world.mjs"
# 带公开门面物证的发布树：验证器必须据此期待 200 门面，而不是旧的 302
mkdir -p "$T/rel-facade/server" "$T/rel-facade/web/v2/public"
printf '%s\n' "$DUAL_SRC" > "$T/rel-facade/server/world.mjs"
printf '<!doctype html><html>fixture facade artifact</html>\n' > "$T/rel-facade/web/v2/public/index.html"
rel_id() { node "$HERE/release-id.mjs" "$1" 2>/dev/null || true; }
now_ms() { local v; v=$(date +%s%3N 2>/dev/null || true); case "$v" in ''|*[!0-9]*) v=$(( $(date +%s) * 1000 ));; esac; printf '%s' "$v"; }
# 双面夹具的通用底座：身份必须来自它实际加载的发布树（RELEASE_ROOT），启动时间是进程真实启动时间
dual_started_at() { printf '%s' "$(( $(now_ms) - 60000 ))"; }

ok()   { TOTAL=$((TOTAL+1)); printf '  \033[32m✓\033[0m %-58s %s\n' "$1" "${2:-}"; }
no()   { TOTAL=$((TOTAL+1)); FAILED=$((FAILED+1)); printf '  \033[31m✗\033[0m %-58s %s\n' "$1" "${2:-}"; }
SKIPPED=0
skip() { SKIPPED=$((SKIPPED+1)); printf '  \033[33m-\033[0m %-58s %s\n' "$1" "${2:-}"; }
# 本平台若能真建符号链接才允许跑切流语义；否则必须显式 SKIP，绝不静默算过
have_symlinks() { mkdir -p "$T/symdir"; rm -f "$T/symprobe"; ln -s "$T/symdir" "$T/symprobe" 2>/dev/null && [ -L "$T/symprobe" ]; }
eq()   { # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1" "=$3"; else no "$1" "期望 $2 实得 $3"; fi
}
has()  { if grep -q "$2" <<<"$3"; then ok "$1" "含 /$2/"; else no "$1" "缺 /$2/（输出：$(printf '%s' "$3" | tr '\n' ' ' | head -c 120)）"; fi; }

start_fixture() { # start_fixture <pub> <ops> [VAR=val ...]  → 等就绪
  local pub="$1" ops="$2"; shift 2
  local log="$T/fx-$pub.log"
  env PUB_PORT="$pub" OPS_PORT="$ops" "$@" node "$FIXTURE" > "$log" 2>&1 &
  local pid=$!
  PIDS="$PIDS $pid"
  local i=0
  while [ $i -lt 100 ]; do
    if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$pub/healthz"; then return 0; fi
    if grep -q FIXTURE_FAIL "$log" 2>/dev/null; then return 1; fi
    sleep 0.1; i=$((i+1))
  done
  return 1
}
stop_fixture() { for p in $PIDS; do kill "$p" 2>/dev/null; done; PIDS=""; sleep 0.3; }

vrun() { # vrun <label> <expected_exit> [VAR=val ...]
  local label="$1" exp="$2"; shift 2
  local out code
  out=$(env WS_RESOLVE_HOST= WS_CURL_TIMEOUT=4 "$@" bash "$VERIFY" 2>&1); code=$?
  eq "$label 退出码" "$exp" "$code"
  if [ "$code" != "$exp" ]; then printf '%s\n' "$out" | grep -E 'FAIL|VERDICT|MODE=|SKIP' | sed 's/^/        ↳ /'; fi
  LAST_OUT="$out"; LAST_CODE="$code"
}

# ───────────────────────── A. 核验器 ─────────────────────────
echo "=== A. ws-verify-faces.sh 的面判定 ==="
# A1 旧版单面（诊断字段仍在公网、没有 3201）→ 7：没有诊断面就没有"正在服务哪份字节"的物证，不得 OK
if start_fixture $P1 0 MODE=legacy; then
  vrun "A1 legacy 单面（回滚状态）" 7 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_TARGET_REL="$T/rel-legacy" WS_SS_CMD=echo
  eq "A1 MODE" "legacy_single_face" "$(grep '^MODE=' <<<"$LAST_OUT" | cut -d= -f2)"
  has "A1 打出旧版警告" "WARN=LEGACY_SINGLE_FACE" "$LAST_OUT"
  has "A1 点名身份不可核实" "IDENTITY_UNVERIFIABLE" "$LAST_OUT"
  stop_fixture
else no "A1 fixture 起不来" ""; fi

# A2 新版双面健康 → PASS + MODE=dual_face（身份来自它实际加载的发布树、启动时间晚于切流）
if start_fixture $P1 $O1 MODE=dual PID=4242 RELEASE_ROOT="$T/rel-dual"; then
  vrun "A2 dual 双面健康" 0 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 \
    WS_TARGET_REL="$T/rel-dual" WS_EXPECT_START_AFTER="$(( $(now_ms) - 60000 ))" WS_SS_CMD="$T/ss-loop"
  eq "A2 MODE" "dual_face" "$(grep '^MODE=' <<<"$LAST_OUT" | cut -d= -f2)"
  has "A2 身份与批准树一致" "ops_release_id_matches_approved" "$LAST_OUT"
  stop_fixture
else no "A2 fixture 起不来" ""; fi

# A3 新版但诊断面没监听 → 退出码 2（不是关站码）
if start_fixture $P1 0 MODE=dual; then
  vrun "A3 dual 但 3201 缺失" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A3 fixture 起不来" ""; fi

# A4 诊断面自报 app_port 与公网口不符（串台到别的服务）→ 2
if start_fixture $P1 $O1 MODE=dual APP_PORT=1; then
  vrun "A4 app_port 自报不符" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A4 fixture 起不来" ""; fi

# A5 诊断面自报 pid 与 MainPID 不符 → 2
if start_fixture $P1 $O1 MODE=dual PID=7; then
  vrun "A5 pid 与服务不符" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A5 fixture 起不来" ""; fi

# A6 诊断面少字段（fail_closed 不见了）→ 2
if start_fixture $P1 $O1 MODE=dual DROP=fail_closed; then
  vrun "A6 诊断字段不完整" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  has "A6 点名缺哪个字段" "fail_closed" "$LAST_OUT"
  stop_fixture
else no "A6 fixture 起不来" ""; fi

# A7 公网面把诊断细节外露（/healthz/detail 给 200）→ 3
if start_fixture $P1 $O1 MODE=dual DETAIL=200; then
  vrun "A7 detail 对外可见" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A7 fixture 起不来" ""; fi

# A8 访问门失效（未登录 POST /api/world 返回 200）→ 3
if start_fixture $P1 $O1 MODE=dual API=200; then
  vrun "A8 未登录 API 被放行" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A8 fixture 起不来" ""; fi

# A9 首页 200 但没有门面物证、也没有目标树 → unbound 必须判红
if start_fixture $P1 $O1 MODE=dual ROOT=200; then
  vrun "A9 未登录首页放行" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A9 fixture 起不来" ""; fi

# A9b 发布树含门面文件 + 运行时 200 带物证 → PASS（新版公开门面）
if start_fixture $P1 $O1 MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$T/rel-facade"; then
  vrun "A9b 门面 200 与物证一致" 0 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 \
    WS_TARGET_REL="$T/rel-facade" WS_EXPECT_START_AFTER="$(( $(now_ms) - 60000 ))" WS_SS_CMD=echo
  has "A9b 打印 facade profile" "PROFILE=facade" "$LAST_OUT"
  stop_fixture
else no "A9b fixture 起不来" ""; fi

# A9c 发布树说是门面，运行时只是任意 200（无标志串）→ 3（"任何 200 都算过"必须无效）
if start_fixture $P1 $O1 MODE=dual PID=4242 ROOT=200; then
  vrun "A9c 任意 200 冒充门面" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_TARGET_REL="$T/rel-facade" WS_SS_CMD=echo
  stop_fixture
else no "A9c fixture 起不来" ""; fi

# A9d 发布树说是门面，运行时却仍 302 → 3（新版没生效，不能放行）
if start_fixture $P1 $O1 MODE=dual PID=4242 ROOT=302; then
  vrun "A9d 门面未生效仍 302" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_TARGET_REL="$T/rel-facade" WS_SS_CMD=echo
  stop_fixture
else no "A9d fixture 起不来" ""; fi

# A9e 发布树没有门面（旧版/回滚），运行时却冒出 200 门面 → 3
if start_fixture $P1 $O1 MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade; then
  vrun "A9e 旧版树冒出公开门面" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_TARGET_REL="$T/rel-dual" WS_SS_CMD=echo
  stop_fixture
else no "A9e fixture 起不来" ""; fi

# A9f 显式预期与发布树物证矛盾 → 6（用法/环境错误，不开机也能判）
vrun "A9f 显式预期与物证矛盾" 6 WS_PUBLIC_PORT=$DEAD1 WS_OPS_PORT=$DEAD2 WS_GATE_BASE="http://127.0.0.1:$DEAD1" WS_TARGET_REL="$T/rel-dual" WS_EXPECTED_ROOT=facade WS_SS_CMD=echo

# A9g 非法预期值 → 6
vrun "A9g 非法 WS_EXPECTED_ROOT" 6 WS_PUBLIC_PORT=$DEAD1 WS_OPS_PORT=$DEAD2 WS_GATE_BASE="http://127.0.0.1:$DEAD1" WS_TARGET_REL="$T/rel-dual" WS_EXPECTED_ROOT=bogus WS_SS_CMD=echo

# A9h 过期/伪造 session 的首页被当成已登录 → 3
if start_fixture $P1 $O1 MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade COOKIE_ROOT=200; then
  vrun "A9h 过期会话被当成已登录" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_TARGET_REL="$T/rel-facade" WS_SS_CMD=echo
  stop_fixture
else no "A9h fixture 起不来" ""; fi

# A9i 未登录 /api/auth/me 被放行 → 3
if start_fixture $P1 $O1 MODE=dual PID=4242 ME=200; then
  vrun "A9i 未登录 me 被放行" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_TARGET_REL="$T/rel-dual" WS_SS_CMD=echo
  stop_fixture
else no "A9i fixture 起不来" ""; fi

# A9j 登录端点接受空凭据（200）→ 3
if start_fixture $P1 $O1 MODE=dual PID=4242 LOGIN_CODE=200; then
  vrun "A9j 登录端点接受空凭据" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_TARGET_REL="$T/rel-dual" WS_SS_CMD=echo
  stop_fixture
else no "A9j fixture 起不来" ""; fi

# A9k 过期 session 的 API 被放行（200）→ 3
if start_fixture $P1 $O1 MODE=dual PID=4242 BADCOOKIE_API=200; then
  vrun "A9k 过期会话 API 放行" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_TARGET_REL="$T/rel-dual" WS_SS_CMD=echo
  stop_fixture
else no "A9k fixture 起不来" ""; fi

# A10 什么都没监听 → 5（唯一可能关站的码）
vrun "A10 服务完全不可达" 5 WS_PUBLIC_PORT=$DEAD1 WS_OPS_PORT=$DEAD2 WS_GATE_BASE="http://127.0.0.1:$DEAD1" WS_SS_CMD=echo

# A11 静态探针与运行时矛盾（代码说双面，跑出来是单面）→ 4
if start_fixture $P1 0 MODE=legacy; then
  FAKE="$T/rel-dual-mismatch"; mkdir -p "$FAKE/server"; printf '%s\n' "$DUAL_SRC" > "$FAKE/server/world.mjs"
  vrun "A11 静态与运行时矛盾" 4 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_TARGET_REL="$FAKE" WS_SS_CMD=echo
  stop_fixture
else no "A11 fixture 起不来" ""; fi

# A12 诊断面被别的地址绑走（非 loopback）→ 2
if start_fixture $P1 $O1 MODE=dual PID=4242; then
  vrun "A12 诊断口非 loopback 绑定" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD="$T/ss-wide"
  stop_fixture
else no "A12 fixture 起不来" ""; fi

# A13 ss 不可用 → 该项必须记 SKIP，不许冒充通过
if start_fixture $P1 $O1 MODE=dual PID=4242 RELEASE_ROOT="$T/rel-dual"; then
  vrun "A13 ss 不可用时不冒充通过" 0 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 \
    WS_TARGET_REL="$T/rel-dual" WS_EXPECT_START_AFTER="$(( $(now_ms) - 60000 ))" WS_SS_CMD="$T/ss-missing"
  has "A13 明确标 SKIP" "ops_face_loopback_only.*SKIP" "$LAST_OUT"
  stop_fixture
else no "A13 fixture 起不来" ""; fi

# ── P0 运行身份：只有"正在服务的字节 == 批准树"才算过 ──
# A14 诊断面自报的 release_id 是另一棵树的 → 2（旧进程/装错版本都归这一类）
if start_fixture $P1 $O1 MODE=dual PID=4242 RELEASE_ROOT="$T/rel-legacy"; then
  vrun "A14 运行身份与批准树不符" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 \
    WS_TARGET_REL="$T/rel-dual" WS_EXPECT_START_AFTER="$(( $(now_ms) - 60000 ))" WS_SS_CMD=echo
  has "A14 点名身份不一致" "ops_release_id_matches_approved" "$LAST_OUT"
  stop_fixture
else no "A14 fixture 起不来" ""; fi

# A15 身份对、但启动时间早于本次切流 → 2（重启没生效，老进程还在服务）
if start_fixture $P1 $O1 MODE=dual PID=4242 RELEASE_ROOT="$T/rel-dual" START_AT="$(dual_started_at)"; then
  vrun "A15 老进程（启动早于切流）" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 \
    WS_TARGET_REL="$T/rel-dual" WS_EXPECT_START_AFTER="$(now_ms)" WS_SS_CMD=echo
  has "A15 点名旧进程" "ops_started_after_cutover" "$LAST_OUT"
  stop_fixture
else no "A15 fixture 起不来" ""; fi

# A16 诊断面不带身份字段 → 2（字段不全就没法证明是哪份字节）
if start_fixture $P1 $O1 MODE=dual PID=4242 RELEASE_ROOT="$T/rel-dual" IDENTITY=missing; then
  vrun "A16 诊断面缺身份字段" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 \
    WS_TARGET_REL="$T/rel-dual" WS_EXPECT_START_AFTER="$(( $(now_ms) - 60000 ))" WS_SS_CMD=echo
  has "A16 点名缺字段" "ops_face_has_all_fields" "$LAST_OUT"
  stop_fixture
else no "A16 fixture 起不来" ""; fi

# ─────────────────────── B. 切流边界 ───────────────────────
echo "=== B. cutover.sh 的关站边界（假 EMERG 记账，真进程重启）==="
if have_symlinks; then
SB=$T/root
CACHE=$SB/.git-cache/World-Space.git
mkdir -p "$SB/state" "$SB/etc" "$(dirname "$CACHE")"
# 切流预检要求目标能在 git 里被解析成同一个提交、且代码自带发布身份测量：
# 夹具必须是真提交 + 真双面代码。假 SHA 与"注释级双面"都会被正确拒绝。
export GIT_AUTHOR_NAME=ops-selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=ops-selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000' GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000'
git init --bare -q "$CACHE"
g() { git --git-dir="$CACHE" "$@"; }
{ printf '<!doctype html><html><body><p>你想做什么事</p>\n<button id="btn-write">开始</button>\n'
  head -c 9000 /dev/zero | tr '\0' 'x'; printf '\n</html>\n'; } > "$T/facade.html"
bcommit() { # bcommit <parent|-> <world.mjs 内容> [facade 文件]
  local parent=$1 world=$2 facade=${3:-} idx wb fb tree
  idx=$(mktemp "$T/bidx.XXXXXX")
  GIT_INDEX_FILE=$idx g read-tree --empty
  wb=$(printf '%s\n' "$world" | g hash-object -w --stdin)
  GIT_INDEX_FILE=$idx g update-index --add --cacheinfo "100644,$wb,server/world.mjs"
  if [ -n "$facade" ]; then
    fb=$(g hash-object -w -- "$facade")
    GIT_INDEX_FILE=$idx g update-index --add --cacheinfo "100644,$fb,web/v2/public/index.html"
  fi
  tree=$(GIT_INDEX_FILE=$idx g write-tree); rm -f "$idx"
  if [ "$parent" = "-" ]; then printf 'fixture\n' | g commit-tree "$tree"
  else printf 'fixture\n' | g commit-tree "$tree" -p "$parent"; fi
}
PREV=$(bcommit - "$LEGACY_SRC")                                     # 旧版单面，无身份测量
SHA=$(bcommit "$PREV" "$DUAL_SRC")                                  # 双面 + 身份
SHAF=$(bcommit "$SHA" "$DUAL_SRC" "$T/facade.html")                 # 双面 + 身份 + 公开门面
SIDE=$(bcommit "$PREV" "$DUAL_SRC
const FORK = 1;")                                                   # 与发布线分叉
g update-ref refs/heads/v2 "$SHA"
g update-ref refs/heads/fork "$SIDE"
mkrelease() { mkdir -p "$SB/releases/$1"; g archive "$1" | tar -x -C "$SB/releases/$1"; }
mkrelease "$PREV"; mkrelease "$SHA"; mkrelease "$SHAF"; mkrelease "$SIDE"
bapprove() { # bapprove <sha> [mode] [rollback_to]  —— 与 ws-prep.sh 写出的批准记录同形状
  local sha=$1 mode=${2:-upgrade} rb=${3:--}
  printf '%s\n' "$sha" > "$SB/state/approved-sha"
  { echo "sha=$sha"; echo "mode=$mode"; echo "release_line=v2"; echo "rollback_to=$rb"
    echo "release_id=$(rel_id "$SB/releases/$sha")"; } > "$SB/state/approved-meta.txt"
}
: > "$T/emerg.log"
cat > "$T/fake-emerg.sh" <<'EM'
#!/usr/bin/env bash
echo "$1" >> "$EMERG_LOG"
exit 0
EM
chmod +x "$T/fake-emerg.sh"

# 真进程：当前实例 + "重启"脚本（杀旧起新 → 新 pid、新启动时间、新 RELEASE_ROOT）
bstart() { # bstart [VAR=val ...]
  local log="$T/bfx.log"; : > "$log"
  env PUB_PORT="$PB" OPS_PORT="$OB" "$@" node "$FIXTURE" >> "$log" 2>&1 &
  local pid=$!; PIDS="$PIDS $pid"; printf '%s' "$pid" > "$T/bfx.pid"
  local i=0
  while [ $i -lt 100 ]; do
    if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PB/healthz"; then return 0; fi
    if grep -q FIXTURE_FAIL "$log" 2>/dev/null; then return 1; fi
    sleep 0.1; i=$((i+1))
  done
  return 1
}
bstop() { for p in $PIDS; do kill "$p" 2>/dev/null; done; [ -f "$T/bfx.pid" ] && kill "$(cat "$T/bfx.pid")" 2>/dev/null; PIDS=""; rm -f "$T/bfx.pid"; sleep 0.3; }
brestart() { # brestart [VAR=val ...] → 写 $T/b-restart.sh（模拟 systemctl restart）
  { echo '#!/usr/bin/env bash'
    echo 'set -u'
    echo "kill \"\$(cat '$T/bfx.pid')\" 2>/dev/null || true"
    echo 'sleep 0.3'
    printf 'env PUB_PORT=%s OPS_PORT=%s' "$PB" "$OB"
    local a; for a in "$@"; do printf ' %q' "$a"; done
    printf ' node %q >> %q 2>&1 &\n' "$FIXTURE" "$T/bfx.log"
    printf "echo \$! > '%s/bfx.pid'\n" "$T"
    printf 'for i in $(seq 1 100); do curl -s -o /dev/null --max-time 1 "http://127.0.0.1:%s/healthz" && exit 0; sleep 0.1; done\n' "$PB"
    echo 'exit 1'
  } > "$T/b-restart.sh"; chmod +x "$T/b-restart.sh"
}
# 重启命令"成功"但什么也没起来：用来逼出"公网面确实不可用才关站"
{ echo '#!/usr/bin/env bash'
  echo "kill \"\$(cat '$T/bfx.pid')\" 2>/dev/null || true"
  echo 'exit 0'; } > "$T/b-dead.sh"; chmod +x "$T/b-dead.sh"

crun() { # crun <label> <expected_exit> <grep-for-verdict> <pub> <ops-or-0> [extra VAR=val ...]
  # 轮换行为由调用方声明：要固定就显式传 WS_ROTATE_SECRET=…（B1-B4 固定 0）；不传 = 测默认值（B5）
  local label="$1" exp="$2" needle="$3" pub="$4" ops="$5"; shift 5
  local out code
  out=$(env WS_ROOT="$SB" WS_EMERG="$T/fake-emerg.sh" WS_VERIFY="$VERIFY" \
        WS_RESTART_CMD=true WS_PID_CMD="cat $T/bfx.pid" EMERG_LOG="$T/emerg.log" \
        WS_PUBLIC_PORT="$pub" WS_OPS_PORT="$ops" WS_GATE_BASE="http://127.0.0.1:$pub" \
        WS_RESOLVE_HOST= WS_CURL_TIMEOUT=4 WS_POLL_TRIES=3 WS_SS_CMD="$T/ss-missing" "$@" \
        bash "$HERE/cutover.sh" 2>&1); code=$?
  CRUN_OUT="$out"
  eq "$label 退出码" "$exp" "$code"
  has "$label 结论行" "$needle" "$out"
}

# B1 新版双面健康 → 切流成功（A 场景：真重启 + 运行身份闭环），一次都没关站
: > "$T/emerg.log"; bapprove "$SHA"; ln -sfn "$SB/releases/$PREV" "$SB/current"
if bstart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$PREV"; then
  brestart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$SHA"
  crun "B1 新版健康切换" 0 "CUTOVER=OK" $PB $OB WS_ROTATE_SECRET=0 WS_RESTART_CMD="$T/b-restart.sh"
  eq "B1 current 已切换" "$SHA" "$(basename "$(readlink "$SB/current")")"
  eq "B1 关站次数" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  bstop
else no "B1 fixture 起不来" ""; fi

# B1b 门面发布：目标树含门面文件 + 运行时 200 门面 → 切流成功，不关站
: > "$T/emerg.log"; ln -sfn "$SB/releases/$PREV" "$SB/current"; bapprove "$SHAF"
if bstart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$PREV"; then
  brestart MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$SB/releases/$SHAF"
  crun "B1b 门面发布切换" 0 "CUTOVER=OK" $PB $OB WS_ROTATE_SECRET=0 WS_RESTART_CMD="$T/b-restart.sh"
  eq "B1b current 已切换" "$SHAF" "$(basename "$(readlink "$SB/current")")"
  eq "B1b 关站次数" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  bstop
else no "B1b fixture 起不来" ""; fi

# B1c 发布树说是门面，运行时仍 302 → 留现场不关站
: > "$T/emerg.log"; ln -sfn "$SB/releases/$PREV" "$SB/current"; bapprove "$SHAF"
if bstart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$PREV"; then
  brestart MODE=dual PID=auto ROOT=302 RELEASE_ROOT="$SB/releases/$SHAF"
  crun "B1c 门面未生效" 1 "CUTOVER=FAILED_SCENE_PRESERVED" $PB $OB WS_ROTATE_SECRET=0 WS_RESTART_CMD="$T/b-restart.sh"
  eq "B1c 关站次数（关键：必须 0）" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  bstop
else no "B1c fixture 起不来" ""; fi

# B2 公网面看起来正常但诊断面没起来 → 必须"留现场不关站"（旧版会在这里误关）
: > "$T/emerg.log"; ln -sfn "$SB/releases/$PREV" "$SB/current"; bapprove "$SHA"
if bstart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$PREV"; then
  brestart MODE=dual PID=auto OPS_PORT=0 RELEASE_ROOT="$SB/releases/$SHA"
  crun "B2 诊断面缺失" 1 "CUTOVER=FAILED_SCENE_PRESERVED" $PB $OB WS_ROTATE_SECRET=0 WS_RESTART_CMD="$T/b-restart.sh"
  eq "B2 关站次数（关键：必须 0）" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  bstop
else no "B2 fixture 起不来" ""; fi

# B3 重启命令退出 0，但真的什么都没起来 → 才允许关站（先回到"待升级"状态，否则预检会判 ALREADY_LIVE）
: > "$T/emerg.log"; ln -sfn "$SB/releases/$PREV" "$SB/current"; bapprove "$SHA"
if bstart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$PREV"; then
  crun "B3 服务确实不可用" 1 "CUTOVER=FAILED_AND_CLOSED" $PB $OB WS_ROTATE_SECRET=0 WS_RESTART_CMD="$T/b-dead.sh"
  eq "B3 关站次数（应恰好 1）" "1" "$(grep -c '^close$' "$T/emerg.log" || true)"
  bstop
else no "B3 fixture 起不来" ""; fi

# B4 回滚到没有身份物证的旧版 → 拒绝（无法证明在服务的是它）
: > "$T/emerg.log"; bapprove "$PREV" rollback "$PREV"; ln -sfn "$SB/releases/$SHA" "$SB/current"
before_cur=$(basename "$(readlink "$SB/current")")
if bstart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$SHA"; then
  crun "B4 无身份旧版回滚被拒" 3 "CUTOVER=ABORT_IDENTITY_UNSUPPORTED_BY_TARGET" $PB $OB WS_ROTATE_SECRET=0 \
    WS_MODE=rollback WS_ROLLBACK_TO="$PREV"
  eq "B4 current 未动" "$before_cur" "$(basename "$(readlink "$SB/current")")"
  eq "B4 关站次数" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  bstop
else no "B4 fixture 起不来" ""; fi

# B4ok 回滚到有身份的前一个版本 → 两把钥匙齐全、真重启、身份核实 → OK，不关站
: > "$T/emerg.log"; bapprove "$SHA" rollback "$SHA"; ln -sfn "$SB/releases/$SHAF" "$SB/current"
if bstart MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$SB/releases/$SHAF"; then
  brestart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$SHA"
  crun "B4ok 合法回滚" 0 "CUTOVER=OK" $PB $OB WS_ROTATE_SECRET=0 WS_RESTART_CMD="$T/b-restart.sh" \
    WS_MODE=rollback WS_ROLLBACK_TO="$SHA"
  eq "B4ok current 已回滚" "$SHA" "$(basename "$(readlink "$SB/current")")"
  eq "B4ok 留档 mode" "mode=rollback" "$(grep -h '^mode=' "$(ls -1t "$SB/state"/cutover-*.txt | head -1)")"
  eq "B4ok 关站次数" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  bstop
else no "B4ok fixture 起不来" ""; fi

# B4r 升级路径塞旧版 → 预检拒绝，零写入，不关站
: > "$T/emerg.log"; bapprove "$PREV"; ln -sfn "$SB/releases/$SHA" "$SB/current"
before_cur=$(basename "$(readlink "$SB/current")")
crun "B4r 旧版冒充升级被拒" 3 "CUTOVER=ABORT_LEGACY_AS_UPGRADE" $PB $OB WS_ROTATE_SECRET=0
eq "B4r current 未动" "$before_cur" "$(basename "$(readlink "$SB/current")")"
eq "B4r 关站次数" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"

# B4s 批准点不在发布线（分叉候选）→ 预检拒绝
: > "$T/emerg.log"; bapprove "$SIDE"; ln -sfn "$SB/releases/$PREV" "$SB/current"
crun "B4s 越线候选被拒" 3 "CUTOVER=ABORT_NOT_IN_RELEASE_LINE" $PB $OB WS_ROTATE_SECRET=0
eq "B4s 关站次数" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"

# B5/B6/B7 轮换默认值（2026-10-05 起默认 0）：未设置 = 不轮换；显式 1 = 轮换；显式 0 = 与未设置同行为。
# 红绿成对：B5 断言「不变」、B6 断言「变」——只见过一种状态的判据不算验证过。
# 密钥文件每个用例独立种子，防上一用例残留造成假绿。
reset_cut() { # 每次切流前把沙箱恢复到同一初态
  bapprove "$SHA"
  ln -sfn "$SB/releases/$PREV" "$SB/current"
  : > "$T/emerg.log"
}
seed_secret() { printf 'seed-rot-%s\n' "$1" > "$SB/etc/session-secret.txt"; }
secret_hash() { sha256sum "$SB/etc/session-secret.txt" | cut -c1-12; }
rec_rotated() { grep -h '^session_secret_rotated=' "$(ls -1t "$SB/state"/cutover-*.txt | head -1)"; }
if bstart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$PREV"; then
  unset WS_ROTATE_SECRET   # B5 测的就是「未设置」本身，不吃环境残留
  reset_cut; seed_secret b5-default; B5H=$(secret_hash)
  brestart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$SHA"
  crun "B5 默认（未设置）不轮换" 0 "CUTOVER=OK" $PB $OB WS_RESTART_CMD="$T/b-restart.sh"
  eq "B5 session 密钥一字未变" "$B5H" "$(secret_hash)"
  eq "B5 留档 session_secret_rotated" "session_secret_rotated=0" "$(rec_rotated)"
  reset_cut; seed_secret b6-explicit-on; B6H=$(secret_hash)
  brestart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$SHA"
  crun "B6 显式 1 才轮换" 0 "CUTOVER=OK" $PB $OB WS_RESTART_CMD="$T/b-restart.sh" WS_ROTATE_SECRET=1
  if [ "$B6H" != "$(secret_hash)" ]; then ok "B6 session 密钥已重写"; else no "B6 session 密钥已重写" "密钥没变（轮换没生效）"; fi
  eq "B6 留档 session_secret_rotated" "session_secret_rotated=1" "$(rec_rotated)"
  reset_cut; seed_secret b7-explicit-off; B7H=$(secret_hash)
  brestart MODE=dual PID=auto RELEASE_ROOT="$SB/releases/$SHA"
  crun "B7 显式 0 不轮换" 0 "CUTOVER=OK" $PB $OB WS_RESTART_CMD="$T/b-restart.sh" WS_ROTATE_SECRET=0
  eq "B7 session 密钥一字未变" "$B7H" "$(secret_hash)"
  eq "B7 留档 session_secret_rotated" "session_secret_rotated=0" "$(rec_rotated)"
  bstop
else no "B5-B7 fixture 起不来" ""; fi

else
  skip "B1 新版健康切换"      "本平台 ln -s 不产生符号链接，切流语义需在 Linux 上验（见报告）"
  skip "B1b 门面发布切换"     "同上"
  skip "B1c 门面未生效"       "同上"
  skip "B2 诊断面缺失不关站"  "同上"
  skip "B3 真不可用才关站"    "同上"
  skip "B4 无身份旧版回滚被拒" "同上"
  skip "B4ok 合法回滚"        "同上"
  skip "B4r 旧版冒充升级被拒" "同上"
  skip "B4s 越线候选被拒"     "同上"
  skip "B5 默认（未设置）不轮换" "同上"
  skip "B6 显式 1 才轮换"     "同上"
  skip "B7 显式 0 不轮换"     "同上"
fi
# ─────────────────────── C. env 写入安全 ───────────────────────
echo "=== C. ws-env-put.sh 的无换行防护 ==="
mk_env() { # mk_env <path> <trailing_newline:1|0>
  printf 'WS_PROVIDER=openai_compatible\nWS_LLM_KEY=sk-fixture-not-real\nWS_SEARCH_KEY_2=tvly-fixture==' > "$1"
  [ "$2" = "1" ] && printf '\n' >> "$1"
}
line_hash() { sed -n "$2p" "$1" | tr -d '\n' | sha256sum | cut -c1-12; }

# C1 末行无换行（事故现场）：追加后原有一行不许被污染
F="$T/env-noNL"; mk_env "$F" 0
before_sensitive=$(line_hash "$F" 3); before_bytes=$(wc -c < "$F")
OUT=$(env WS_ENV_FILE="$F" bash "$ENVPUT" WS_OPS_PORT 3201 2>&1); code=$?
eq "C1 无换行文件退出码" "0" "$code"
has "C1 报告动作" "action=appended" "$OUT"
eq "C1 WS_SEARCH_KEY_2 未变" "$before_sensitive" "$(line_hash "$F" 3)"
eq "C1 行首锚定=1" "1" "$(grep -c '^WS_OPS_PORT=' "$F" || true)"
eq "C1 全文出现=1（无粘连）" "1" "$(grep -c 'WS_OPS_PORT=' "$F" || true)"
eq "C1 字节算式" "$((before_bytes + 1 + 17))" "$(wc -c < "$F")"
eq "C1 行数" "4" "$(wc -l < "$F")"
# C1b 同一把尺子的红侧：预先造成粘连形状，--check 必须判红
BAD="$T/env-polluted"; mk_env "$BAD" 1; printf 'WS_OTHER=xWS_OPS_PORT=3201\n' >> "$BAD"
env WS_ENV_FILE="$BAD" bash "$ENVPUT" --check WS_OPS_PORT > /dev/null 2>&1
eq "C1b 污染形状必须判红" "2" "$?"
env WS_ENV_FILE="$F" bash "$ENVPUT" --check WS_OPS_PORT > /dev/null 2>&1
eq "C1c 干净文件判绿" "0" "$?"

# C2 末行有换行：只多一行，其余逐行不动
G="$T/env-NL"; mk_env "$G" 1
g_before=$(sed '4d' "$G" | sha256sum | cut -c1-12)
OUT=$(env WS_ENV_FILE="$G" bash "$ENVPUT" WS_OPS_PORT 3201 2>&1); code=$?
eq "C2 有换行文件退出码" "0" "$code"
eq "C2 行数" "4" "$(wc -l < "$G")"
eq "C2 原有三行未动" "$g_before" "$(sed '4d' "$G" | sha256sum | cut -c1-12)"

# C3 幂等：再写一次同值，内容一字不变
H="$T/env-idem"; mk_env "$H" 0
env WS_ENV_FILE="$H" bash "$ENVPUT" WS_OPS_PORT 3201 > /dev/null 2>&1
c1v=$(sha256sum "$H" | cut -c1-12)
OUT=$(env WS_ENV_FILE="$H" bash "$ENVPUT" WS_OPS_PORT 3201 2>&1)
c2v=$(sha256sum "$H" | cut -c1-12)
eq "C3 二次写入内容不变" "$c1v" "$c2v"
has "C3 第二次是 replaced" "action=replaced" "$OUT"
eq "C3 锚定仍为 1" "1" "$(grep -c '^WS_OPS_PORT=' "$H" || true)"

# C4 改值：只动那一行，且含 '=' 的 base64 值不许被牵连
K="$T/env-val"; mk_env "$K" 1
kv_before=$(line_hash "$K" 3)
env WS_ENV_FILE="$K" bash "$ENVPUT" WS_OPS_PORT 3202 > /dev/null 2>&1
eq "C4 改值生效" "WS_OPS_PORT=3202" "$(grep '^WS_OPS_PORT=' "$K")"
eq "C4 敏感行仍未动" "$kv_before" "$(line_hash "$K" 3)"

# C5 用法错误必须拒写且文件不变
M="$T/env-bad"; mk_env "$M" 1; m0=$(sha256sum "$M" | cut -c1-12)
env WS_ENV_FILE="$M" bash "$ENVPUT" WS_OPS_PORT "" > /dev/null 2>&1; eq "C5 空值被拒" "6" "$?"
env WS_ENV_FILE="$M" bash "$ENVPUT" bad_lower 1   > /dev/null 2>&1; eq "C5 小写键被拒" "6" "$?"
env WS_ENV_FILE="$M" bash "$ENVPUT" WS_NEW "a
b" > /dev/null 2>&1; eq "C5 含换行的值被拒" "6" "$?"
eq "C5 文件一字未动" "$m0" "$(sha256sum "$M" | cut -c1-12)"

# C6 备份确实在位且可用
eq "C6 生成了备份" "yes" "$(ls "$T/env-noNL".bak-envput-* >/dev/null 2>&1 && echo yes || echo no)"

# C7 「末行有没有换行」这条读数本身（上一版就是它错，导致给有换行的文件多加空行）
PNL="$T/probe-nl"; PNN="$T/probe-nonl"; mk_env "$PNL" 1; mk_env "$PNN" 0
has "C7 有换行 → 读成 yes" "is_newline  *yes" "$(env WS_ENV_FILE="$PNL" bash "$ENVPUT" --check WS_PROVIDER 2>&1)"
has "C7 无换行 → 读成 no"  "is_newline  *no"  "$(env WS_ENV_FILE="$PNN" bash "$ENVPUT" --check WS_PROVIDER 2>&1)"

# ─────────────────────── D. 语法与静态检查 ───────────────────────
echo "=== D. 语法 / 静态检查 ==="
for f in cutover.sh ws-prep.sh ws-verify-faces.sh ws-env-put.sh ops-selftest.sh release-tooling-selftest.sh; do
  if bash -n "$HERE/$f" 2> "$T/syn"; then ok "bash -n $f" ""; else no "bash -n $f" "$(cat "$T/syn" | head -2)"; fi
done
if node --check "$FIXTURE" 2> "$T/syn2"; then ok "node --check fixture" ""; else no "node --check fixture" "$(head -2 "$T/syn2")"; fi
if node --check "$HERE/face-probe.mjs" 2> "$T/syn3"; then ok "node --check face-probe" ""; else no "node --check face-probe" "$(head -2 "$T/syn3")"; fi
if node --check "$HERE/release-id.mjs" 2> "$T/syn4"; then ok "node --check release-id" ""; else no "node --check release-id" "$(head -2 "$T/syn4")"; fi
# 核验器版本绑定：钉住的哈希必须就是仓库里这份核验器，改一处就得重新钉，不能带着旧钉上线
eq "核验器哈希钉与文件一致" "$(sha256sum "$HERE/ws-verify-faces.sh" | cut -d' ' -f1)" \
   "$(awk 'NR==1{print $1}' "$HERE/ws-verify-faces.sh.sha256" 2>/dev/null)"
# 自测绝不允许碰生产路径：每一次调用 ENVPUT 都必须显式带着 WS_ENV_FILE 指向临时文件
unguarded=$(grep '\$ENVPUT' "$0" | grep -vc 'WS_ENV_FILE=' || true)
eq "每次 ws-env-put 调用都被 WS_ENV_FILE 圈住" "0" "${unguarded:-0}"
unguarded2=$(grep 'bash "\$HERE/cutover.sh"' "$0" | wc -l)
eq "cutover 调用只经由 crun（带 WS_ROOT 沙箱）" "1" "$unguarded2"

echo
printf '自测合计 %s 项，失败 %s 项，跳过 %s 项\n' "$TOTAL" "$FAILED" "$SKIPPED"
[ "$SKIPPED" = "0" ] || echo "注意：有 $SKIPPED 项被跳过（本平台缺能力）—— 跳过 ≠ 通过，须在 Linux 上补跑"
[ "$FAILED" = "0" ] || exit 1
[ "$SKIPPED" = "0" ] || exit 3
echo "OPS_SELFTEST=PASS"
