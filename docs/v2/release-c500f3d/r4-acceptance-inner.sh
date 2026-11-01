#!/usr/bin/env bash
# R4 真实验收（容器内执行）—— 由 r4-acceptance.sh 在 node:20 容器里启动。
#
# 前置（宿主脚本负责）：
#   /srv/trees/{base,prev,r4,r3base}  三/四棵由 git archive 解出的 LF 发布树
#   /srv/static/{ai,ming}             /ai/ 的已接受静态树 + /ming/ 夹具
#   /srv/nginx/nginx.conf             nginx 1.18 配置（upstream 指向本容器）
#   /srv/manifests/{base,prev,r4}.lst 宿主从真实提交读出的"blob 内容+路径"清单（证明导入无损）
#   NGINX_HOST                        nginx 容器名（同网络，端口 8080）
#   R4_SHA / PREV_SHA / BASE_SHA      目标 / 上一版（有身份）/ 生产基线（无身份）
#
# 做两件事：
#   A. 真 nginx + 真 world.mjs 的 12 项验收（匿名门面 / /ai/ / 登录登出 / API / 边界 /ming/ 身份）
#   B. 用 cutover.sh 跑四个场景：正常发布 / 假重启 / 重启失败 / 回滚
# 然后跑 R3 四套装置与首页回归，全部输出真实退出码。
#
# 退出码：0 = 全绿；非 0 = 失败项数。
set -uo pipefail
: "${NGINX_HOST:?}" "${R4_SHA:?}" "${PREV_SHA:?}" "${BASE_SHA:?}"
MANIFEST_DIR=${MANIFEST_DIR:-/srv/manifests}

T=/srv/work; ROOT=$T/root; CACHE=$ROOT/.git-cache/World-Space.git; ORIGIN=$T/origin
# 工具一律从"宿主按 LF 展开的那棵树"取；$ROOT/releases/ 下的目录名是下面合成提交的 SHA，
# 与宿主传进来的真实提交号不是同一个数值（合成提交的 author/date 不同），不能拿来当初值。
REL4=/srv/trees/r4
NG="http://$NGINX_HOST:8080"
N=0; F=0
ck()   { N=$((N+1)); if [ "$2" = "$3" ]; then echo "PASS $1 = $2"; else echo "FAIL $1 = $2（期望 $3）"; F=$((F+1)); fi; }
has()  { N=$((N+1)); if printf '%s' "$2" | grep -qF -- "$3"; then echo "PASS $1 含「$3」"; else echo "FAIL $1 缺「$3」"; F=$((F+1)); fi; }
hasnt(){ N=$((N+1)); if printf '%s' "$2" | grep -qF -- "$3"; then echo "FAIL $1 不该含「$3」"; F=$((F+1)); else echo "PASS $1 无「$3」"; fi; }
jget() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const v=j[process.argv[1]];console.log(typeof v==="undefined"?"":String(v))}catch(e){console.log("ERR")}})' "$1"; }
code() { curl -s -o "$2" -w '%{http_code}' "$1"; }
md5f() { md5sum "$1" | cut -d' ' -f1; }
ops_rid() { curl -s --max-time 3 http://127.0.0.1:3201/healthz | jget release_id; }
ops_pid() { curl -s --max-time 3 http://127.0.0.1:3201/healthz | jget pid; }
ops_started() { curl -s --max-time 3 http://127.0.0.1:3201/healthz | jget started_at_ms; }
pub_ok() { curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3200/healthz; }

mkdir -p "$T/body" "$ROOT"/{releases,state,etc,run,bin}
B=$T/body

echo "=== 0) 用三棵真树搭一个真 git 源（提交号由内容决定，不是编的） ==="
# Windows 绑定挂载不保留 exec 位，合成提交里所有文件都会记成 100755；内容字节不受影响。
# 所以这里不比对整棵 tree 号，而是比对"路径+blob 内容"清单——发布身份只认内容字节，
# cutover 的 verify_release_tree 也只比路径与 blob 内容（模式只用来判符号链接）。
git init -q -b v2 "$ORIGIN"
git -C "$ORIGIN" config user.email r4@local; git -C "$ORIGIN" config user.name r4
import_tree() { find "$ORIGIN" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +; cp -a "$1"/. "$ORIGIN"/; git -C "$ORIGIN" add -A -f .; }
manifest_of() { git -C "$ORIGIN" ls-tree -r --format='%(objectname) %(path)' HEAD | LC_ALL=C sort | sha256sum | cut -d' ' -f1; }
manifest_ck() { # manifest_ck <label>：与宿主从真实提交读出的清单逐条相同
  local want; want=$(sha256sum < "$MANIFEST_DIR/$1.lst" | cut -d' ' -f1)
  ck "manifest_$1_same_as_real_commit" "$(manifest_of)" "$want"
  echo "  $1 文件数=$(git -C "$ORIGIN" ls-tree -r --name-only HEAD | wc -l | tr -d ' ')"
}
import_tree /srv/trees/base; git -C "$ORIGIN" commit -q -m "base: production v2 tree"
BASE_SHA=$(git -C "$ORIGIN" rev-parse HEAD)
manifest_ck base
import_tree /srv/trees/prev; git -C "$ORIGIN" commit -q -m "prev: v2 + release tooling (identity)"
manifest_ck prev
PREV_SHA=$(git -C "$ORIGIN" rev-parse HEAD)
import_tree /srv/trees/r4; git -C "$ORIGIN" commit -q -m "r4: integrated candidate"
manifest_ck r4
R4_SHA=$(git -C "$ORIGIN" rev-parse HEAD)
# 假重启 / 重启失败场景需要一个"更新的、行为相同"的后继提交（只多一个说明文件）
printf 'scene carrier for restart-negative tests\n' > "$ORIGIN/scene-note.txt"
git -C "$ORIGIN" add -A -f .; git -C "$ORIGIN" commit -q -m "scene: successor carrier for negative tests"
C3_SHA=$(git -C "$ORIGIN" rev-parse HEAD)
echo "BASE=$BASE_SHA PREV=$PREV_SHA R4=$R4_SHA C3=$C3_SHA"
git clone -q --bare "$ORIGIN" "$CACHE" || { echo "FAIL git clone --bare"; exit 1; }
# cutover 要求"目标必须包含发布线最新提交"。生产里这是 ws-prep 把新提交推进 refs/heads/v2 的结果，
# 这里按同一含义在每次切流前把发布线指到本次目标（不是放宽判据）。
line_to() { git -C "$CACHE" update-ref refs/heads/v2 "$1" || { echo "FAIL 更新发布线 refs/heads/v2 -> $1"; exit 1; }; }

echo "=== 1) 发布根：三棵树 + 一个后继载体（逐文件等于提交树） ==="
cp -a /srv/trees/base/. "$ROOT/releases/$BASE_SHA"/
cp -a /srv/trees/prev/. "$ROOT/releases/$PREV_SHA"/
cp -a /srv/trees/r4/.   "$ROOT/releases/$R4_SHA"/
cp -a /srv/trees/r4/.   "$ROOT/releases/$C3_SHA"/; cp "$ORIGIN/scene-note.txt" "$ROOT/releases/$C3_SHA"/

ID4=$(node "$REL4/docs/v2/release-c500f3d/release-id.mjs" "$ROOT/releases/$R4_SHA")
IDP=$(node "$REL4/docs/v2/release-c500f3d/release-id.mjs" "$ROOT/releases/$PREV_SHA")
IDB=$(node "$REL4/docs/v2/release-c500f3d/release-id.mjs" "$ROOT/releases/$BASE_SHA")
ID3=$(node "$REL4/docs/v2/release-c500f3d/release-id.mjs" "$ROOT/releases/$C3_SHA")
echo "R4 发布身份=$ID4"; echo "PREV 发布身份=$IDP"; echo "BASE 发布身份=$IDB"; echo "C3 发布身份=$ID3"
ck identity_r4_matches_supplied "$ID4" "${EXPECT_RELEASE_ID:--}"
ck identity_r4_changed_vs_prev "$([ "$ID4" = "$IDP" ] && echo same || echo different)" different
ck identity_r4_changed_vs_base "$([ "$ID4" = "$IDB" ] && echo same || echo different)" different

echo "=== 2) 运行期配置（用户/密钥/预算全部在发布树之外） ==="
: > "$ROOT/state/emergency.log"   # 让"关站调用了几次"有一个可数的空账本（0 行 = 没调用）
printf '%s' 'r4-pass-2026' | node "$REL4/scripts/hash-password.mjs" u-r4 r4 > "$T/u.json" \
  || { echo "FAIL hash-password"; exit 1; }
node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify({users:[JSON.parse(fs.readFileSync(process.argv[2],"utf8"))]},null,2))' \
  "$ROOT/etc/users.json" "$T/u.json"
node -e 'console.log(require("crypto").randomBytes(48).toString("base64"))' > "$ROOT/etc/session-secret.txt"
echo "fixture: $ROOT/etc/users.json $(wc -c < "$ROOT/etc/users.json")B, secret $(wc -c < "$ROOT/etc/session-secret.txt")B"

cat > "$ROOT/bin/restart.sh" <<EOF
#!/usr/bin/env bash
# 真重启：停旧进程，再按 current 起新进程（写 pid 文件）
# WS_HOST=0.0.0.0 只是本隔离网络里的拓扑需要（nginx 与 node 分处两个容器）；
# 生产里 node 与 nginx 同机，公网口仍只绑 127.0.0.1。诊断口在代码里写死 127.0.0.1，不随此变量变。
set -u
[ -f "$ROOT/run/app.pid" ] && kill "\$(cat "$ROOT/run/app.pid")" 2>/dev/null || true
for i in \$(seq 1 100); do kill -0 "\$(cat "$ROOT/run/app.pid" 2>/dev/null)" 2>/dev/null || break; sleep 0.05; done
rel=\$(readlink -f "$ROOT/current")
( cd "\$rel" && exec nohup env WS_HOST=0.0.0.0 WS_PORT=3200 WS_OPS_PORT=3201 WS_PROVIDER=stub WS_SEARCH=fixture \\
  WS_STATE_FILE="$ROOT/state/budget.json" WS_AUTH_USERS_FILE="$ROOT/etc/users.json" \\
  WS_SESSION_SECRET_FILE="$ROOT/etc/session-secret.txt" WS_RATE_LIMIT=1000 WS_LIVENESS=0 WS_DAILY_CAP=500 \\
  node server/world.mjs >> "$ROOT/run/app.log" 2>&1 ) &
echo \$! > "$ROOT/run/app.pid"
EOF
cat > "$ROOT/bin/restart-kill-fail.sh" <<EOF
#!/usr/bin/env bash
# 重启失败的一种真实形态：旧进程已经停了，新进程起不来
kill "\$(cat "$ROOT/run/app.pid")" 2>/dev/null || true
sleep 0.3
exit 1
EOF
cat > "$ROOT/bin/fake-restart.sh" <<'EOF'
#!/usr/bin/env bash
# 假重启：退出码 0，但什么都没做
exit 0
EOF
cat > "$ROOT/bin/emergency.sh" <<EOF
#!/usr/bin/env bash
echo "EMERG_CALLED \$1" >> "$ROOT/state/emergency.log"
exit 0
EOF
chmod +x "$ROOT"/bin/*.sh

start_app() {
  local rel; rel=$(readlink -f "$ROOT/current")
  # exec：让后台作业的 pid 就是 node 的 pid，否则 app.pid 记的是中间 shell，kill 打不中真进程
  ( cd "$rel" && exec nohup env WS_HOST=0.0.0.0 WS_PORT=3200 WS_OPS_PORT=3201 WS_PROVIDER=stub WS_SEARCH=fixture \
      WS_STATE_FILE="$ROOT/state/budget.json" WS_AUTH_USERS_FILE="$ROOT/etc/users.json" \
      WS_SESSION_SECRET_FILE="$ROOT/etc/session-secret.txt" WS_RATE_LIMIT=1000 WS_LIVENESS=0 WS_DAILY_CAP=500 \
      node server/world.mjs >> "$ROOT/run/app.log" 2>&1 ) &
  echo $! > "$ROOT/run/app.pid"
  wait_up
}
wait_up() { for i in $(seq 1 100); do [ "$(pub_ok)" = 200 ] && return 0; sleep 0.1; done; return 1; }
stop_app() { [ -f "$ROOT/run/app.pid" ] && kill "$(cat "$ROOT/run/app.pid")" 2>/dev/null; sleep 0.4; }

meta_write() { # <mode> <sha> <release_id> <rollback_to>
  printf 'sha=%s\nmode=%s\nrelease_line=v2\nrelease_id=%s\nrollback_to=%s\n' "$2" "$1" "$3" "$4" > "$ROOT/state/approved-meta.txt"
  printf '%s' "$2" > "$ROOT/state/approved-sha"
}
run_cutover() { # <logname> —— 输出打到 $B/<logname>.log，返回 cutover 的退出码
  # 核验器的"访问门"默认打 https://ymai.fun（生产形态）；本隔离环境没有 TLS，
  # 就把它指向 nginx 1.18 的 8080（同样经过 nginx，而不是绕过它直连应用）。
  ( cd "$REL4/docs/v2/release-c500f3d" && \
    WS_ROOT="$ROOT" WS_CACHE="$CACHE" WS_EMERG="$ROOT/bin/emergency.sh" \
    WS_VERIFY="${WS_VERIFY_OVERRIDE:-$REL4/docs/v2/release-c500f3d/ws-verify-faces.sh}" \
    WS_GATE_BASE="$NG" WS_RESOLVE_HOST="" \
    WS_RESTART_CMD="${RESTART_CMD:-$ROOT/bin/restart.sh}" WS_PID_CMD="cat $ROOT/run/app.pid" \
    WS_PUBLIC_PORT=3200 WS_OPS_PORT=3201 WS_POLL_TRIES=100 WS_MODE="${CUT_MODE:-upgrade}" \
    WS_ROLLBACK_TO="${CUT_ROLLBACK_TO:-}" \
    bash ./cutover.sh ) > "$B/$1.log" 2>&1
  echo $?
}

echo "=== 3) 初始状态：线上 = 生产基线（无门面、无身份），起真应用 ==="
ln -sfn "$ROOT/releases/$BASE_SHA" "$ROOT/current"
meta_write upgrade "$BASE_SHA" "$IDB" ""
start_app || { echo "FAIL 初始应用起不来"; tail -20 "$ROOT/run/app.log"; exit 1; }
ck baseline_root_redirects_to_login "$(code http://127.0.0.1:3200/ "$B/base-root")" 302
# 生产基线（v2 3e8e15f1）没有身份能力：诊断面不该有 release_id —— 这正是"升级必须要求目标带身份"的起点
ck baseline_runtime_id_absent "$(ops_rid)" ""

echo "=== 4) 场景 S1：正常发布到集成候选（真重启） ==="
line_to "$R4_SHA"
meta_write upgrade "$R4_SHA" "$ID4" ""
PRE_PID=$(ops_pid)
T0_MS=$(node -e 'console.log(Date.now())')
RESTART_CMD="$ROOT/bin/restart.sh" CUT_MODE=upgrade; export RESTART_CMD CUT_MODE
RC=$(run_cutover s1-upgrade)
S1=$(cat "$B/s1-upgrade.log")
ck s1_exit "$RC" 0
has s1_ok_token "$S1" 'CUTOVER=OK'
ck s1_current "$(readlink "$ROOT/current")" "$ROOT/releases/$R4_SHA"
ck s1_runtime_identity "$(ops_rid)" "$ID4"
ck s1_new_pid "$([ "$(ops_pid)" != "$PRE_PID" ] && echo changed || echo same)" changed
ck s1_started_after_T0 "$([ -n "$(ops_started)" ] && [ "$(ops_started)" -ge "$T0_MS" ] && echo yes || echo no)" yes
ck s1_meta_release_id "$(grep '^release_id=' "$ROOT/state/approved-meta.txt" | cut -d= -f2)" "$ID4"
REC=$(ls -t "$ROOT"/state/cutover-*.txt | head -1)
ck s1_receipt_status "$(grep '^status=' "$REC" | cut -d= -f2)" OK
ck s1_receipt_target_id "$(grep '^target_release_id=' "$REC" | cut -d= -f2)" "$ID4"
ck s1_receipt_verifier "$(grep '^verifier_sha256=' "$REC" | cut -d= -f2)" "$(awk 'NR==1{print $1}' "$REL4/docs/v2/release-c500f3d/ws-verify-faces.sh.sha256")"
ck s1_emergency_not_called "$([ -f "$ROOT/state/emergency.log" ] && wc -l < "$ROOT/state/emergency.log" || echo 0)" 0

echo "=== 5) 12 项验收（经 nginx 1.18 真实转发） ==="
# 1 匿名公开首页
ck a1_root_status "$(code "$NG/" "$B/root.html")" 200
has a1_root_facade_title "$(cat "$B/root.html")" '你想做什么事'
has a1_root_write_button "$(cat "$B/root.html")" 'id="btn-write"'
ck a1_root_bytes_ge_8000 "$([ "$(wc -c < "$B/root.html")" -ge 8000 ] && echo yes || echo no)" yes
hasnt a1_root_not_login_redirect "$(cat "$B/root.html")" '进入你的空间'
# 2 /ai/ 并列入口
ck a2_ai_slash_status "$(code "$NG/ai/" "$B/ai.html")" 200
has a2_ai_title "$(cat "$B/ai.html")" 'AI 从零开始'
ck a2_ai_no_slash_301 "$(curl -s -o /dev/null -w '%{http_code}' --max-redirs 0 "$NG/ai")" 301
ck a2_ai_deeplink "$(code "$NG/ai/paths/make-something.html" "$B/ai-deep.html")" 200
ck a2_ai_asset "$(code "$NG/ai/assets/ai.css" "$B/ai.css")" 200
ck a2_ai_missing_404 "$(code "$NG/ai/does-not-exist.html" "$B/ai-404")" 404
# 3 登录 / 登出
ck a3_login_status "$(curl -s -c "$T/jar" -H 'content-type: application/json' -d '{"username":"r4","password":"r4-pass-2026"}' -o "$B/login.json" -w '%{http_code}' "$NG/api/auth/login")" 200
ck a3_login_ok "$(jget ok < "$B/login.json")" true
ck a3_session_cookie "$(grep -c $'^127.0.0.1\|^#HttpOnly' "$T/jar")" 1
ck a3_me_after_login "$(curl -s -b "$T/jar" -o "$B/me.json" -w '%{http_code}' "$NG/api/auth/me")" 200
ck a3_me_user "$(jget user_id < "$B/me.json")" u-r4
ck a3_logged_in_root_is_app "$(curl -s -b "$T/jar" -o "$B/app.html" -w '%{http_code}' "$NG/")" 200
has a3_logged_in_root_app_title "$(cat "$B/app.html")" '你现在想做成什么'
# 4 登录后 API
ck a4_world_status "$(curl -s -b "$T/jar" -H 'content-type: application/json' -d '{"intent":"把家里旧照片整理成一份备份清单"}' -o "$B/world.json" -w '%{http_code}' "$NG/api/world")" 200
ck a4_world_no_error "$(jget error < "$B/world.json")" ""
ck a4_logout_status "$(curl -s -b "$T/jar" -H 'content-type: application/json' -X POST -d '{}' -o "$B/logout.json" -w '%{http_code}' "$NG/api/auth/logout")" 200
ck a4_me_after_logout "$(curl -s -b "$T/jar" -o /dev/null -w '%{http_code}' "$NG/api/auth/me")" 401
# 5 未授权 API 不泄露
ck a5_world_unauth "$(curl -s -H 'content-type: application/json' -d '{"intent":"未登录试试"}' -o "$B/unauth-world.json" -w '%{http_code}' "$NG/api/world")" 401
ck a5_me_unauth "$(curl -s -o "$B/unauth-me.json" -w '%{http_code}' "$NG/api/auth/me")" 401
hasnt a5_no_userid_leak "$(cat "$B/unauth-world.json" "$B/unauth-me.json")" 'u-r4'
hasnt a5_no_cookie_leak "$(cat "$B/unauth-world.json")" 'session'
# 6 /healthz
ck a6_healthz "$(curl -s -o "$B/hz.json" -w '%{http_code}' "$NG/healthz")" 200
ck a6_healthz_body "$(jget ok < "$B/hz.json")" true
ck a6_detail_not_public "$(code "$NG/healthz/detail" "$B/detail")" 404
# 7 /ming/ 不受影响
MING_MD5=$(md5f /srv/static/ming/index.html)
ck a7_ming_status "$(code "$NG/ming/" "$B/ming.html")" 200
ck a7_ming_unchanged "$(md5f "$B/ming.html")" "$MING_MD5"
ck a7_ming_no_slash_301 "$(curl -s -o /dev/null -w '%{http_code}' --max-redirs 0 "$NG/ming")" 301
# 8 身份 = 集成树
ck a8_runtime_release_id "$(ops_rid)" "$ID4"
ck a8_runtime_scheme "$(curl -s http://127.0.0.1:3201/healthz | jget release_id_scheme)" world-release-tree-v1
ck a8_runtime_pid_matches "$(ops_pid)" "$(cat "$ROOT/run/app.pid")"
ck a8_diagnostic_face "$(curl -s http://127.0.0.1:3201/healthz | jget diagnostic_face)" ops-v1

echo "=== 5b) 分享卡 / 登录页 / API 契约 / 私密面 ==="
PAGE=$(cat "$B/root.html")
has og_title "$PAGE" '<meta property="og:title" content="World Space — 你想做什么事？">'
has og_description "$PAGE" '<meta property="og:description" content="选一件事，马上开始。'
has og_type "$PAGE" '<meta property="og:type" content="website">'
has og_url "$PAGE" '<meta property="og:url" content="https://ymai.fun">'
has html_title "$PAGE" '<title>World Space — 你想做什么事？</title>'
hasnt og_no_placeholder "$PAGE" 'content=""'
ck login_page_status "$(code "$NG/login" "$B/login.html")" 200
has login_page_title "$(cat "$B/login.html")" '进入你的空间'
ck api_world_get_404 "$(curl -s -o "$B/world-get.json" -w '%{http_code}' "$NG/api/world")" 404
has api_world_get_contract "$(cat "$B/world-get.json")" 'only POST /api/world exists'
ck ops_roster_not_public "$(code "$NG/api/ops/roster" "$B/roster.json")" 404
hasnt roster_no_payload "$(cat "$B/roster.json")" 'members'
# 四条旅程（同一进程里按真实顺序走：匿名 → 登录 → 未授权反证 → 登出后再访）
ck j1_anonymous_root "$(code "$NG/" "$B/j1-root.html")" 200
has j1_anonymous_facade "$(cat "$B/j1-root.html")" '你想做什么事'
ck j1_anonymous_ai "$(code "$NG/ai/" "$B/j1-ai.html")" 200
ck j1_anonymous_ai_deeplink "$(code "$NG/ai/paths/make-a-picture.html" "$B/j1-ai-deep.html")" 200
ck j1_anonymous_login "$(code "$NG/login" "$B/j1-login.html")" 200
ck j2_login "$(curl -s -c "$T/jar2" -H 'content-type: application/json' -d '{"username":"r4","password":"r4-pass-2026"}' -o /dev/null -w '%{http_code}' "$NG/api/auth/login")" 200
ck j2_root_is_app "$(curl -s -b "$T/jar2" -o "$B/j2-root.html" -w '%{http_code}' "$NG/")" 200
has j2_root_app_marker "$(cat "$B/j2-root.html")" '你现在想做成什么'
ck j2_world "$(curl -s -b "$T/jar2" -H 'content-type: application/json' -d '{"intent":"给爸妈做一份用药提醒清单"}' -o "$B/j2-world.json" -w '%{http_code}' "$NG/api/world")" 200
ck j3_world_unauth "$(curl -s -H 'content-type: application/json' -d '{"intent":"x"}' -o "$B/j3-world.json" -w '%{http_code}' "$NG/api/world")" 401
ck j3_me_unauth "$(curl -s -o "$B/j3-me.json" -w '%{http_code}' "$NG/api/auth/me")" 401
hasnt j3_no_private_leak "$(cat "$B/j3-world.json" "$B/j3-me.json")" 'u-r4'
ck j4_logout "$(curl -s -b "$T/jar2" -H 'content-type: application/json' -X POST -d '{}' -o /dev/null -w '%{http_code}' "$NG/api/auth/logout")" 200
ck j4_root_facade_again "$(curl -s -b "$T/jar2" -o "$B/j4-root.html" -w '%{http_code}' "$NG/")" 200
has j4_facade_after_logout "$(cat "$B/j4-root.html")" '你想做什么事'
ck j4_me_after_logout "$(curl -s -b "$T/jar2" -o /dev/null -w '%{http_code}' "$NG/api/auth/me")" 401

echo "=== 5c) 场景 S5：核验器版本被换（哈希不符）—— 任何写入之前中止 ==="
line_to "$C3_SHA"; meta_write upgrade "$C3_SHA" "$ID3" ""
SNAP_C=$(readlink "$ROOT/current"); SNAP_P=$(ops_pid); REC0=$(ls "$ROOT"/state/cutover-*.txt 2>/dev/null | wc -l | tr -d ' ')
cp "$REL4/docs/v2/release-c500f3d/ws-verify-faces.sh" "$T/bad-verifier.sh"
printf '\n# tampered\n' >> "$T/bad-verifier.sh"
RC=$(WS_VERIFY_OVERRIDE="$T/bad-verifier.sh" run_cutover s5-verifier-mismatch)
S5=$(cat "$B/s5-verifier-mismatch.log")
ck s5_exit "$RC" 3
has s5_token "$S5" 'CUTOVER=ABORT_VERIFIER_IDENTITY_MISMATCH'
hasnt s5_no_ok "$S5" 'CUTOVER=OK'
ck s5_current_unchanged "$(readlink "$ROOT/current")" "$SNAP_C"
ck s5_pid_unchanged "$(ops_pid)" "$SNAP_P"
ck s5_no_receipt "$(ls "$ROOT"/state/cutover-*.txt 2>/dev/null | wc -l | tr -d ' ')" "$REC0"

echo "=== 5d) 场景 S6：Git 元数据伪造（replace refs / info/grafts） ==="
WS_ROOT="$ROOT" WS_CACHE="$CACHE" WS_CUTOVER="$REL4/docs/v2/release-c500f3d/cutover.sh" \
WS_TARGET="$C3_SHA" WS_EMERG="$ROOT/bin/emergency.sh" \
WS_VERIFY="$REL4/docs/v2/release-c500f3d/ws-verify-faces.sh" \
WS_GATE_BASE="$NG" WS_RESTART_CMD="$ROOT/bin/restart.sh" WS_PID_CMD="cat $ROOT/run/app.pid" \
WS_PUBLIC_PORT=3200 WS_OPS_PORT=3201 \
  bash "$REL4/docs/v2/release-c500f3d/git-metadata-adversarial.sh" > "$B/git_metadata_adversarial.log" 2>&1
RC=$?
ck s6_script_exit "$RC" 0
has s6_verdict "$(tail -3 "$B/git_metadata_adversarial.log" | tr '\n' ' ')" 'GIT_METADATA_ADVERSARIAL=PASS'
ck s6_no_receipt "$(ls "$ROOT"/state/cutover-*.txt 2>/dev/null | wc -l | tr -d ' ')" "$REC0"

echo "=== 5e) 场景 S7：发布树被改 / 含符号链接 / 目标目录是链接 / current 逃逸 ==="
SNAP_C=$(readlink "$ROOT/current"); SNAP_P=$(ops_pid); SNAP_ID=$(ops_rid)
cp "$ROOT/releases/$C3_SHA/README.md" "$T/readme.bak"
printf 'tamper\n' >> "$ROOT/releases/$C3_SHA/README.md"
RC=$(run_cutover s7a-tree-tampered); S7A=$(cat "$B/s7a-tree-tampered.log")
ck s7a_exit "$RC" 3
has s7a_token "$S7A" 'CUTOVER=ABORT_RELEASE_TREE_MISMATCH'
ck s7a_current_unchanged "$(readlink "$ROOT/current")" "$SNAP_C"
ck s7a_pid_unchanged "$(ops_pid)" "$SNAP_P"
cp "$T/readme.bak" "$ROOT/releases/$C3_SHA/README.md"

ln -s /etc/passwd "$ROOT/releases/$C3_SHA/evil-link"
RC=$(run_cutover s7b-tree-symlink); S7B=$(cat "$B/s7b-tree-symlink.log")
ck s7b_exit "$RC" 3
has s7b_token "$S7B" 'CUTOVER=ABORT_RELEASE_TREE_SYMLINK'
ck s7b_pid_unchanged "$(ops_pid)" "$SNAP_P"
rm -f "$ROOT/releases/$C3_SHA/evil-link"

FAKE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
meta_write upgrade "$FAKE_SHA" "$ID3" ""
ln -s /srv/static "$ROOT/releases/$FAKE_SHA"
RC=$(run_cutover s7c-target-is-link); S7C=$(cat "$B/s7c-target-is-link.log")
ck s7c_exit "$RC" 3
has s7c_token "$S7C" 'CUTOVER=ABORT_RELEASE_TREE_MISSING'
ck s7c_pid_unchanged "$(ops_pid)" "$SNAP_P"
rm -f "$ROOT/releases/$FAKE_SHA"

meta_write upgrade "$C3_SHA" "$ID3" ""
ln -sfn /srv/static "$ROOT/current"
RC=$(run_cutover s7d-live-escape); S7D=$(cat "$B/s7d-live-escape.log")
ck s7d_exit "$RC" 3
has s7d_token "$S7D" 'CUTOVER=ABORT_LIVE_IDENTITY_UNKNOWN'
ck s7d_pid_unchanged "$(ops_pid)" "$SNAP_P"
ck s7d_identity_still_r4 "$(ops_rid)" "$SNAP_ID"
ck s7d_service_alive "$(pub_ok)" 200
ln -sfn "$ROOT/releases/$R4_SHA" "$ROOT/current"; meta_write upgrade "$R4_SHA" "$ID4" ""
ck s7_restored_current "$(readlink "$ROOT/current")" "$ROOT/releases/$R4_SHA"

echo "=== 6) 场景 S2：重启命令退出 0 但没重启（假重启不得假报成功） ==="
line_to "$C3_SHA"
meta_write upgrade "$C3_SHA" "$ID3" ""
PRE_PID=$(ops_pid)
RESTART_CMD="$ROOT/bin/fake-restart.sh" CUT_MODE=upgrade; export RESTART_CMD CUT_MODE
RC=$(run_cutover s2-fake-restart)
S2=$(cat "$B/s2-fake-restart.log")
ck s2_exit "$RC" 1
has s2_no_ok_token "$S2" 'CUTOVER=FAILED_SCENE_PRESERVED'
hasnt s2_never_ok "$S2" 'CUTOVER=OK'
ck s2_scene_is_target "$(readlink "$ROOT/current")" "$ROOT/releases/$C3_SHA"
ck s2_old_process_still_serving "$(ops_pid)" "$PRE_PID"
ck s2_identity_still_r4 "$(ops_rid)" "$ID4"
ck s2_service_alive "$(pub_ok)" 200
ck s2_emergency_not_called "$(wc -l < "$ROOT/state/emergency.log" 2>/dev/null || echo 0)" 0
# 假重启后 current 停在目标目录、进程仍是旧版：这是留给人的现场，cutover 不会替你退回。
# 为继续下一场景，按"人工处置"把 current 与批准记录指回真正在服务的 R4（相当于运维确认后的恢复）。
ln -sfn "$ROOT/releases/$R4_SHA" "$ROOT/current"
meta_write upgrade "$R4_SHA" "$ID4" ""
ck s2_manual_repair_current "$(readlink "$ROOT/current")" "$ROOT/releases/$R4_SHA"

echo "=== 7) 场景 S3a：重启命令失败、旧进程还在 —— 必须保留现场 ==="
line_to "$C3_SHA"
meta_write upgrade "$C3_SHA" "$ID3" ""
PRE_PID=$(ops_pid)
CUT_MODE=upgrade; export CUT_MODE
RESTART_CMD="$ROOT/bin/restart-kill-fail.sh"
# 该脚本会真的把旧进程停掉：先复制一份"只退出 1、不动进程"的版本用于 S3a
cat > "$ROOT/bin/restart-fail-early.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$ROOT/bin/restart-fail-early.sh"
RESTART_CMD="$ROOT/bin/restart-fail-early.sh"; export RESTART_CMD
RC=$(run_cutover s3a-restart-fail)
S3A=$(cat "$B/s3a-restart-fail.log")
ck s3a_exit "$RC" 1
has s3a_scene_preserved "$S3A" 'CUTOVER=FAILED_RESTART_SCENE_PRESERVED'
ck s3a_current_restored "$(readlink "$ROOT/current")" "$ROOT/releases/$R4_SHA"
ck s3a_identity_still_r4 "$(ops_rid)" "$ID4"
ck s3a_service_alive "$(pub_ok)" 200
ck s3a_emergency_not_called "$(wc -l < "$ROOT/state/emergency.log" 2>/dev/null || echo 0)" 0

echo "=== 8) 场景 S3b：旧进程已停且新进程起不来 —— 只有此时才允许关站 ==="
line_to "$C3_SHA"
meta_write upgrade "$C3_SHA" "$ID3" ""
CUT_MODE=upgrade RESTART_CMD="$ROOT/bin/restart-kill-fail.sh"; export CUT_MODE RESTART_CMD
RC=$(run_cutover s3b-kill-then-fail)
S3B=$(cat "$B/s3b-kill-then-fail.log")
ck s3b_exit "$RC" 1
has s3b_closed "$S3B" 'CUTOVER=FAILED_RESTART_AND_CLOSED'
ck s3b_emergency_once "$(wc -l < "$ROOT/state/emergency.log")" 1
start_app || { echo "FAIL 现场恢复失败"; tail -20 "$ROOT/run/app.log"; exit 1; }
ck s3b_recovered_service "$(pub_ok)" 200

echo "=== 9) 场景 S4：回滚到上一版（两把钥匙），并核实真实恢复状态 ==="
meta_write rollback "$PREV_SHA" "$IDP" "$PREV_SHA"
CUT_MODE=rollback CUT_ROLLBACK_TO="$PREV_SHA" RESTART_CMD="$ROOT/bin/restart.sh"; export CUT_MODE CUT_ROLLBACK_TO RESTART_CMD
RC=$(run_cutover s4-rollback)
S4=$(cat "$B/s4-rollback.log")
ck s4_exit "$RC" 0
has s4_ok_token "$S4" 'CUTOVER=OK'
ck s4_current "$(readlink "$ROOT/current")" "$ROOT/releases/$PREV_SHA"
ck s4_runtime_identity "$(ops_rid)" "$IDP"
ck s4_root_back_to_login "$(code http://127.0.0.1:3200/ "$B/prev-root")" 302
ck s4_meta_release_id "$(grep '^release_id=' "$ROOT/state/approved-meta.txt" | cut -d= -f2)" "$IDP"
REC=$(ls -t "$ROOT"/state/cutover-*.txt | head -1)
ck s4_receipt_status "$(grep '^status=' "$REC" | cut -d= -f2)" OK
ck s4_receipt_target_id "$(grep '^target_release_id=' "$REC" | cut -d= -f2)" "$IDP"
ck s4_service_alive "$(pub_ok)" 200

echo "=== 9b) 场景 S9：退回无身份的旧版（带外通道，两把钥匙） ==="
# 线上此刻是上一版（有身份，PREV）；唯一"无身份"的目标是生产基线 BASE。
# 标准 cutover 不允许把无身份版本当回滚目标，这里演练的是那条被显式隔离的带外通道。
: > "$ROOT/state/emergency.log"
PRE_E_PID=$(ops_pid)
WS_ALLOW_IDENTITYLESS_ROLLBACK=yes WS_ROOT="$ROOT" WS_TARGET_SHA="$BASE_SHA" \
WS_RESTART_CMD="$ROOT/bin/restart.sh" WS_PUBLIC_PORT=3200 WS_OPS_PORT=3201 \
  bash "$REL4/docs/v2/release-c500f3d/emergency-rollback-identityless.sh" > "$B/s9-emergency.log" 2>&1
RC=$?; S9=$(cat "$B/s9-emergency.log")
ck s9_exit "$RC" 0
has s9_ok "$S9" 'EMERGENCY_ROLLBACK=OK'
ck s9_current "$(readlink "$ROOT/current")" "$ROOT/releases/$BASE_SHA"
ck s9_root_back_to_login "$(code http://127.0.0.1:3200/ "$B/s9-root")" 302
ck s9_identity_absent "$(ops_rid)" ""
ck s9_service_alive "$(pub_ok)" 200
ck s9_pid_changed "$([ "$(ops_pid)" != "$PRE_E_PID" ] && echo changed || echo same)" changed
ck s9_approved_sha "$(cat "$ROOT/state/approved-sha")" "$BASE_SHA"
ck s9_meta_mode "$(grep '^mode=' "$ROOT/state/approved-meta.txt" | cut -d= -f2)" "emergency-rollback"
ck s9_meta_identity_unidentified "$(grep '^release_id=' "$ROOT/state/approved-meta.txt" | cut -d= -f2)" "unidentified"
EREC=$(ls -t "$ROOT"/state/emergency-rollback-*.txt | head -1)
ck s9_receipt_status "$(grep '^status=' "$EREC" | cut -d= -f2)" OK
ck s9_receipt_identity_verified "$(grep '^identity_verified=' "$EREC" | cut -d= -f2)" no
ck s9_receipt_from_id "$(grep '^from_release_id=' "$EREC" | cut -d= -f2)" "$IDP"
ck s9_receipt_target_id "$(grep '^target_release_id=' "$EREC" | cut -d= -f2)" unidentified
ck s9_emergency_close_not_called "$(wc -l < "$ROOT/state/emergency.log")" 0
# 第二把钥匙缺失时必须拒绝（负向样本，证明这条通道不是谁都能顺手开）
RC2=$(WS_ROOT="$ROOT" WS_TARGET_SHA="$BASE_SHA" WS_RESTART_CMD="$ROOT/bin/restart.sh" \
  bash "$REL4/docs/v2/release-c500f3d/emergency-rollback-identityless.sh" > "$B/s9-no-key.log" 2>&1; echo $?)
ck s9_no_key_exit "$RC2" 3
has s9_no_key_token "$(cat "$B/s9-no-key.log")" 'EMERGENCY_ROLLBACK=ABORT_SECOND_KEY_MISSING'
ck s9_no_key_current_unchanged "$(readlink "$ROOT/current")" "$ROOT/releases/$BASE_SHA"

echo "=== 9c) 场景 S10：从无身份旧版正常前进回集成候选（cutover 仍是唯一前进通道） ==="
line_to "$R4_SHA"; meta_write upgrade "$R4_SHA" "$ID4" ""
CUT_MODE=upgrade CUT_ROLLBACK_TO=""; export CUT_MODE CUT_ROLLBACK_TO
RC=$(run_cutover s10-reforward); S10=$(cat "$B/s10-reforward.log")
ck s10_exit "$RC" 0
has s10_ok "$S10" 'CUTOVER=OK'
ck s10_current "$(readlink "$ROOT/current")" "$ROOT/releases/$R4_SHA"
ck s10_identity "$(ops_rid)" "$ID4"
ck s10_root_is_facade "$(code http://127.0.0.1:3200/ "$B/s10-root")" 200

echo "=== 9d) 发布身份机制复审（真运行进程 + 真核验器） ==="
WS_TREE=/srv/trees/r4 WS_TOOL="$REL4/docs/v2/release-c500f3d" \
WS_BASE=/srv/trees/base WS_PREV=/srv/trees/prev \
WS_ROOT="$ROOT" WS_OPS_PORT=3201 \
  bash "$REL4/docs/v2/release-c500f3d/prelaunch-identity-audit.sh" > "$B/identity_audit.log" 2>&1
RC=$?
ck identity_audit_exit "$RC" 0
has identity_audit_verdict "$(tail -3 "$B/identity_audit.log" | tr '\n' ' ')" 'IDENTITY_AUDIT=PASS'

echo "=== 10) 停应用，跑 R3 四套装置与首页回归（同一容器、同一棵树） ==="
stop_app
cd "$REL4/docs/v2/release-c500f3d" || { echo "FAIL 找不到工具目录"; exit 1; }

suite() { # <名字> <期望 token> <命令...>
  local name=$1 want=$2; shift 2
  "$@" > "$B/$name.log" 2>&1; local rc=$?
  local tailtxt; tailtxt=$(tail -3 "$B/$name.log" | tr '\n' ' ')
  ck "$name exit" "$rc" 0
  has "$name verdict" "$tailtxt" "$want"
  echo "  ↳ $tailtxt"
}
suite r3_tooling 'RELEASE_TOOLING_SELFTEST=PASS' bash release-tooling-selftest.sh
suite r3_ops 'OPS_SELFTEST=PASS' bash ops-selftest.sh
suite r3_real_app_it 'REAL_APP_IDENTITY_IT=PASS' bash -c "REL='$REL4' bash '$REL4/docs/v2/release-c500f3d/real-app-identity-it.sh'"
TOOL_BASELINE=/srv/trees/r3base/docs/v2/release-c500f3d TOOL_CANDIDATE="$REL4/docs/v2/release-c500f3d" \
  suite r3_baseline_red 'R3_BASELINE_RED_PROBES=PASS' bash r3-baseline-red-probes.sh
suite repo_regression 'REPO_REGRESSION=PASS' bash prelaunch-repo-regression.sh "$REL4"
# 首页自身回归（PR #33 自带；不需要浏览器）
cd "$REL4" || exit 1
node eval/public-entry-selftest.mjs > "$B/public_entry_selftest.log" 2>&1; RC=$?
ck public_entry_selftest_exit "$RC" 0
ck public_entry_selftest_zero_fail "$(grep -c '✗' "$B/public_entry_selftest.log")" 0
node eval/auth-selftest.mjs > "$B/auth_selftest.log" 2>&1; RC=$?
ck auth_selftest_exit "$RC" 0
echo "  ↳ auth-selftest: $(tail -1 "$B/auth_selftest.log")"

echo
echo "R4_ACCEPTANCE_TOTAL=$N  FAILS=$F"
[ "$F" -eq 0 ] && echo "R4_ACCEPTANCE=PASS" || echo "R4_ACCEPTANCE=FAIL"
exit "$F"
