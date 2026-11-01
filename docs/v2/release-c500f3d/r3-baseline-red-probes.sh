#!/usr/bin/env bash
# r3-baseline-red-probes.sh —— R2-965 四条 blocker 的"旧版本确实错"证据装置。
#
# 同一套沙箱（真 git 提交 / 真发布树 / 原生 POSIX symlink / 真端口），分别喂给：
#   baseline = 9654540 的发布工具（RED 侧：断言旧行为确实错）
#   candidate = 候选的发布工具（GREEN 侧：同一构造不再放行）
#
# 覆盖：P0 假重启仍报 OK、P2 恢复失败仍称已退回、P3 current 越界、
#       P4 releases 根是链接、P5 info/grafts 伪造祖先、P6 WS_POLL_TRIES=0 关站、
#       P7 WS_RELEASE_LINE 换线、P8 注释伪造诊断面能力。
# 只碰 /tmp 沙箱；不写生产、不重启真实服务、不碰 nginx/DNS。
#
# 用法：
#   TOOL_BASELINE=<9654540 树>/docs/v2/release-c500f3d \
#   TOOL_CANDIDATE=<候选树>/docs/v2/release-c500f3d bash r3-baseline-red-probes.sh
# 退出码：0 = 所有预期都成立；非 0 = 有预期不成立（数字为不成立项数）
set -u
BASE_TOOL=${TOOL_BASELINE:-/base/docs/v2/release-c500f3d}
CAND_TOOL=${TOOL_CANDIDATE:-/cand/docs/v2/release-c500f3d}
PUB=${WS_PROBE_PUB:-3200}; OPS=${WS_PROBE_OPS:-3201}
SB=$(mktemp -d)
mkdir -p "$SB/bin"
FAILS=0; TOTAL=0
ck() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then printf '  PASS %-48s = %s\n' "$1" "$2"; else printf '  FAIL %-48s = %s (expect %s)\n' "$1" "$2" "$3"; FAILS=$((FAILS+1)); fi; }
has() { TOTAL=$((TOTAL+1)); if printf '%s' "$3" | grep -q "$2"; then printf '  PASS %-48s 含 /%s/\n' "$1" "$2"; else printf '  FAIL %-48s 缺 /%s/（输出：%s）\n' "$1" "$2" "$(printf '%s' "$3" | tr '\n' ' ' | head -c 160)"; FAILS=$((FAILS+1)); fi; }
hasnt() { TOTAL=$((TOTAL+1)); if printf '%s' "$3" | grep -q "$2"; then printf '  FAIL %-48s 不应出现 /%s/\n' "$1" "$2"; FAILS=$((FAILS+1)); else printf '  PASS %-48s 无 /%s/\n' "$1" "$2"; fi; }

cleanup() { [ -f "$SB/app.wrap" ] && while read -r w; do kill "$w" 2>/dev/null; done < "$SB/app.wrap"; chmod -R u+rwX "$SB" 2>/dev/null; rm -rf "$SB"; }
trap cleanup EXIT

for p in "$PUB" "$OPS"; do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$p/" 2>/dev/null; then
    printf 'FAIL 端口 %s 已被占用——换 WS_PROBE_PUB/WS_PROBE_OPS 再跑\n' "$p"; exit 6
  fi
done

# ── 假面：双面 + 门面物证（>=8000B）+ pid 自报 + 未登录行为，与核验器同口径 ──
cat > "$SB/fake-app.js" <<'JS'
const http = require('http');
const fs = require('fs');
const PUB = Number(process.argv[2] || 3200);
const OPS = Number(process.argv[3] || 0);
const PF = process.argv[4] || '';
const FAC = process.argv[5] || '';
const PID = process.pid;
if (PF) { try { fs.writeFileSync(PF, String(PID)); } catch (e) {} }
const facade = FAC && fs.existsSync(FAC) ? fs.readFileSync(FAC) : Buffer.alloc(0);
const send = (res, code, body, type) => { res.writeHead(code, { 'content-type': type || 'application/json' }); res.end(body); };
const pub = (req, res) => {
  const u = req.url.split('?')[0];
  if (u === '/healthz') return send(res, 200, JSON.stringify({ ok: true }));
  if (u === '/healthz/detail') return send(res, 404, 'not found', 'text/plain');
  if (u === '/' || u === '/index.html') return send(res, 200, facade, 'text/html; charset=utf-8');
  if (u === '/login') return send(res, 200, '<html><body>进入你的空间</body></html>', 'text/html; charset=utf-8');
  if (u === '/api/world' && req.method === 'POST') return send(res, 401, JSON.stringify({ error: 'unauthorized' }));
  if (u === '/api/auth/me') return send(res, 401, JSON.stringify({ error: 'unauthorized' }));
  if (u === '/api/auth/login' && req.method === 'POST') return send(res, 400, JSON.stringify({ error: 'bad request' }));
  return send(res, 404, 'not found', 'text/plain');
};
const ops = (req, res) => {
  const u = req.url.split('?')[0];
  if (u === '/healthz') return send(res, 200, JSON.stringify({
    auth: 'ready', provider: 'fixture', model: 'fixture-model', search: 'fixture-search',
    search_configured: true, today_calls: 0, daily_cap: 100, month_cost_rmb: 0,
    monthly_cap_rmb: 10, fail_closed: false, app_port: String(PUB), pid: String(PID),
  }));
  return send(res, 404, 'not found', 'text/plain');
};
http.createServer(pub).listen(PUB, '127.0.0.1', () => {
  if (OPS > 0) http.createServer(ops).listen(OPS, '127.0.0.1');
});
JS

# ── fixture 仓库：真提交、真分支、门面物证 ──
mkdir -p "$SB/work/src"
(
  cd "$SB/work/src"
  git init -q -b main .
  git config user.email probe@example.invalid; git config user.name probe; git config core.autocrlf false
  mkdir -p server web/v2/public
  { printf '<!doctype html><html><head><title>World Space</title></head><body><h1>你想做什么事</h1>\n'
    printf '<button id="btn-write">写点东西</button>\n'
    i=0; while [ $i -lt 500 ]; do printf '<p>padding %s</p>\n' "$i"; i=$((i+1)); done
    printf '</body></html>\n'; } > web/v2/public/index.html
  cat > server/world.mjs <<'EOF'
import http from 'node:http';
const opsPort = process.env.WS_OPS_PORT || 3201;
http.createServer((req, res) => { res.end('{"ok":true}'); }).listen(opsPort, '127.0.0.1');
export const iteration = 1;
EOF
  git add -A >/dev/null; git commit -qm "C1 dual-face 当前线上"
  printf '// iteration 2\n' >> server/world.mjs
  git add -A >/dev/null; git commit -qm "C2 v2 尖端"
  git branch -f v2 "$(git rev-parse HEAD)"
  git checkout -q -b alt HEAD~1
  printf '// alt line\n' >> server/world.mjs
  git add -A >/dev/null; git commit -qm "ALT 不在 v2 线"
  git checkout -q main
  git checkout -q --orphan evil; git rm -rq --cached . >/dev/null 2>&1
  printf 'const opsPort2 = 3201;\n' > server/world.mjs
  git add -A >/dev/null; git commit -qm "X 孤儿双面（不在发布线）"
  git checkout -q main
  printf '// opsPort handled elsewhere (NOT IMPLEMENTED)\nexport const nothing = 1;\n' > server/world.mjs
  git add -A >/dev/null; git commit -qm "K 仅注释里有 opsPort"; git branch -f v2b HEAD
)
SRC="$SB/work/src"
C1=$(git -C "$SRC" rev-parse main~2); C2=$(git -C "$SRC" rev-parse v2)
ALT=$(git -C "$SRC" rev-parse alt); X=$(git -C "$SRC" rev-parse evil); K=$(git -C "$SRC" rev-parse v2b)
git init -q --bare "$SB/work/cache.git" >/dev/null
git -C "$SRC" push -q "$SB/work/cache.git" main:main v2:v2 alt:alt evil:evil v2b:v2b 2>/dev/null
cp -r "$SB/work/cache.git" "$SB/work/cache.orig.git"
FACADE="$SRC/web/v2/public/index.html"
printf 'fixtures: C1=%s C2=%s ALT=%s X=%s K=%s\n' "$C1" "$C2" "$ALT" "$X" "$K"

export_tree() { mkdir -p "$1"; git -c core.autocrlf=false -c core.eol=lf -C "$SB/work/cache.git" archive "$2" | tar -x -C "$1"; }
new_root() { local r="$SB/roots/$1"; rm -rf "$r"; mkdir -p "$r/releases" "$r/state"; printf '%s' "$r"; }
restore_cache() { rm -rf "$SB/work/cache.git"; cp -r "$SB/work/cache.orig.git" "$SB/work/cache.git"; }
stub_emerg() { cat > "$1" <<'EOS'
#!/usr/bin/env bash
echo "EMERG_CALLED $*" >> "$(dirname "$0")/emerg.log"
exit 0
EOS
chmod +x "$1"; }
start_app() { local pf=$1; : > "$pf"; node "$SB/fake-app.js" "$PUB" "$OPS" "$pf" "$FACADE" > "$SB/app.log" 2>&1 & echo $! >> "$SB/app.wrap"
  for i in $(seq 1 50); do [ -s "$pf" ] && break; sleep 0.1; done
  for i in $(seq 1 50); do curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PUB/healthz" && return 0; sleep 0.1; done; return 1; }
stop_apps() { [ -f "$SB/app.wrap" ] && while read -r w; do kill "$w" 2>/dev/null; done < "$SB/app.wrap"; rm -f "$SB/app.wrap" "$SB/app.pid"; sleep 0.3; }
run_cut() { # run_cut <label> <tool_dir> <root> <pidfile> [env...]
  local label=$1 tool=$2 r=$3 pf=$4; shift 4
  local em="$SB/bin/emerg-$label.sh"; stub_emerg "$em"
  env -u WS_EXPECT_FACE WS_ROOT="$r" WS_CACHE="$SB/work/cache.git" WS_EMERG="$em" \
    WS_VERIFY="$tool/ws-verify-faces.sh" WS_PUBLIC_PORT=$PUB WS_OPS_PORT=$OPS WS_CURL_TIMEOUT=2 \
    WS_GATE_BASE="http://127.0.0.1:$PUB" WS_RESOLVE_HOST= WS_SS_CMD=echo WS_MODE=upgrade \
    WS_RESTART_CMD=true WS_PID_CMD="cat $pf" "$@" bash "$tool/cutover.sh" > "$SB/$label.log" 2>&1
  echo $? > "$SB/$label.rc"; }
out() { cat "$SB/$1.log"; }; rc() { cat "$SB/$1.rc"; }

echo
echo "=== P0 重启命令 rc=0 但没重启：baseline 必须假报 OK，候选必须不给 OK ==="
for side in baseline candidate; do
  [ "$side" = baseline ] && TOOL=$BASE_TOOL || TOOL=$CAND_TOOL
  R=$(new_root "p0-$side"); export_tree "$R/releases/$C1" "$C1"; export_tree "$R/releases/$C2" "$C2"
  printf '%s\n' "$C2" > "$R/state/approved-sha"
  # 候选会对账批准记录；baseline 不读这个文件
  if [ -f "$CAND_TOOL/release-id.mjs" ]; then
    RID=$(node "$CAND_TOOL/release-id.mjs" "$R/releases/$C2")
    printf 'sha=%s\nmode=upgrade\nrelease_line=v2\nrollback_to=-\nrelease_id=%s\n' "$C2" "$RID" > "$R/state/approved-meta.txt"
  fi
  start_app "$SB/app.pid"; OLD=$(cat "$SB/app.pid"); ln -sfn "$R/releases/$C1" "$R/current"
  run_cut "p0-$side" "$TOOL" "$R" "$SB/app.pid"
  O=$(out "p0-$side"); NOW_PID=$(cat "$SB/app.pid" 2>/dev/null || echo none)
  if [ "$side" = baseline ]; then
    has "[baseline] 假报 CUTOVER=OK（RED）" "CUTOVER=OK" "$O"
    ck  "[baseline] 退出码" "$(rc p0-baseline)" "0"
    ck  "[baseline] 旧进程 pid 未变（证明没重启）" "$NOW_PID" "$OLD"
    ck  "[baseline] current 已切到 C2" "$(readlink "$R/current" 2>/dev/null || echo none)" "$R/releases/$C2"
    ck  "[baseline] 3200 仍由旧进程应答" "$(curl -s --max-time 2 "http://127.0.0.1:$PUB/healthz")" '{"ok":true}'
  else
    has "[candidate] 预检中止（目标无身份能力）" "CUTOVER=ABORT_IDENTITY_UNSUPPORTED_BY_TARGET" "$O"
    ck  "[candidate] 退出码" "$(rc p0-candidate)" "3"
    hasnt "[candidate] 不得报 OK" "CUTOVER=OK" "$O"
    ck  "[candidate] 旧进程 pid 未变（没重启）" "$NOW_PID" "$OLD"
    ck  "[candidate] current 未变" "$(readlink "$R/current" 2>/dev/null || echo none)" "$R/releases/$C1"
    ck  "[candidate] 未关站" "$( [ -f "$SB/bin/emerg-p0-candidate.sh" ] && ls "$SB/bin/emerg.log" >/dev/null 2>&1 && wc -l < "$SB/bin/emerg.log" || echo 0 )" "0"
  fi
  stop_apps
done

echo
echo "=== P2 重启失败 + 恢复 current 失败：旧版仍称「已退回」 ==="
R=$(new_root p2); export_tree "$R/releases/$C1" "$C1"; export_tree "$R/releases/$C2" "$C2"
printf '%s\n' "$C2" > "$R/state/approved-sha"
start_app "$SB/app.pid"; ln -sfn "$R/releases/$C1" "$R/current"
printf '#!/usr/bin/env bash\nrm -f "%s/current"; mkdir "%s/current"; exit 1\n' "$R" "$R" > "$SB/bin/break.sh"; chmod +x "$SB/bin/break.sh"
run_cut p2 "$BASE_TOOL" "$R" "$SB/app.pid" WS_RESTART_CMD="$SB/bin/break.sh"
O=$(out p2)
has "[baseline] 宣称已退回（与事实相反）" "已退回" "$O"
ck  "[baseline] 退出码" "$(rc p2)" "1"
if [ -L "$R/current" ]; then ck "[baseline] current 变成了真实目录" "dir" "link"; else ck "[baseline] current 变成真实目录且未被察觉" "dir" "dir"; fi
stop_apps

echo
echo "=== P3 current 指向 ROOT 之外（目录名恰好是合法 SHA） ==="
R=$(new_root p3); export_tree "$R/releases/$C1" "$C1"; export_tree "$R/releases/$C2" "$C2"
printf '%s\n' "$C2" > "$R/state/approved-sha"
mkdir -p "$SB/outside/$C1"; export_tree "$SB/outside/$C1" "$C1"
start_app "$SB/app.pid"; ln -sfn "$SB/outside/$C1" "$R/current"
run_cut p3 "$BASE_TOOL" "$R" "$SB/app.pid"
O=$(out p3)
has "[baseline] 给 OK（不校验位置边界）" "CUTOVER=OK" "$O"
ck  "[baseline] 退出码" "$(rc p3)" "0"
stop_apps

echo
echo "=== P4 releases 根目录本身是符号链接 ==="
R=$(new_root p4); rm -rf "$R/releases"; mkdir -p "$SB/outside/releases"
export_tree "$SB/outside/releases/$C1" "$C1"; export_tree "$SB/outside/releases/$C2" "$C2"
ln -sfn "$SB/outside/releases" "$R/releases"; printf '%s\n' "$C2" > "$R/state/approved-sha"
start_app "$SB/app.pid"; ln -sfn "$R/releases/$C1" "$R/current"
run_cut p4 "$BASE_TOOL" "$R" "$SB/app.pid"
O=$(out p4)
has "[baseline] 给 OK（releases 解析到 ROOT 外）" "CUTOVER=OK" "$O"
ck  "[baseline] 退出码" "$(rc p4)" "0"
stop_apps

echo
echo "=== P5 info/grafts 伪造祖先 ==="
restore_cache
R=$(new_root p5); export_tree "$R/releases/$C1" "$C1"; export_tree "$R/releases/$X" "$X"
printf '%s\n' "$X" > "$R/state/approved-sha"
start_app "$SB/app.pid"; ln -sfn "$R/releases/$C1" "$R/current"
printf '%s %s\n' "$X" "$C2" > "$SB/work/cache.git/info/grafts"
run_cut p5 "$BASE_TOOL" "$R" "$SB/app.pid"
O=$(out p5)
has "[baseline] 给 OK（grafts 绕过发布线闸门）" "CUTOVER=OK" "$O"
ck  "[baseline] 退出码" "$(rc p5)" "0"
restore_cache
stop_apps

echo
echo "=== P6 WS_POLL_TRIES=0：健康站点被关站 ==="
R=$(new_root p6); export_tree "$R/releases/$C1" "$C1"; export_tree "$R/releases/$C2" "$C2"
printf '%s\n' "$C2" > "$R/state/approved-sha"
start_app "$SB/app.pid"; ln -sfn "$R/releases/$C1" "$R/current"
BEFORE=$(curl -s --max-time 2 "http://127.0.0.1:$PUB/healthz")
run_cut p6 "$BASE_TOOL" "$R" "$SB/app.pid" WS_POLL_TRIES=0
O=$(out p6); AFTER=$(curl -s --max-time 2 "http://127.0.0.1:$PUB/healthz")
ck  "[baseline] 运行前站点健康" "$BEFORE" '{"ok":true}'
ck  "[baseline] 运行后站点仍健康（服务从未不可用）" "$AFTER" '{"ok":true}'
has "[baseline] 把健康站点判成不可用" "FAILED_AND_CLOSED" "$O"
has "[baseline] 因此调用了关站" "EMERG_CALLED close" "$(cat "$SB/bin/emerg.log" 2>/dev/null || true)"
ck  "[baseline] 退出码" "$(rc p6)" "1"
stop_apps

echo
echo "=== P7 WS_RELEASE_LINE=alt 放行非 v2 线 ==="
R=$(new_root p7); export_tree "$R/releases/$C1" "$C1"; export_tree "$R/releases/$ALT" "$ALT"
printf '%s\n' "$ALT" > "$R/state/approved-sha"
start_app "$SB/app.pid"; ln -sfn "$R/releases/$C1" "$R/current"
run_cut p7 "$BASE_TOOL" "$R" "$SB/app.pid" WS_RELEASE_LINE=alt
O=$(out p7)
has "[baseline] 给 OK（残留 env 换线无人拦）" "CUTOVER=OK" "$O"
hasnt "[baseline] 不提越线" "NOT_IN_RELEASE_LINE" "$O"
ck  "[baseline] 退出码" "$(rc p7)" "0"
stop_apps

echo
echo "=== P8 注释里的 opsPort 被当成真实诊断面能力 ==="
R=$(new_root p8); export_tree "$R/releases/$C1" "$C1"; export_tree "$R/releases/$K" "$K"
printf '%s\n' "$K" > "$R/state/approved-sha"
start_app "$SB/app.pid"; ln -sfn "$R/releases/$C1" "$R/current"
run_cut p8 "$BASE_TOOL" "$R" "$SB/app.pid"
O=$(out p8)
has "[baseline] 把只有注释的 K 判成 dual_face" "dual_face" "$O"
hasnt "[baseline] 未在写入前中止 LEGACY_AS_UPGRADE" "LEGACY_AS_UPGRADE" "$O"
ck  "[baseline] current 已被切到 K（写入已发生）" "$(readlink "$R/current" 2>/dev/null || echo none)" "$R/releases/$K"
stop_apps

echo
echo "R3_BASELINE_RED_PROBES_FAILS=$FAILS（共 $TOTAL 项）"
[ "$FAILS" -eq 0 ] && echo "R3_BASELINE_RED_PROBES=PASS" || echo "R3_BASELINE_RED_PROBES=FAIL"
exit "$FAILS"
