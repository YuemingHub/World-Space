#!/usr/bin/env bash
# release-tooling-selftest.sh —— 发布工具（cutover.sh / ws-prep.sh）的身份与路径自测
#
# 契约（2026-11-01 收紧后的两条 P0）：
#   候选必须显式（WS_REF 40 位）→ 必须能在 git 缓存里解析成同一个提交 → 必须属于发布线
#   （refs/heads/v2 在它的历史里）→ 必须是当前线上版本的后代 → legacy 单面只允许走回滚路径；
#   回滚必须两把钥匙（WS_MODE=rollback + WS_ROLLBACK_TO），且目标必须是当前线上版本的祖先。
#
# 每个场景都检查：退出码 / current / approved-sha / 发布树 / 留档 / 关站记录 / 是否有部分写入。
# 只碰 $T 下的沙箱（可用 TOOLING_TEST_ROOT / TOOLING_TEST_ORIGIN 指向容器里的固定路径）。
#
# 用法：bash release-tooling-selftest.sh     （退出码 0 = 全部通过；3 = 有跳过）
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREP="${WS_PREP:-$HERE/ws-prep.sh}"
CUT="${WS_CUTOVER:-$HERE/cutover.sh}"
VERIFY="${WS_VERIFY:-$HERE/ws-verify-faces.sh}"
FIXTURE="${WS_FIXTURE:-$HERE/ops-fixture-face.mjs}"
T=$(mktemp -d)
ROOT="${TOOLING_TEST_ROOT:-$T/root}"
ORIGIN="${TOOLING_TEST_ORIGIN:-$T/origin.git}"
ORIGIN_URL="file://$ORIGIN"
BASE=${WS_TEST_PORT_BASE:-4811}
PUB=$BASE; OPS=$((BASE+1))
PIDS=""
FAILED=0; TOTAL=0; SKIPPED=0
LAST_OUT=""

ok()   { TOTAL=$((TOTAL+1)); printf '  \033[32m✓\033[0m %-58s %s\n' "$1" "${2:-}"; }
no()   { TOTAL=$((TOTAL+1)); FAILED=$((FAILED+1)); printf '  \033[31m✗\033[0m %-58s %s\n' "$1" "${2:-}"; }
skip() { SKIPPED=$((SKIPPED+1)); printf '  \033[33m-\033[0m %-58s %s\n' "$1" "${2:-}"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1" "=$3"; else no "$1" "期望 $2 实得 $3"; fi; }
has()  { if printf '%s' "$3" | grep -q "$2"; then ok "$1" "含 /$2/"; else no "$1" "缺 /$2/（输出：$(printf '%s' "$3" | tr '\n' ' ' | head -c 160)）"; fi; }

cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT

printf '#!/usr/bin/env bash\nexit 1\n' > "$T/ss-missing"; chmod +x "$T/ss-missing"
cat > "$T/fake-emerg.sh" <<'EM'
#!/usr/bin/env bash
echo "$1" >> "$EMERG_LOG"
exit 0
EM
chmod +x "$T/fake-emerg.sh"

for p in "$PUB" "$OPS"; do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$p/" 2>/dev/null; then
    printf 'FAIL  端口 %s 已被占用——换 WS_TEST_PORT_BASE 再跑\n' "$p"; exit 6
  fi
done

start_fixture() { # start_fixture [VAR=val ...]
  local log="$T/fx.log"; : > "$log"
  env PUB_PORT="$PUB" OPS_PORT="$OPS" "$@" node "$FIXTURE" > "$log" 2>&1 &
  local pid=$!; PIDS="$PIDS $pid"; local i=0
  while [ $i -lt 100 ]; do
    if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PUB/healthz"; then return 0; fi
    if grep -q FIXTURE_FAIL "$log" 2>/dev/null; then return 1; fi
    sleep 0.1; i=$((i+1))
  done
  return 1
}
stop_fixture() { for p in $PIDS; do kill "$p" 2>/dev/null; done; PIDS=""; sleep 0.2; }

# ───────────── git 沙箱：真提交、真树、真 refs ─────────────
export GIT_AUTHOR_NAME=tooling-selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=tooling-selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000' GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000'
git_() { git --git-dir="$ORIGIN" "$@"; }

mkcommit() { # mkcommit <parent|-> <world.mjs 内容> [facade 文件]
  local parent=$1 world=$2 facade=${3:-} idx wb fb tree
  idx=$(mktemp "$T/idx.XXXXXX")
  GIT_INDEX_FILE=$idx git_ read-tree --empty
  wb=$(printf '%s\n' "$world" | git_ hash-object -w --stdin)
  GIT_INDEX_FILE=$idx git_ update-index --add --cacheinfo "100644,$wb,server/world.mjs"
  if [ -n "$facade" ]; then
    fb=$(git_ hash-object -w -- "$facade")
    GIT_INDEX_FILE=$idx git_ update-index --add --cacheinfo "100644,$fb,web/v2/public/index.html"
  fi
  tree=$(GIT_INDEX_FILE=$idx git_ write-tree)
  rm -f "$idx"
  if [ "$parent" = "-" ]; then printf 'fixture\n' | git_ commit-tree "$tree"
  else printf 'fixture\n' | git_ commit-tree "$tree" -p "$parent"; fi
}

{ printf '<!doctype html><html><body><p>你想做什么事</p>\n<button id="btn-write">开始</button>\n'
  head -c 9000 /dev/zero | tr '\0' 'x'; printf '\n</html>\n'; } > "$T/facade.html"
printf '<html>tiny</html>\n' > "$T/tiny.html"

rm -rf "$ORIGIN"; git init --bare -q "$ORIGIN"
LEGACY=$(mkcommit - 'const CFG = { webDir: 1 };')
DUAL=$(mkcommit "$LEGACY" 'const CFG = { opsPort: 3201 };')
FACADE=$(mkcommit "$DUAL" 'const CFG = { opsPort: 3201 };' "$T/facade.html")
SIDE=$(mkcommit "$LEGACY" 'const CFG = { opsPort: 3201 }; // forked from legacy')  # 与发布线分叉（内容必须与 DUAL 不同，否则是同一次提交）
BADFACADE=$(mkcommit "$DUAL" 'const CFG = { opsPort: 3201 };' "$T/tiny.html")
UNKNOWN=0123456789abcdef0123456789abcdef01234567
git_ update-ref refs/heads/v2 "$DUAL"
git_ update-ref refs/heads/legacy "$LEGACY"
git_ update-ref refs/heads/facade "$FACADE"
git_ update-ref refs/heads/side "$SIDE"
printf '沙箱提交：LEGACY=%.10s DUAL=%.10s FACADE=%.10s SIDE=%.10s\n' "$LEGACY" "$DUAL" "$FACADE" "$SIDE"

reset_root() {
  rm -rf "$ROOT/releases" "$ROOT/state" "$ROOT/.git-cache" "$ROOT/current"
  mkdir -p "$ROOT/releases" "$ROOT/state" "$ROOT/etc"
  : > "$T/emerg.log"
}
mkrelease() { # mkrelease <sha>
  rm -rf "$ROOT/releases/$1"; mkdir -p "$ROOT/releases/$1"
  git_ archive "$1" | tar -x -C "$ROOT/releases/$1"
}
set_current() { ln -sfn "$ROOT/releases/$1" "$ROOT/current"; }
approve() { printf '%s\n' "$1" > "$ROOT/state/approved-sha"; }
approved_now() { cat "$ROOT/state/approved-sha" 2>/dev/null || echo -; }
current_now() { local t; t=$(readlink "$ROOT/current" 2>/dev/null || true); [ -n "$t" ] && basename "$t" || echo -; }
release_list() { ls -1 "$ROOT/releases" 2>/dev/null | sort | tr '\n' ',' || true; }
receipt_count() { ls -1 "$ROOT/state"/cutover-*.txt 2>/dev/null | wc -l; }
close_count() { grep -c '^close$' "$T/emerg.log" 2>/dev/null || true; }

BEFORE_CUR=""; BEFORE_APP=""; BEFORE_REL=""; BEFORE_REC=""
mark() { BEFORE_CUR=$(current_now); BEFORE_APP=$(approved_now); BEFORE_REL=$(release_list); BEFORE_REC=$(receipt_count); }
assert_untouched() { # assert_untouched <label>
  eq "$1 current 未变"    "$BEFORE_CUR" "$(current_now)"
  eq "$1 approved-sha 未变" "$BEFORE_APP" "$(approved_now)"
  eq "$1 发布树未增"      "$BEFORE_REL" "$(release_list)"
  eq "$1 无新留档"        "$BEFORE_REC" "$(receipt_count)"
  eq "$1 未关站"          "0" "$(close_count)"
}

prep_run() { # prep_run <fetch|verify> [VAR=val ...]
  local sub=$1; shift
  env WS_ROOT="$ROOT" WS_REPO="$ORIGIN_URL" WS_BRANCH=v2 "$@" bash "$PREP" "$sub" 2>&1
}
can_symlink() { rm -f "$T/symprobe"; ln -s "$T" "$T/symprobe" 2>/dev/null && [ -L "$T/symprobe" ]; }
run_cut() { # run_cut <label> <expected_exit> <needle> [VAR=val ...]
  local label=$1 exp=$2 needle=$3; shift 3
  local out code
  out=$(env WS_ROOT="$ROOT" WS_EMERG="$T/fake-emerg.sh" WS_VERIFY="$VERIFY" \
        WS_RESTART_CMD=true WS_PID_CMD="echo 4242" EMERG_LOG="$T/emerg.log" \
        WS_PUBLIC_PORT="$PUB" WS_OPS_PORT="$OPS" WS_GATE_BASE="http://127.0.0.1:$PUB" \
        WS_RESOLVE_HOST= WS_CURL_TIMEOUT=4 WS_POLL_TRIES=3 WS_SS_CMD="$T/ss-missing" "$@" \
        bash "$CUT" 2>&1); code=$?
  eq "$label 退出码" "$exp" "$code"
  has "$label 结论" "$needle" "$out"
  LAST_OUT="$out"
}

# ─────────────────────── P. ws-prep.sh 的批准路径 ───────────────────────
echo "=== P. ws-prep.sh：没有显式候选就不写批准点 ==="
if [ "$(id -u)" != "0" ]; then
  skip "P 全部" "ws-prep.sh 要求 root（服务器上用 root 跑自测）"
else
# P1 未给 WS_REF → 零写入、明确报错（2026-11-01 之前这里默认 e8284c4 并直接可用）
reset_root; mark
OUT=$(prep_run fetch); code=$?
eq "P1 无候选退出码" "2" "$code"
has "P1 点名缺候选" "PREDEPLOY_ABORT_TARGET_REQUIRED" "$OUT"
assert_untouched "P1"
eq "P1 未创建 git 缓存" "no" "$([ -e "$ROOT/.git-cache" ] && echo yes || echo no)"
eq "P1 未创建日志目录" "no" "$([ -d "$ROOT/state/logs" ] && echo yes || echo no)"

# P2 显式指定旧版（升级路径）→ 必须拒绝，且不写批准点
reset_root; set_current "$DUAL"; mark
OUT=$(prep_run fetch WS_REF="$LEGACY"); code=$?
eq "P2 旧版作为升级目标" "2" "$code"
has "P2 拒绝 legacy 升级" "PREDEPLOY_ABORT_LEGACY_AS_UPGRADE" "$OUT"
assert_untouched "P2"

# P3 版本回退（当前线上比候选新）→ 必须拒绝
reset_root; set_current "$FACADE"; mark
OUT=$(prep_run fetch WS_REF="$DUAL"); code=$?
eq "P3 回退候选退出码" "2" "$code"
has "P3 拒绝版本回退" "PREDEPLOY_ABORT_VERSION_REGRESSION" "$OUT"
assert_untouched "P3"

# P4 未知提交号 → 必须拒绝（不得把"取不回来"当成"就它了"）
reset_root; set_current "$DUAL"; mark
OUT=$(prep_run fetch WS_REF="$UNKNOWN"); code=$?
eq "P4 未知提交退出码" "2" "$code"
has "P4 点名身份未知" "PREDEPLOY_ABORT_\(TARGET_IDENTITY_UNKNOWN\|FETCH_FAILED\)" "$OUT"
assert_untouched "P4"

# P5 不在发布线上（从旧版分叉的候选）→ 必须拒绝
reset_root; set_current "$LEGACY"; mark
OUT=$(prep_run fetch WS_REF="$SIDE"); code=$?
eq "P5 分叉候选退出码" "2" "$code"
has "P5 拒绝越线候选" "PREDEPLOY_ABORT_NOT_IN_RELEASE_LINE" "$OUT"
assert_untouched "P5"

# P6 正常新版本：fetch + verify 成功，批准点 = 候选，current 一动不动
reset_root; set_current "$DUAL"; mark
OUT=$(prep_run fetch WS_REF="$FACADE"); code=$?
eq "P6 正常候选 fetch" "0" "$code"
OUT=$(prep_run verify WS_REF="$FACADE"); code=$?
eq "P6 正常候选 verify" "0" "$code"
has "P6 登记批准点" "GIT=PASS" "$OUT"
eq "P6 approved-sha" "$FACADE" "$(approved_now)"
eq "P6 current 未变" "$DUAL" "$(current_now)"
eq "P6 发布树就位" "yes" "$([ -f "$ROOT/releases/$FACADE/server/world.mjs" ] && echo yes || echo no)"

# P7 发布树被改过一个字节 → verify 必须拒绝且不写批准点（验证先于批准）
reset_root; set_current "$DUAL"; mark
prep_run fetch WS_REF="$FACADE" >/dev/null 2>&1
printf 'tampered\n' >> "$ROOT/releases/$FACADE/server/world.mjs"
mark
OUT=$(prep_run verify WS_REF="$FACADE"); code=$?
eq "P7 内容漂移退出码" "2" "$code"
has "P7 点名内容不一致" "PREDEPLOY_ABORT_GIT_DRIFT" "$OUT"
eq "P7 approved-sha 未写" "-" "$(approved_now)"
eq "P7 current 未变" "$DUAL" "$(current_now)"

# P8 显式回滚：两把钥匙齐全 → 允许登记旧版，current 仍不动
reset_root; set_current "$FACADE"; mark
OUT=$(prep_run fetch WS_MODE=rollback WS_ROLLBACK_TO="$DUAL" WS_REF="$DUAL"); code=$?
eq "P8 回滚 fetch" "0" "$code"
OUT=$(prep_run verify WS_MODE=rollback WS_ROLLBACK_TO="$DUAL" WS_REF="$DUAL"); code=$?
eq "P8 回滚 verify" "0" "$code"
eq "P8 approved-sha" "$DUAL" "$(approved_now)"
eq "P8 current 未变" "$FACADE" "$(current_now)"

# P9 回滚缺第二把钥匙 → 拒绝
reset_root; set_current "$FACADE"; mark
OUT=$(prep_run fetch WS_MODE=rollback WS_REF="$DUAL"); code=$?
eq "P9 缺 ROLLBACK_TO 退出码" "2" "$code"
has "P9 点名缺第二把钥匙" "PREDEPLOY_ABORT_ROLLBACK_TARGET_REQUIRED" "$OUT"
assert_untouched "P9"

# P10 回滚目标不是祖先（想借回滚路径往前跳）→ 拒绝
reset_root; set_current "$DUAL"; mark
OUT=$(prep_run fetch WS_MODE=rollback WS_ROLLBACK_TO="$FACADE" WS_REF="$FACADE"); code=$?
eq "P10 伪回滚退出码" "2" "$code"
has "P10 拒绝非祖先" "PREDEPLOY_ABORT_ROLLBACK_NOT_ANCESTOR" "$OUT"
assert_untouched "P10"

# P11 发布树里被塞进符号链接 → verify 必须拒绝且不写批准点（find -type f 看不见链接）
if can_symlink; then
  reset_root; set_current "$DUAL"
  prep_run fetch WS_REF="$FACADE" >/dev/null 2>&1
  ln -s /etc/passwd "$ROOT/releases/$FACADE/leak.txt"
  mark
  OUT=$(prep_run verify WS_REF="$FACADE"); code=$?
  eq "P11 符号链接退出码" "2" "$code"
  has "P11 点名符号链接" "PREDEPLOY_ABORT_GIT_DRIFT" "$OUT"
  eq "P11 approved-sha 未写" "-" "$(approved_now)"
else skip "P11 符号链接" "本平台建不了符号链接"; fi

# P12 没有 current（升级路径）→ 拒绝：不知道从哪来就不算前进
reset_root; mark
OUT=$(prep_run fetch WS_REF="$FACADE"); code=$?
eq "P12 无 current 退出码" "2" "$code"
has "P12 点名线上身份未知" "PREDEPLOY_ABORT_LIVE_IDENTITY_UNKNOWN" "$OUT"
eq "P12 approved-sha 未写" "-" "$(approved_now)"
eq "P12 未展开发布树" "no" "$([ -e "$ROOT/releases/$FACADE" ] && echo yes || echo no)"
fi

# ─────────────────────── C. cutover.sh 的切换路径 ───────────────────────
echo "=== C. cutover.sh：身份、发布线、前进方向、两把钥匙 ==="
# 每个场景准备：沙箱 git 缓存 + 发布树 + current + approved-sha
setup_cut() { # setup_cut <live_sha|none> <approved_sha>
  reset_root
  mkdir -p "$ROOT/.git-cache"
  git clone -q --bare "$ORIGIN" "$ROOT/.git-cache/World-Space.git"
  mkrelease "$LEGACY"; mkrelease "$DUAL"; mkrelease "$FACADE"; mkrelease "$SIDE"
  [ "$1" = none ] || set_current "$1"
  approve "$2"
}

# C1 正常升级（发布线内、向前、双面 + 门面）→ 成功，current 换成候选，留档 path=upgrade
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade; then
  run_cut "C1 正常升级" 0 "CUTOVER=OK" WS_MODE=upgrade
  eq "C1 current 已切换" "$FACADE" "$(current_now)"
  eq "C1 留档 mode" "mode=upgrade" "$(grep -h '^mode=' "$(ls -1t "$ROOT/state"/cutover-*.txt | head -1)")"
  eq "C1 关站次数" "0" "$(close_count)"
  stop_fixture
else no "C1 fixture 起不来" ""; fi

# C2 当前线上比批准点新（静默降级）→ 必须拒绝且零写入（旧版会直接切回去）
setup_cut "$FACADE" "$DUAL"; mark
if start_fixture MODE=dual PID=4242; then
  run_cut "C2 静默降级" 3 "CUTOVER=ABORT_VERSION_REGRESSION" WS_MODE=upgrade
  assert_untouched "C2"
  stop_fixture
else no "C2 fixture 起不来" ""; fi

# C3 升级路径塞旧版单面 → 必须拒绝
setup_cut "$DUAL" "$LEGACY"; mark
if start_fixture MODE=legacy; then
  run_cut "C3 旧版冒充升级" 3 "CUTOVER=ABORT_LEGACY_AS_UPGRADE" WS_MODE=upgrade
  assert_untouched "C3"
  stop_fixture
else no "C3 fixture 起不来" ""; fi

# C4 批准点不在发布线上（从旧版分叉）→ 必须拒绝
setup_cut "$LEGACY" "$SIDE"; mark
if start_fixture MODE=dual PID=4242; then
  run_cut "C4 越线候选" 3 "CUTOVER=ABORT_NOT_IN_RELEASE_LINE" WS_MODE=upgrade
  assert_untouched "C4"
  stop_fixture
else no "C4 fixture 起不来" ""; fi

# C5 批准点身份未知（发布树在、git 里没有）→ 必须拒绝
setup_cut "$DUAL" "$DUAL"
rm -rf "$ROOT/releases/$UNKNOWN"; cp -a "$ROOT/releases/$DUAL" "$ROOT/releases/$UNKNOWN"
approve "$UNKNOWN"; mark
if start_fixture MODE=dual PID=4242; then
  run_cut "C5 未知身份" 3 "CUTOVER=ABORT_TARGET_IDENTITY_UNKNOWN" WS_MODE=upgrade
  assert_untouched "C5"
  stop_fixture
else no "C5 fixture 起不来" ""; fi

# C6 发布树被改过（身份对但内容不对）→ 必须拒绝
setup_cut "$DUAL" "$FACADE"
printf 'tampered\n' >> "$ROOT/releases/$FACADE/server/world.mjs"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade; then
  run_cut "C6 发布树漂移" 3 "CUTOVER=ABORT_RELEASE_TREE_MISMATCH" WS_MODE=upgrade
  assert_untouched "C6"
  stop_fixture
else no "C6 fixture 起不来" ""; fi

# C7 回滚缺第二把钥匙 → 必须拒绝
setup_cut "$DUAL" "$LEGACY"; mark
if start_fixture MODE=legacy; then
  run_cut "C7 回滚缺钥匙" 3 "CUTOVER=ABORT_ROLLBACK_TARGET_REQUIRED" WS_MODE=rollback
  assert_untouched "C7"
  stop_fixture
else no "C7 fixture 起不来" ""; fi

# C8 回滚目标在前方（借回滚路径往前跳）→ 必须拒绝
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade; then
  run_cut "C8 伪回滚" 3 "CUTOVER=ABORT_ROLLBACK_NOT_ANCESTOR" WS_MODE=rollback WS_ROLLBACK_TO="$FACADE"
  assert_untouched "C8"
  stop_fixture
else no "C8 fixture 起不来" ""; fi

# C9 显式回滚：两把钥匙齐全、目标是祖先 → 成功，留档 mode=rollback
setup_cut "$FACADE" "$DUAL"; mark
if start_fixture MODE=dual PID=4242; then
  run_cut "C9 合法回滚" 0 "CUTOVER=OK" WS_MODE=rollback WS_ROLLBACK_TO="$DUAL"
  eq "C9 current 已回滚" "$DUAL" "$(current_now)"
  eq "C9 留档 mode" "mode=rollback" "$(grep -h '^mode=' "$(ls -1t "$ROOT/state"/cutover-*.txt | head -1)")"
  eq "C9 留下回滚目标" "rollback_to=$DUAL" "$(grep -h '^rollback_to=' "$(ls -1t "$ROOT/state"/cutover-*.txt | head -1)")"
  eq "C9 关站次数" "0" "$(close_count)"
  stop_fixture
else no "C9 fixture 起不来" ""; fi

# C10 批准点就是当前线上版本 → 拒绝（空操作不算成功）
setup_cut "$DUAL" "$DUAL"; mark
if start_fixture MODE=dual PID=4242; then
  run_cut "C10 已在线" 3 "CUTOVER=ABORT_ALREADY_LIVE" WS_MODE=upgrade
  assert_untouched "C10"
  stop_fixture
else no "C10 fixture 起不来" ""; fi

# C11 面形状显式预期不符 → 拒绝（不需要起服务）
setup_cut "$DUAL" "$FACADE"; mark
run_cut "C11 面形状不符" 3 "CUTOVER=ABORT_FACE_MISMATCH" WS_MODE=upgrade WS_EXPECT_FACE=legacy_single_face
assert_untouched "C11"

# C12 发布树被塞符号链接（逐文件校验看不见，运行时会顺着它读树外文件）→ 拒绝
if can_symlink; then
  setup_cut "$DUAL" "$FACADE"
  ln -s /etc/passwd "$ROOT/releases/$FACADE/leak.txt"; mark
  run_cut "C12 发布树符号链接" 3 "CUTOVER=ABORT_RELEASE_TREE_SYMLINK" WS_MODE=upgrade
  assert_untouched "C12"
else skip "C12 符号链接" "本平台建不了符号链接"; fi

# C13 重启命令失败 → 不得报成功；current 退回旧版本、不关站、无留档
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade; then
  run_cut "C13 重启失败" 1 "CUTOVER=FAILED_RESTART_SCENE_PRESERVED" WS_MODE=upgrade WS_RESTART_CMD=false
  assert_untouched "C13"
  stop_fixture
else no "C13 fixture 起不来" ""; fi

# C14 没有 current（升级）→ 拒绝：无法判断前进方向
setup_cut none "$FACADE"; mark
run_cut "C14 无 current" 3 "CUTOVER=ABORT_LIVE_IDENTITY_UNKNOWN" WS_MODE=upgrade
assert_untouched "C14"

# C15 current 是真目录而不是符号链接 → 拒绝（否则 ln 会往目录里建链接）
setup_cut none "$FACADE"; mkdir -p "$ROOT/current"; mark
run_cut "C15 current 非链接" 3 "CUTOVER=ABORT_LIVE_IDENTITY_UNKNOWN" WS_MODE=upgrade
assert_untouched "C15"

echo
printf '发布工具自测合计 %s 项，失败 %s 项，跳过 %s 项\n' "$TOTAL" "$FAILED" "$SKIPPED"
[ "$SKIPPED" = "0" ] || echo "注意：有 $SKIPPED 项被跳过——跳过 ≠ 通过"
[ "$FAILED" = "0" ] || exit 1
[ "$SKIPPED" = "0" ] || exit 3
echo "RELEASE_TOOLING_SELFTEST=PASS"
