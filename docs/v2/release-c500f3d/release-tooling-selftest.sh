#!/usr/bin/env bash
# release-tooling-selftest.sh —— 发布工具（cutover.sh / ws-prep.sh）的身份与路径自测
#
# 契约（2026-11-01 R3 收紧）：
#   候选必须显式（WS_REF 40 位）→ 必须能在 git 缓存里解析成同一个提交 → 必须属于发布线
#   （refs/heads/v2 写死，环境变量不能换线，replace refs / info/grafts 不能伪造祖先）
#   → 必须是当前线上版本的后代 → legacy 单面只允许走回滚路径 → 目标代码必须自带发布身份测量。
#   回滚必须两把钥匙（WS_MODE=rollback + WS_ROLLBACK_TO），且目标必须是当前线上版本的祖先，
#   且同样要能被运行时核实（没有身份物证的旧版不给登记）。
#
#   切流侧的闭环：CUTOVER=OK 只在"批准的字节确实在服务"时出现——公网面可达、诊断面在、
#   诊断面自报的 release_id 等于批准树实算值、自报启动时间晚于本次切流、pid 等于重启后的
#   MainPID。以下六种情形只有 A 允许 OK：
#     A 正常重启   B 重启命令成功但没重启   C 重启命令失败
#     D 旧进程带着"新 SHA"的环境变量        E 端口被别的进程占着   F 新进程起来了但身份不符
#
# 每个场景都检查：退出码 / current / approved-sha / 批准记录 / 发布树 / 留档 / 关站记录 /
# 是否有部分写入。只碰 $T 下的沙箱（可用 TOOLING_TEST_ROOT / TOOLING_TEST_ORIGIN 指向固定路径）。
#
# 用法：bash release-tooling-selftest.sh     （退出码 0 = 全部通过；3 = 有跳过）
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREP="${WS_PREP:-$HERE/ws-prep.sh}"
CUT="${WS_CUTOVER:-$HERE/cutover.sh}"
VERIFY="${WS_VERIFY:-$HERE/ws-verify-faces.sh}"
FIXTURE="${WS_FIXTURE:-$HERE/ops-fixture-face.mjs}"
IDENTITY_TOOL="${WS_IDENTITY_TOOL:-$HERE/release-id.mjs}"
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
has()  { if grep -q "$2" <<<"$3"; then ok "$1" "含 /$2/"; else no "$1" "缺 /$2/（输出：$(printf '%s' "$3" | tr '\n' ' ' | head -c 200)）"; fi; }
hasnt(){ if grep -q "$2" <<<"$3"; then no "$1" "不应出现 /$2/"; else ok "$1" "无 /$2/"; fi; }

cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; [ -f "$T/fx.pid" ] && kill "$(cat "$T/fx.pid")" 2>/dev/null; chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"; }
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

# ── 假面：真实进程、真实 pid、可重启、可按发布树算身份 ──
start_fixture() { # start_fixture [VAR=val ...]
  local log="$T/fx.log"; : > "$log"
  env PUB_PORT="$PUB" OPS_PORT="$OPS" "$@" node "$FIXTURE" > "$log" 2>&1 &
  local pid=$!; PIDS="$PIDS $pid"; printf '%s' "$pid" > "$T/fx.pid"
  local i=0
  while [ $i -lt 100 ]; do
    if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PUB/healthz"; then return 0; fi
    if grep -q FIXTURE_FAIL "$log" 2>/dev/null; then return 1; fi
    sleep 0.1; i=$((i+1))
  done
  return 1
}
stop_fixture() {
  for p in $PIDS; do kill "$p" 2>/dev/null; done
  [ -f "$T/fx.pid" ] && kill "$(cat "$T/fx.pid")" 2>/dev/null
  PIDS=""; rm -f "$T/fx.pid"; sleep 0.3
}

# 真正的"重启"：杀掉旧进程、起一个新进程（新 pid、新启动时间）。用于 A / F。
write_restart_script() { # write_restart_script [VAR=val ...]
  { echo '#!/usr/bin/env bash'
    echo 'set -u'
    echo "kill \"\$(cat '$T/fx.pid')\" 2>/dev/null || true"
    echo 'sleep 0.4'
    printf 'env PUB_PORT=%s OPS_PORT=%s' "$PUB" "$OPS"
    local a; for a in "$@"; do printf ' %q' "$a"; done
    printf ' node %q >> %q 2>&1 &\n' "$FIXTURE" "$T/fx.log"
    printf "echo \$! > '%s/fx.pid'\n" "$T"
    printf 'for i in $(seq 1 100); do curl -s -o /dev/null --max-time 1 "http://127.0.0.1:%s/healthz" && exit 0; sleep 0.1; done\n' "$PUB"
    echo 'exit 1'
  } > "$T/restart.sh"
  chmod +x "$T/restart.sh"
}

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

# 合成世界的三种代码形状（面形状/身份能力由 face-probe.mjs 读代码判定）：
#   DUAL  = 双面 + 身份；LEGACY = 单面旧版；NID = 双面但没有身份测量
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
NID_SRC=$(cat <<'JS'
const http = require('node:http');
const WS_OPS_PORT = Number(process.env.WS_OPS_PORT || 3201);
function handler(req, res) { res.end('{"ok":true}'); }
http.createServer(handler).listen(3200);
http.createServer(handler).listen(WS_OPS_PORT);
JS
)
LEGACY_SRC='const CFG = { webDir: 1 };'
FORGED_SRC=$(cat <<'JS'
const RELEASE_ID_SCHEME = 'world-release-tree-v1';
function computeReleaseId() { return 'forged'; }
// WS_OPS_PORT 3201 createServer(...).listen(...)  ← 只写在注释里，不是能力
const NOTE = 'WS_OPS_PORT createServer listen';
JS
)

rm -rf "$ORIGIN"; git init --bare -q "$ORIGIN"
LEGACY=$(mkcommit - "$LEGACY_SRC")
DUAL=$(mkcommit "$LEGACY" "$DUAL_SRC")
FACADE=$(mkcommit "$DUAL" "$DUAL_SRC" "$T/facade.html")
SIDE=$(mkcommit "$LEGACY" "$DUAL_SRC
const FORK = 1;")                                             # 与发布线分叉（内容必须与 DUAL 不同）
BADFACADE=$(mkcommit "$DUAL" "$DUAL_SRC" "$T/tiny.html")
NID=$(mkcommit "$DUAL" "$NID_SRC")                              # 双面但无身份
FORGED=$(mkcommit "$NID" "$FORGED_SRC")                         # 注释里写着 opsPort
UNKNOWN=0123456789abcdef0123456789abcdef01234567
git_ update-ref refs/heads/v2 "$DUAL"
git_ update-ref refs/heads/legacy "$LEGACY"
git_ update-ref refs/heads/facade "$FACADE"
git_ update-ref refs/heads/side "$SIDE"
# 这三条是"反面样本"提交：生产缓存按分支取对象，挂在 refs 上才能像真实候选一样被取回来。
git_ update-ref refs/heads/nid "$NID"
git_ update-ref refs/heads/forged "$FORGED"
git_ update-ref refs/heads/badfacade "$BADFACADE"
printf '沙箱提交：LEGACY=%.10s DUAL=%.10s FACADE=%.10s SIDE=%.10s NID=%.10s FORGED=%.10s\n' \
  "$LEGACY" "$DUAL" "$FACADE" "$SIDE" "$NID" "$FORGED"

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
live_at() { mkrelease "$1"; set_current "$1"; }   # 线上版本必须真的有一棵可读的发布树
release_id_of() { node "$IDENTITY_TOOL" "$ROOT/releases/$1" 2>/dev/null || true; }
approve() { # approve <sha> [mode] [rollback_to]
  local sha=$1 mode=${2:-upgrade} rb=${3:--} rid=""
  printf '%s\n' "$sha" > "$ROOT/state/approved-sha"
  [ -d "$ROOT/releases/$sha" ] && rid=$(release_id_of "$sha")
  { echo "sha=$sha"; echo "mode=$mode"; echo "release_line=v2"
    echo "rollback_to=$rb"; echo "release_id=$rid"; } > "$ROOT/state/approved-meta.txt"
}
approved_now() { cat "$ROOT/state/approved-sha" 2>/dev/null || echo -; }
meta_now() { sha256sum "$ROOT/state/approved-meta.txt" 2>/dev/null | cut -c1-12 || echo -; }
current_now() { local t; t=$(readlink "$ROOT/current" 2>/dev/null || true); [ -n "$t" ] && basename "$t" || echo -; }
release_list() { ls -1 "$ROOT/releases" 2>/dev/null | sort | tr '\n' ',' || true; }
receipt_count() { ls -1 "$ROOT/state"/cutover-*.txt 2>/dev/null | wc -l; }
close_count() { grep -c '^close$' "$T/emerg.log" 2>/dev/null || true; }
last_receipt() { ls -1t "$ROOT/state"/cutover-*.txt 2>/dev/null | head -1; }

BEFORE_CUR=""; BEFORE_APP=""; BEFORE_REL=""; BEFORE_REC=""; BEFORE_META=""
mark() { BEFORE_CUR=$(current_now); BEFORE_APP=$(approved_now); BEFORE_REL=$(release_list); BEFORE_REC=$(receipt_count); BEFORE_META=$(meta_now); }
assert_untouched() { # assert_untouched <label>
  eq "$1 current 未变"    "$BEFORE_CUR" "$(current_now)"
  eq "$1 approved-sha 未变" "$BEFORE_APP" "$(approved_now)"
  eq "$1 批准记录未变"    "$BEFORE_META" "$(meta_now)"
  eq "$1 发布树未增"      "$BEFORE_REL" "$(release_list)"
  eq "$1 无新留档"        "$BEFORE_REC" "$(receipt_count)"
  eq "$1 未关站"          "0" "$(close_count)"
}

prep_run() { # prep_run <fetch|verify> [VAR=val ...]
  local sub=$1; shift
  env WS_ROOT="$ROOT" WS_REPO="$ORIGIN_URL" WS_BRANCH=v2 "$@" bash "$PREP" "$sub" 2>&1
}
prep_env() { # prep_env <sub>：不走 prep_run 的环境，供特殊参数用例自己给全
  local sub=$1; shift
  env WS_ROOT="$ROOT" WS_REPO="$ORIGIN_URL" "$@" bash "$PREP" "$sub" 2>&1
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
echo "=== P. ws-prep.sh：没有显式候选就不写批准点；身份/路径/发布线逐条把关 ==="
if [ "$(id -u)" != "0" ]; then
  skip "P 全部" "ws-prep.sh 要求 root（服务器上用 root 跑自测）"
else
# P1 未给 WS_REF → 零写入、明确报错
reset_root; mark
OUT=$(prep_run fetch); code=$?
eq "P1 无候选退出码" "2" "$code"
has "P1 点名缺候选" "PREDEPLOY_ABORT_TARGET_REQUIRED" "$OUT"
assert_untouched "P1"
eq "P1 未创建 git 缓存" "no" "$([ -e "$ROOT/.git-cache" ] && echo yes || echo no)"
eq "P1 未创建日志目录" "no" "$([ -d "$ROOT/state/logs" ] && echo yes || echo no)"

# P2 显式指定旧版（升级路径）→ 必须拒绝，且不写批准点
reset_root; live_at "$DUAL"; mark
OUT=$(prep_run fetch WS_REF="$LEGACY"); code=$?
eq "P2 旧版作为升级目标" "2" "$code"
has "P2 拒绝 legacy 升级" "PREDEPLOY_ABORT_LEGACY_AS_UPGRADE" "$OUT"
assert_untouched "P2"

# P3 版本回退（当前线上比候选新）→ 必须拒绝
reset_root; live_at "$FACADE"; mark
OUT=$(prep_run fetch WS_REF="$DUAL"); code=$?
eq "P3 回退候选退出码" "2" "$code"
has "P3 拒绝版本回退" "PREDEPLOY_ABORT_VERSION_REGRESSION" "$OUT"
assert_untouched "P3"

# P4 未知提交号 → 必须拒绝（不得把"取不回来"当成"就它了"）
reset_root; live_at "$DUAL"; mark
OUT=$(prep_run fetch WS_REF="$UNKNOWN"); code=$?
eq "P4 未知提交退出码" "2" "$code"
has "P4 点名身份未知" "PREDEPLOY_ABORT_\(TARGET_IDENTITY_UNKNOWN\|FETCH_FAILED\)" "$OUT"
assert_untouched "P4"

# P5 不在发布线上（从旧版分叉的候选）→ 必须拒绝
reset_root; live_at "$LEGACY"; mark
OUT=$(prep_run fetch WS_REF="$SIDE"); code=$?
eq "P5 分叉候选退出码" "2" "$code"
has "P5 拒绝越线候选" "PREDEPLOY_ABORT_NOT_IN_RELEASE_LINE" "$OUT"
assert_untouched "P5"

# P6 正常新版本：fetch + verify 成功，批准点 = 候选，current 一动不动，批准记录对得上
reset_root; live_at "$DUAL"; mark
OUT=$(prep_run fetch WS_REF="$FACADE"); code=$?
eq "P6 正常候选 fetch" "0" "$code"
OUT=$(prep_run verify WS_REF="$FACADE"); code=$?
eq "P6 正常候选 verify" "0" "$code"
has "P6 登记批准点" "GIT=PASS" "$OUT"
eq "P6 approved-sha" "$FACADE" "$(approved_now)"
eq "P6 current 未变" "$DUAL" "$(current_now)"
eq "P6 发布树就位" "yes" "$([ -f "$ROOT/releases/$FACADE/server/world.mjs" ] && echo yes || echo no)"
eq "P6 记录发布线" "release_line=v2" "$(grep -h '^release_line=' "$ROOT/state/approved-meta.txt")"
eq "P6 记录模式" "mode=upgrade" "$(grep -h '^mode=' "$ROOT/state/approved-meta.txt")"
eq "P6 记录身份=实算" "release_id=$(release_id_of "$FACADE")" "$(grep -h '^release_id=' "$ROOT/state/approved-meta.txt")"

# P7 发布树被改过一个字节 → verify 必须拒绝且不写批准点（验证先于批准）
reset_root; live_at "$DUAL"; mark
prep_run fetch WS_REF="$FACADE" >/dev/null 2>&1
printf 'tampered\n' >> "$ROOT/releases/$FACADE/server/world.mjs"
mark
OUT=$(prep_run verify WS_REF="$FACADE"); code=$?
eq "P7 内容漂移退出码" "2" "$code"
has "P7 点名内容不一致" "PREDEPLOY_ABORT_GIT_DRIFT" "$OUT"
eq "P7 approved-sha 未写" "-" "$(approved_now)"
eq "P7 批准记录未写" "no" "$([ -e "$ROOT/state/approved-meta.txt" ] && echo yes || echo no)"
eq "P7 current 未变" "$DUAL" "$(current_now)"

# P8 显式回滚：两把钥匙齐全 → 允许登记旧版（两个版本都有身份能力），current 仍不动
reset_root; live_at "$FACADE"; mark
OUT=$(prep_run fetch WS_MODE=rollback WS_ROLLBACK_TO="$DUAL" WS_REF="$DUAL"); code=$?
eq "P8 回滚 fetch" "0" "$code"
OUT=$(prep_run verify WS_MODE=rollback WS_ROLLBACK_TO="$DUAL" WS_REF="$DUAL"); code=$?
eq "P8 回滚 verify" "0" "$code"
eq "P8 approved-sha" "$DUAL" "$(approved_now)"
eq "P8 current 未变" "$FACADE" "$(current_now)"
eq "P8 记录回滚目标" "rollback_to=$DUAL" "$(grep -h '^rollback_to=' "$ROOT/state/approved-meta.txt")"

# P9 回滚缺第二把钥匙 → 拒绝
reset_root; live_at "$FACADE"; mark
OUT=$(prep_run fetch WS_MODE=rollback WS_REF="$DUAL"); code=$?
eq "P9 缺 ROLLBACK_TO 退出码" "2" "$code"
has "P9 点名缺第二把钥匙" "PREDEPLOY_ABORT_ROLLBACK_TARGET_REQUIRED" "$OUT"
assert_untouched "P9"

# P10 回滚目标不是祖先（想借回滚路径往前跳）→ 拒绝
reset_root; live_at "$DUAL"; mark
OUT=$(prep_run fetch WS_MODE=rollback WS_ROLLBACK_TO="$FACADE" WS_REF="$FACADE"); code=$?
eq "P10 伪回滚退出码" "2" "$code"
has "P10 拒绝非祖先" "PREDEPLOY_ABORT_ROLLBACK_NOT_ANCESTOR" "$OUT"
assert_untouched "P10"

# P11 发布树里被塞进符号链接 → verify 必须拒绝且不写批准点（find -type f 看不见链接）
if can_symlink; then
  reset_root; live_at "$DUAL"
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

# P13 残留 WS_BRANCH 想换发布线 → 必须拒绝（P7 的"静默换线"）
reset_root; live_at "$DUAL"; mark
OUT=$(prep_env fetch WS_BRANCH=alt WS_REF="$FACADE"); code=$?
eq "P13 换线退出码" "2" "$code"
has "P13 点名换线" "PREDEPLOY_ABORT_RELEASE_LINE_OVERRIDE" "$OUT"
assert_untouched "P13"

# P14 releases 被换成符号链接 → 拒绝（否则整棵"发布树"可以是任意目录）
if can_symlink; then
  reset_root; live_at "$DUAL"
  mv "$ROOT/releases" "$T/rel-outside"; ln -s "$T/rel-outside" "$ROOT/releases"
  mark
  OUT=$(prep_run fetch WS_REF="$FACADE"); code=$?
  eq "P14 releases 链接退出码" "2" "$code"
  has "P14 点名 releases 不是目录" "PREDEPLOY_ABORT_RELEASES_NOT_DIRECTORY" "$OUT"
  rm -f "$ROOT/releases"; mv "$T/rel-outside" "$ROOT/releases"
  assert_untouched "P14"
else skip "P14 releases 符号链接" "本平台建不了符号链接"; fi

# P15 git 缓存里的 replace refs 能伪造祖先 → 必须拒绝
reset_root; live_at "$DUAL"; mkdir -p "$ROOT/.git-cache"
git init --bare -q "$ROOT/.git-cache/World-Space.git"
git -C "$ROOT/.git-cache/World-Space.git" remote add origin "$ORIGIN_URL"
git -C "$ROOT/.git-cache/World-Space.git" fetch -q --force origin '+refs/heads/*:refs/heads/*'
git -C "$ROOT/.git-cache/World-Space.git" update-ref "refs/replace/$LEGACY" "$DUAL"
mark
OUT=$(prep_run fetch WS_REF="$FACADE"); code=$?
eq "P15 replace refs 退出码" "2" "$code"
has "P15 点名元数据被改" "PREDEPLOY_ABORT_GIT_METADATA_TAMPERED" "$OUT"
assert_untouched "P15"

# P16 git 缓存里的 info/grafts 能伪造祖先 → 必须拒绝
reset_root; live_at "$DUAL"; mkdir -p "$ROOT/.git-cache"
git init --bare -q "$ROOT/.git-cache/World-Space.git"
git -C "$ROOT/.git-cache/World-Space.git" remote add origin "$ORIGIN_URL"
git -C "$ROOT/.git-cache/World-Space.git" fetch -q --force origin '+refs/heads/*:refs/heads/*'
mkdir -p "$ROOT/.git-cache/World-Space.git/info"
printf '%s %s\n' "$LEGACY" "$DUAL" > "$ROOT/.git-cache/World-Space.git/info/grafts"
mark
OUT=$(prep_run fetch WS_REF="$FACADE"); code=$?
eq "P16 grafts 退出码" "2" "$code"
has "P16 点名元数据被改" "PREDEPLOY_ABORT_GIT_METADATA_TAMPERED" "$OUT"
assert_untouched "P16"

# P17 注释里写着 opsPort 的"伪双面" → 必须按代码判成单面并拒绝（P8）
reset_root; live_at "$NID"
OUT=$(prep_run fetch WS_REF="$FORGED"); code=$?
eq "P17 注释伪造退出码" "2" "$code"
has "P17 按代码判为单面" "PREDEPLOY_ABORT_LEGACY_AS_UPGRADE" "$OUT"
eq "P17 approved-sha 未写" "-" "$(approved_now)"

# P18 目标没有发布身份测量 → 拒绝：登记了也永远拿不到 OK（P0 闭环）
reset_root; live_at "$DUAL"
OUT=$(prep_run fetch WS_REF="$NID"); code=$?
eq "P18 无身份退出码" "2" "$code"
has "P18 点名无身份能力" "PREDEPLOY_ABORT_IDENTITY_UNSUPPORTED_BY_TARGET" "$OUT"
eq "P18 approved-sha 未写" "-" "$(approved_now)"

# P19 current 指向 ROOT 之外、basename 却看起来合法 → 拒绝（P3）
if can_symlink; then
  reset_root
  mkdir -p "$T/outside/$DUAL"
  ln -sfn "$T/outside/$DUAL" "$ROOT/current"
  mark
  OUT=$(prep_run fetch WS_REF="$FACADE"); code=$?
  eq "P19 current 越界退出码" "2" "$code"
  has "P19 拒绝越界 current" "PREDEPLOY_ABORT_LIVE_IDENTITY_UNKNOWN" "$OUT"
  assert_untouched "P19"
else skip "P19 current 越界" "本平台建不了符号链接"; fi

# P20 回滚到没有身份物证的旧版 → 拒绝（否则批准了一个永远无法核实的版本）
reset_root; live_at "$DUAL"
OUT=$(prep_run fetch WS_MODE=rollback WS_ROLLBACK_TO="$LEGACY" WS_REF="$LEGACY"); code=$?
eq "P20 无身份回滚退出码" "2" "$code"
has "P20 点名无身份能力" "PREDEPLOY_ABORT_IDENTITY_UNSUPPORTED_BY_TARGET" "$OUT"
eq "P20 approved-sha 未写" "-" "$(approved_now)"
fi

# ─────────────────────── C. cutover.sh 的预检与切换 ───────────────────────
echo "=== C. cutover.sh：身份、发布线、前进方向、两把钥匙、路径与元数据 ==="
setup_cut() { # setup_cut <live_sha|none> <approved_sha> [mode] [rollback_to]
  reset_root
  mkdir -p "$ROOT/.git-cache"
  git clone -q --bare "$ORIGIN" "$ROOT/.git-cache/World-Space.git"
  mkrelease "$LEGACY"; mkrelease "$DUAL"; mkrelease "$FACADE"; mkrelease "$SIDE"
  mkrelease "$NID"; mkrelease "$FORGED"; mkrelease "$BADFACADE"
  [ "$1" = none ] || set_current "$1"
  approve "$2" "${3:-upgrade}" "${4:--}"
}

# C1 正常升级：真重启 + 身份闭环 → OK
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL" START_AT=$(( $(date +%s%3N) - 600000 )); then
  write_restart_script MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$FACADE"
  run_cut "C1 正常升级" 0 "CUTOVER=OK" WS_MODE=upgrade \
    WS_RESTART_CMD="$T/restart.sh" WS_PID_CMD="cat $T/fx.pid"
  eq "C1 current 已切换" "$FACADE" "$(current_now)"
  eq "C1 留档 mode" "mode=upgrade" "$(grep -h '^mode=' "$(last_receipt)")"
  eq "C1 留档身份=批准身份" "target_release_id=$(release_id_of "$FACADE")" "$(grep -h '^target_release_id=' "$(last_receipt)")"
  eq "C1 关站次数" "0" "$(close_count)"
  stop_fixture
else no "C1 fixture 起不来" ""; fi

# C2 当前线上比批准点新（静默降级）→ 必须拒绝且零写入
setup_cut "$FACADE" "$DUAL"; mark
if start_fixture MODE=dual PID=4242 RELEASE_ROOT="$ROOT/releases/$FACADE"; then
  run_cut "C2 静默降级" 3 "CUTOVER=ABORT_VERSION_REGRESSION" WS_MODE=upgrade
  assert_untouched "C2"
  stop_fixture
else no "C2 fixture 起不来" ""; fi

# C3 升级路径塞旧版单面 → 必须拒绝
setup_cut "$DUAL" "$LEGACY"; mark
if start_fixture MODE=legacy PID=4242 RELEASE_ROOT="$ROOT/releases/$DUAL"; then
  run_cut "C3 旧版冒充升级" 3 "CUTOVER=ABORT_LEGACY_AS_UPGRADE" WS_MODE=upgrade
  assert_untouched "C3"
  stop_fixture
else no "C3 fixture 起不来" ""; fi

# C4 批准点不在发布线上（从旧版分叉）→ 必须拒绝
setup_cut "$LEGACY" "$SIDE"; mark
if start_fixture MODE=dual PID=4242 RELEASE_ROOT="$ROOT/releases/$LEGACY"; then
  run_cut "C4 越线候选" 3 "CUTOVER=ABORT_NOT_IN_RELEASE_LINE" WS_MODE=upgrade
  assert_untouched "C4"
  stop_fixture
else no "C4 fixture 起不来" ""; fi

# C5 批准点身份未知（发布树在、git 里没有）→ 必须拒绝
setup_cut "$DUAL" "$DUAL"
rm -rf "$ROOT/releases/$UNKNOWN"; cp -a "$ROOT/releases/$DUAL" "$ROOT/releases/$UNKNOWN"
approve "$UNKNOWN"; mark
if start_fixture MODE=dual PID=4242 RELEASE_ROOT="$ROOT/releases/$DUAL"; then
  run_cut "C5 未知身份" 3 "CUTOVER=ABORT_TARGET_IDENTITY_UNKNOWN" WS_MODE=upgrade
  assert_untouched "C5"
  stop_fixture
else no "C5 fixture 起不来" ""; fi

# C6 发布树被改过（身份对但内容不对）→ 必须拒绝
setup_cut "$DUAL" "$FACADE"
printf 'tampered\n' >> "$ROOT/releases/$FACADE/server/world.mjs"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL"; then
  run_cut "C6 发布树漂移" 3 "CUTOVER=ABORT_RELEASE_TREE_MISMATCH" WS_MODE=upgrade
  assert_untouched "C6"
  stop_fixture
else no "C6 fixture 起不来" ""; fi

# C6b 门面物证不完整（<8000 字节或缺标志串）→ 必须拒绝
setup_cut "$DUAL" "$BADFACADE"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL"; then
  run_cut "C6b 门面不完整" 3 "CUTOVER=ABORT_FACADE_INVALID" WS_MODE=upgrade
  assert_untouched "C6b"
  stop_fixture
else no "C6b fixture 起不来" ""; fi

# C7 回滚缺第二把钥匙 → 必须拒绝（批准记录本身是一份合法的回滚批准）
setup_cut "$FACADE" "$DUAL" rollback "$DUAL"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$FACADE"; then
  run_cut "C7 回滚缺钥匙" 3 "CUTOVER=ABORT_ROLLBACK_TARGET_REQUIRED" WS_MODE=rollback
  assert_untouched "C7"
  stop_fixture
else no "C7 fixture 起不来" ""; fi

# C8 回滚目标在前方（借回滚路径往前跳）→ 必须拒绝
setup_cut "$DUAL" "$FACADE" rollback "$FACADE"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL"; then
  run_cut "C8 伪回滚" 3 "CUTOVER=ABORT_ROLLBACK_NOT_ANCESTOR" WS_MODE=rollback WS_ROLLBACK_TO="$FACADE"
  assert_untouched "C8"
  stop_fixture
else no "C8 fixture 起不来" ""; fi

# C9 显式回滚：两把钥匙齐全、目标是祖先、真重启、目标身份核实 → OK
setup_cut "$FACADE" "$DUAL" rollback "$DUAL"; mark
if start_fixture MODE=dual PID=auto ROOT=302 RELEASE_ROOT="$ROOT/releases/$FACADE" START_AT=$(( $(date +%s%3N) - 600000 )); then
  write_restart_script MODE=dual PID=auto ROOT=302 RELEASE_ROOT="$ROOT/releases/$DUAL"
  run_cut "C9 合法回滚" 0 "CUTOVER=OK" WS_MODE=rollback WS_ROLLBACK_TO="$DUAL" \
    WS_RESTART_CMD="$T/restart.sh" WS_PID_CMD="cat $T/fx.pid"
  eq "C9 current 已回滚" "$DUAL" "$(current_now)"
  eq "C9 留档 mode" "mode=rollback" "$(grep -h '^mode=' "$(last_receipt)")"
  eq "C9 留下回滚目标" "rollback_to=$DUAL" "$(grep -h '^rollback_to=' "$(last_receipt)")"
  eq "C9 关站次数" "0" "$(close_count)"
  stop_fixture
else no "C9 fixture 起不来" ""; fi

# C10 批准点就是当前线上版本 → 拒绝（空操作不算成功）
setup_cut "$DUAL" "$DUAL"; mark
if start_fixture MODE=dual PID=4242 RELEASE_ROOT="$ROOT/releases/$DUAL"; then
  run_cut "C10 已在线" 3 "CUTOVER=ABORT_ALREADY_LIVE" WS_MODE=upgrade
  assert_untouched "C10"
  stop_fixture
else no "C10 fixture 起不来" ""; fi

# C11 面形状显式预期不符 → 拒绝（不需要起服务）
setup_cut "$DUAL" "$FACADE"; mark
run_cut "C11 面形状不符" 3 "CUTOVER=ABORT_FACE_MISMATCH" WS_MODE=upgrade WS_EXPECT_FACE=legacy_single_face
assert_untouched "C11"

# C12 发布树被塞符号链接 → 拒绝
if can_symlink; then
  setup_cut "$DUAL" "$FACADE"
  ln -s /etc/passwd "$ROOT/releases/$FACADE/leak.txt"; mark
  run_cut "C12 发布树符号链接" 3 "CUTOVER=ABORT_RELEASE_TREE_SYMLINK" WS_MODE=upgrade
  assert_untouched "C12"
else skip "C12 符号链接" "本平台建不了符号链接"; fi

# C13 重启命令失败 → 不得报成功；current 退回旧版本、不关站、留真实恢复结论
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=4242 ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL"; then
  run_cut "C13 重启失败" 1 "CUTOVER=FAILED_RESTART_SCENE_PRESERVED" WS_MODE=upgrade WS_RESTART_CMD=false
  eq "C13 current 已退回旧版" "$DUAL" "$(current_now)"
  eq "C13 留档恢复核实" "restore_verified=yes" "$(grep -h '^restore_verified=' "$(last_receipt)")"
  eq "C13 关站次数" "0" "$(close_count)"
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

# C16 核验器被换成另一个文件 → 拒绝（旧判据不能冒充被接受的版本，P9）
setup_cut "$DUAL" "$FACADE"
cp "$VERIFY" "$T/verify-alternate.sh"; printf '\n# drift\n' >> "$T/verify-alternate.sh"; mark
run_cut "C16 核验器哈希不符" 3 "CUTOVER=ABORT_VERIFIER_IDENTITY_MISMATCH" WS_MODE=upgrade \
  WS_VERIFY="$T/verify-alternate.sh"
assert_untouched "C16"

# C17 没有核验器期望哈希 → 拒绝（生产哈希 UNKNOWN 时不得默认"就是新版"）
setup_cut "$DUAL" "$FACADE"; mark
run_cut "C17 无核验器哈希" 3 "CUTOVER=ABORT_VERIFIER_IDENTITY_UNKNOWN" WS_MODE=upgrade \
  WS_VERIFY_SHA_FILE="$T/no-such.sha256" WS_VERIFY_SHA256=
assert_untouched "C17"

# C18 残留 WS_RELEASE_LINE 想换发布线 → 拒绝（P7）
setup_cut "$DUAL" "$FACADE"; mark
run_cut "C18 换发布线" 3 "CUTOVER=ABORT_RELEASE_LINE_OVERRIDE" WS_MODE=upgrade WS_RELEASE_LINE=alt
assert_untouched "C18"

# C19/C20 WS_POLL_TRIES 非法 → 用法错误；不能"一次都不探测就判不可用"（P6）
setup_cut "$DUAL" "$FACADE"; mark
run_cut "C19 POLL_TRIES=0" 3 "CUTOVER=ABORT_USAGE_ERROR" WS_MODE=upgrade WS_POLL_TRIES=0
assert_untouched "C19"
mark
run_cut "C20 POLL_TRIES=abc" 3 "CUTOVER=ABORT_USAGE_ERROR" WS_MODE=upgrade WS_POLL_TRIES=abc
assert_untouched "C20"

# C21/C22 replace refs / info/grafts 伪造祖先 → 拒绝（P5）
setup_cut "$LEGACY" "$SIDE"; mark
git -C "$ROOT/.git-cache/World-Space.git" update-ref "refs/replace/$SIDE" "$DUAL"
run_cut "C21 replace refs" 3 "CUTOVER=ABORT_GIT_METADATA_TAMPERED" WS_MODE=upgrade
assert_untouched "C21"
setup_cut "$LEGACY" "$SIDE"; mark
mkdir -p "$ROOT/.git-cache/World-Space.git/info"
printf '%s %s\n' "$SIDE" "$DUAL" > "$ROOT/.git-cache/World-Space.git/info/grafts"
run_cut "C22 info/grafts" 3 "CUTOVER=ABORT_GIT_METADATA_TAMPERED" WS_MODE=upgrade
assert_untouched "C22"

# C23 releases 变成符号链接 → 拒绝（P4）
if can_symlink; then
  setup_cut "$DUAL" "$FACADE"
  mv "$ROOT/releases" "$T/rel-outside-c"; ln -s "$T/rel-outside-c" "$ROOT/releases"; mark
  run_cut "C23 releases 符号链接" 3 "CUTOVER=ABORT_RELEASES_NOT_DIRECTORY" WS_MODE=upgrade
  rm -f "$ROOT/releases"; mv "$T/rel-outside-c" "$ROOT/releases"
  assert_untouched "C23"
else skip "C23 releases 符号链接" "本平台建不了符号链接"; fi

# C24 发布树本身是符号链接 → 拒绝
if can_symlink; then
  setup_cut "$DUAL" "$FACADE"
  mv "$ROOT/releases/$FACADE" "$T/tree-outside"; ln -s "$T/tree-outside" "$ROOT/releases/$FACADE"; mark
  run_cut "C24 发布树符号链接" 3 "CUTOVER=ABORT_\(PATH_ESCAPE\|RELEASE_TREE_MISSING\)" WS_MODE=upgrade
  rm -f "$ROOT/releases/$FACADE"; mv "$T/tree-outside" "$ROOT/releases/$FACADE"
  assert_untouched "C24"
else skip "C24 发布树符号链接" "本平台建不了符号链接"; fi

# C25 current 指向 ROOT 之外、basename 却合法 → 拒绝（P3）
if can_symlink; then
  setup_cut none "$FACADE"
  mkdir -p "$T/outside/$DUAL"
  ln -sfn "$T/outside/$DUAL" "$ROOT/current"; mark
  run_cut "C25 current 越界" 3 "CUTOVER=ABORT_LIVE_IDENTITY_UNKNOWN" WS_MODE=upgrade
  assert_untouched "C25"
else skip "C25 current 越界" "本平台建不了符号链接"; fi

# C26/C27 批准记录缺失或与策略对不上 → 拒绝
setup_cut "$DUAL" "$FACADE"; rm -f "$ROOT/state/approved-meta.txt"; mark
run_cut "C26 批准记录缺失" 3 "CUTOVER=ABORT_APPROVAL_RECORD_MISSING" WS_MODE=upgrade
assert_untouched "C26"
setup_cut "$DUAL" "$FACADE"; approve "$FACADE" rollback "$DUAL"; mark
run_cut "C27 批准记录模式不符" 3 "CUTOVER=ABORT_APPROVAL_RECORD_MISMATCH" WS_MODE=upgrade
assert_untouched "C27"

# C28 目标没有身份测量 → 拒绝（P0：无法证明在服务的是它）
setup_cut "$DUAL" "$NID"; mark
run_cut "C28 目标无身份" 3 "CUTOVER=ABORT_IDENTITY_UNSUPPORTED_BY_TARGET" WS_MODE=upgrade
assert_untouched "C28"

# C29 注释里写着 opsPort 的伪双面 → 按代码判为单面并拒绝（P8）
setup_cut "$NID" "$FORGED"; mark
run_cut "C29 注释伪造面形状" 3 "CUTOVER=ABORT_LEGACY_AS_UPGRADE" WS_MODE=upgrade
assert_untouched "C29"

# C30 回滚到没有身份物证的旧版 → 拒绝（P0/P2 的交点）
setup_cut "$DUAL" "$LEGACY" rollback "$LEGACY"; mark
run_cut "C30 无身份回滚" 3 "CUTOVER=ABORT_IDENTITY_UNSUPPORTED_BY_TARGET" WS_MODE=rollback WS_ROLLBACK_TO="$LEGACY"
assert_untouched "C30"

# C31 恢复失败必须如实记录：旧树被删 + current 变目录 → 不得写"已退回"
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL" START_AT=$(( $(date +%s%3N) - 600000 )); then
  { echo '#!/usr/bin/env bash'
    echo "kill \"\$(cat '$T/fx.pid')\" 2>/dev/null || true"
    echo "rm -rf '$ROOT/releases/$DUAL'"
    echo "rm -f '$ROOT/current'; mkdir '$ROOT/current'"
    printf 'env PUB_PORT=%s OPS_PORT=%s MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT=%q node %q >> %q 2>&1 &\n' \
      "$PUB" "$OPS" "$ROOT/releases/$FACADE" "$FIXTURE" "$T/fx.log"
    printf "echo \$! > '%s/fx.pid'\n" "$T"
    echo 'exit 1'
  } > "$T/break-restore.sh"; chmod +x "$T/break-restore.sh"
  run_cut "C31 恢复失败" 1 "恢复核实=no" WS_MODE=upgrade \
    WS_RESTART_CMD="$T/break-restore.sh" WS_PID_CMD="cat $T/fx.pid"
  eq "C31 留档 restore_verified=no" "restore_verified=no" "$(grep -h '^restore_verified=' "$(last_receipt)")"
  has "C31 留档记录真实 current" "非符号链接" "$(grep -h '^current_after=' "$(last_receipt)")"
  stop_fixture
else no "C31 fixture 起不来" ""; fi

# C32 切换本身失败（current 不可写）→ FAILED_SWITCH，且不得把"没发生的恢复"说成已完成
if [ "$(id -u)" = 0 ] && [ -f "$T/fake-emerg.sh" ] && command -v su >/dev/null 2>&1 && id -u node >/dev/null 2>&1; then
  NROOT="$T/nr-root"
  rm -rf "$NROOT"; mkdir -p "$NROOT/releases" "$NROOT/state" "$NROOT/.git-cache" "$NROOT/etc"
  git clone -q --bare "$ORIGIN" "$NROOT/.git-cache/World-Space.git"
  for s in LEGACY DUAL FACADE; do eval "sha=\$$s"; mkdir -p "$NROOT/releases/$sha"
    git_ archive "$sha" | tar -x -C "$NROOT/releases/$sha"; done
  ln -sfn "$NROOT/releases/$DUAL" "$NROOT/current"
  printf '%s\n' "$FACADE" > "$NROOT/state/approved-sha"
  { echo "sha=$FACADE"; echo "mode=upgrade"; echo "release_line=v2"; echo "rollback_to=-"; } > "$NROOT/state/approved-meta.txt"
  chmod 777 "$NROOT/state"
  chmod -R a+rX "$NROOT/releases" "$NROOT/.git-cache"
  chmod 755 "$NROOT"
  chmod 711 "$T"
  cat > "$T/run-nr.sh" <<EOS
#!/usr/bin/env bash
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
export WS_ROOT="$NROOT"
export WS_EMERG="$T/fake-emerg.sh"
export WS_VERIFY="$VERIFY"
export WS_RESTART_CMD=true
export EMERG_LOG="$T/emerg.log"
export WS_PUBLIC_PORT="$PUB" WS_OPS_PORT="$OPS"
export WS_GATE_BASE="http://127.0.0.1:$PUB"
export WS_RESOLVE_HOST= WS_CURL_TIMEOUT=4 WS_POLL_TRIES=3
export WS_SS_CMD="$T/ss-missing"
exec bash "$CUT"
EOS
  chmod 755 "$T/run-nr.sh"
  NOUT=$(su -s /bin/bash node -c "bash '$T/run-nr.sh'" 2>&1); NCODE=$?
  eq "C32 切换失败退出码" "1" "$NCODE"
  has "C32 结论 FAILED_SWITCH" "CUTOVER=FAILED_SWITCH" "$NOUT"
  has "C32 如实记录 current 未变" "恢复核实=unchanged" "$NOUT"
  hasnt "C32 不把未发生的恢复说成已完成" "恢复核实=yes" "$NOUT"
  eq "C32 留档 restore_verified=unchanged" "restore_verified=unchanged" "$(grep -h '^restore_verified=' "$NROOT"/state/cutover-*.txt 2>/dev/null | tail -1)"
  eq "C32 current 未变" "$DUAL" "$(basename "$(readlink "$NROOT/current")")"
  rm -rf "$NROOT"
else skip "C32 切换失败（非 root 写面）" "需要 root 且存在可用的非 root 用户"; fi

# ─────────────────────── I. 运行身份闭环：只有 A 允许 OK ───────────────────────
echo "=== I. 运行身份闭环（A 正常重启 / B-E 都不得 OK）==="

# A 已由 C1 覆盖（真重启 + 身份一致 → OK）。

# B 重启命令成功但没重启：老进程、老启动时间 → 不得 OK
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL" START_AT=$(( $(date +%s%3N) - 600000 )); then
  run_cut "I-B 未重启" 1 "CUTOVER=FAILED_SCENE_PRESERVED" WS_MODE=upgrade \
    WS_RESTART_CMD=true WS_PID_CMD="cat $T/fx.pid"
  hasnt "I-B 不得报 OK" "CUTOVER=OK" "$LAST_OUT"
  eq "I-B 未关站" "0" "$(close_count)"
  stop_fixture
else no "I-B fixture 起不来" ""; fi

# C 重启命令失败 → 不得 OK（已在 C13 覆盖）；这里确认结论不含 OK
# D 老进程被塞了"新 SHA"的环境变量 → 身份不来自环境变量，仍不得 OK
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL" \
     START_AT=$(( $(date +%s%3N) - 600000 )) WS_RELEASE_ID="$(release_id_of "$FACADE")" WS_APPROVED_SHA="$FACADE"; then
  run_cut "I-D 环境变量冒充" 1 "CUTOVER=FAILED_SCENE_PRESERVED" WS_MODE=upgrade \
    WS_RESTART_CMD=true WS_PID_CMD="cat $T/fx.pid"
  hasnt "I-D 不得报 OK" "CUTOVER=OK" "$LAST_OUT"
  stop_fixture
else no "I-D fixture 起不来" ""; fi

# E 端口被别的进程占着：公网面有响应，但不是我们的服务 → 不得 OK，也不得关站
setup_cut "$DUAL" "$FACADE"; mark
mkdir -p "$T/foreign"; cp "$T/facade.html" "$T/foreign/index.html"
if start_fixture MODE=dual PID=9999 ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$T/foreign"; then
  run_cut "I-E 端口被他人占用" 1 "CUTOVER=FAILED_SCENE_PRESERVED" WS_MODE=upgrade \
    WS_RESTART_CMD=true WS_PID_CMD="echo 4242"
  hasnt "I-E 不得报 OK" "CUTOVER=OK" "$LAST_OUT"
  eq "I-E 未关站（不是它的错）" "0" "$(close_count)"
  stop_fixture
else no "I-E fixture 起不来" ""; fi

# F 新进程起来了、但运行身份 ≠ 批准身份 → 不得 OK
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL" START_AT=$(( $(date +%s%3N) - 600000 )); then
  write_restart_script MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$SIDE"
  run_cut "I-F 身份不符" 1 "CUTOVER=FAILED_SCENE_PRESERVED" WS_MODE=upgrade \
    WS_RESTART_CMD="$T/restart.sh" WS_PID_CMD="cat $T/fx.pid"
  hasnt "I-F 不得报 OK" "CUTOVER=OK" "$LAST_OUT"
  has "I-F 点名身份不一致" "release_id_matches_approved" "$LAST_OUT"
  stop_fixture
else no "I-F fixture 起不来" ""; fi

# G 诊断面缺身份字段（IDENTITY=missing）→ 不得 OK
setup_cut "$DUAL" "$FACADE"; mark
if start_fixture MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$DUAL" START_AT=$(( $(date +%s%3N) - 600000 )); then
  write_restart_script MODE=dual PID=auto ROOT=200 ROOT_MARK=facade RELEASE_ROOT="$ROOT/releases/$FACADE" IDENTITY=missing
  run_cut "I-G 身份字段缺失" 1 "CUTOVER=FAILED_SCENE_PRESERVED" WS_MODE=upgrade \
    WS_RESTART_CMD="$T/restart.sh" WS_PID_CMD="cat $T/fx.pid"
  hasnt "I-G 不得报 OK" "CUTOVER=OK" "$LAST_OUT"
  stop_fixture
else no "I-G fixture 起不来" ""; fi

# 真不可用（没有任何监听）→ 只有这一条允许关站
setup_cut "$DUAL" "$FACADE"; mark
run_cut "I-H 服务真不可用" 1 "CUTOVER=FAILED_AND_CLOSED" WS_MODE=upgrade \
  WS_PUBLIC_PORT=4899 WS_OPS_PORT=4898 WS_POLL_TRIES=2
eq "I-H 关站次数（应恰好 1）" "1" "$(close_count)"

echo
printf '发布工具自测合计 %s 项，失败 %s 项，跳过 %s 项\n' "$TOTAL" "$FAILED" "$SKIPPED"
[ "$SKIPPED" = "0" ] || echo "注意：有 $SKIPPED 项被跳过——跳过 ≠ 通过"
[ "$FAILED" = "0" ] || exit 1
[ "$SKIPPED" = "0" ] || exit 3
echo "RELEASE_TOOLING_SELFTEST=PASS"
