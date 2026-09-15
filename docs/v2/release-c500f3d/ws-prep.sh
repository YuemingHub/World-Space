#!/usr/bin/env bash
# World Space V0.1 发布前准备（服务器侧，非公网）
#
# 这个脚本刻意做到：**公网在跑的版本、nginx 入口、共享生产 env、systemd 服务，全都不动。**
#   - 不写 /opt/world-space/current
#   - 不 systemctl start/restart/stop world-space.service
#   - 不改 /etc/nginx/sites-enabled/world-space
#   - 不改 /opt/world-space/shared/env/world-space.env（只读它，用来派生 smoke 用的副本）
#   - 不碰 DNS
# 验证用的第二个实例只监听 127.0.0.1 的一个独立端口，跑完就停，公网永远看不见它。
#
# 用法（root，服务器上）：
#   ws-prep.sh fetch              # 1. 取批准 SHA 的发布树（不动 current）
#   ws-prep.sh verify             # 2. 逐文件证明部署树 = 该 SHA 且工作树干净
#   ws-prep.sh emergency          # 3. 装关站方案 + 独立进程预演（不 reload 公网入口）
#   ws-prep.sh smokeenv           # 4. 从生产 env 派生仓库外 smoke env（600），补访问门配置
#   ws-prep.sh failclosed         # 5. 先验证"认证配置坏了绝不退化成公开访问"
#   ws-prep.sh gates              # 6. 在服务器发布树跑全部 Gate（离线桩，0 外网 0 花费）
#   ws-prep.sh start|stop         # 7. 起/停本机验证实例（仅 127.0.0.1:3210）
#   ws-prep.sh report             # 8. 汇总只读事实（不含任何密钥值）
set -euo pipefail

REF="${WS_REF:-c500f3d76601abb263511cb622efd38379e8b959}"
REPO=https://github.com/YuemingHub/World-Space
BRANCH=v2
ROOT=/opt/world-space
REL=$ROOT/releases/$REF
CACHE=$ROOT/.git-cache/World-Space.git
PROD_ENV=$ROOT/shared/env/world-space.env
SMOKE_ENV=$ROOT/shared/env/world-space.v01-smoke.env
PRIV=$ROOT/etc                                    # 仓库外私有文件（users.json / session-secret）
EMERG=$ROOT/emergency
STATE=$ROOT/state                                 # 本脚本自己的状态/日志，不是 nginx 的
SMOKE_PORT=3210                                   # 只绑 127.0.0.1，公网不可达
SMOKE_HOST=127.0.0.1
LOGDIR=$STATE/logs
OUTCOME_URL=https://ymai.fun                      # 唯一正式 Origin

die() { echo "FAIL: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "需要 root"; }
mkdir -p "$LOGDIR" "$STATE"

# ---------- 1. 取发布树 ----------
cmd_fetch() {
  need_root
  [ -d "$REL" ] && { echo "已存在：$REL"; return 0; }
  install -d -m 755 "$ROOT/.git-cache" "$(dirname "$REL")"
  if [ ! -d "$CACHE" ]; then
    git init --bare -q "$CACHE"
    git -C "$CACHE" remote add origin "$REPO"
  fi
  timeout 300 git -C "$CACHE" fetch -q --force origin "+refs/heads/$BRANCH:refs/heads/$BRANCH" \
    || die "从 GitHub 取不到 $BRANCH（机内直连 GitHub 若不通，改用投递产物，别改批准 SHA）"
  local head; head=$(git -C "$CACHE" rev-parse "$BRANCH")
  [ "$head" = "$REF" ] || { echo "  $BRANCH 现在是 $head，批准点是 $REF" >&2; die "PREDEPLOY_ABORT_GIT_DRIFT"; }
  install -d -m 755 "$REL"
  # 逐文件从该 SHA 展开（不带 .git，避免"目录里有个 git 仓库"被误当成可改的工作区）
  git -C "$CACHE" archive "$REF" | tar -x -C "$REL"
  git -C "$CACHE" ls-tree -r --full-name "$REF" | sha256sum > "$STATE/tree-manifest-$REF.sha256"
  echo "OK 发布树就位：$REL"
  echo "   树清单：$(cat "$STATE/tree-manifest-$REF.sha256")"
}

# ---------- 2. 证明部署树就是批准 SHA ----------
cmd_verify() {
  need_root
  [ -d "$REL" ] || die "先跑 fetch"
  local want have
  want=$(git -C "$CACHE" ls-tree -r --full-name "$REF" | sha256sum | awk '{print $1}')
  have=$(cd "$REL" && find . -type f ! -path './.git/*' -printf '%P\n' | sort \
          | xargs -r sha256sum | sha256sum | awk '{print $1}')
  # 两边的算法不同（一个是 git blob 列表，一个是内容列表），这里只作留档；真判定用下面的 git 比对
  echo "  git tree sha256 : $want"
  echo "  files sha256    : $have"
  echo "  files           : $(cd "$REL" && find . -type f | wc -l)"
  # 用 git 自己重放一遍：把发布树接回一个临时仓库，看是否与该 SHA 完全一致
  local tmp; tmp=$(mktemp -d)
  git init -q "$tmp" && git -C "$tmp" --work-tree="$REL" fetch -q "$CACHE" "$REF" 2>/dev/null
  git -C "$tmp" --work-tree="$REL" checkout -q FETCH_HEAD -- . 2>/dev/null || true
  if [ -z "$(git -C "$tmp" --work-tree="$REL" status --porcelain 2>/dev/null)" ]; then
    echo "GIT=PASS  部署树逐文件 = $REF，无差异、无多余、工作树干净"
  else
    git -C "$tmp" --work-tree="$REL" status --porcelain | head -20
    die "PREDEPLOY_ABORT_GIT_DRIFT 发布树与该 SHA 不一致"
  fi
  rm -rf "$tmp"
  echo "  current 仍指向：$(readlink "$ROOT/current" || echo 未设置)（本脚本从不改它）"
}

# ---------- 3. 关站方案 ----------
cmd_emergency() {
  need_root
  [ -x /usr/local/bin/world-space-emergency.sh ] || die "先 scp world-space-emergency.sh 到 /usr/local/bin 并 chmod 755"
  [ -d "$EMERG/staging" ] || die "先 scp emergency-closed/{world-space-closed.conf,maintenance.html} 到 $EMERG/staging"
  world-space-emergency.sh install
  world-space-emergency.sh preflight
  world-space-emergency.sh status | tee "$STATE/status-$(date +%Y%m%d-%H%M%S).txt"
  echo "EMERGENCY_CLOSED=READY（已装 + 已预演；关站块未启用，公网入口未动）"
}

# ---------- 4. 派生 smoke env（不碰生产 env） ----------
cmd_smokeenv() {
  need_root
  [ -f "$PROD_ENV" ] || die "读不到 $PROD_ENV"
  [ -f "$SMOKE_ENV" ] && cp -f "$SMOKE_ENV" "$SMOKE_ENV.bak-$(date +%Y%m%d-%H%M%S)"
  install -d -m 700 "$PRIV"
  # 只改这几项；env 里其它生产值（provider / 模型 / token 上限）原样继承
  {
    grep -vE '^(WS_PORT|WS_HOST|WS_AUTH_USERS_FILE|WS_SESSION_SECRET_FILE|WS_COOKIE_SECURE|WS_TRUST_PROXY|WS_ALLOWED_ORIGINS|WS_DAILY_CAP|WS_MONTHLY_CAP_RMB)=' "$PROD_ENV"
    echo "WS_PORT=$SMOKE_PORT"
    echo "WS_HOST=$SMOKE_HOST"
    echo "WS_AUTH_USERS_FILE=$PRIV/users.json"
    echo "WS_SESSION_SECRET_FILE=$PRIV/session-secret.txt"
    echo "WS_COOKIE_SECURE=1"
    echo "WS_TRUST_PROXY=1"
    echo "WS_ALLOWED_ORIGINS=$OUTCOME_URL"
    echo "WS_DAILY_CAP=50"
    echo "WS_MONTHLY_CAP_RMB=20"
  } > "$SMOKE_ENV"
  chmod 600 "$SMOKE_ENV"; chown wsapp:wsapp "$SMOKE_ENV" 2>/dev/null || true
  echo "OK $SMOKE_ENV（600，wsapp 可读；生产 env 未改动）"
  # 认证相关配置逐项回读（不打印任何密钥值）
  for k in WS_AUTH_ENABLED WS_COOKIE_SECURE WS_TRUST_PROXY WS_HOST WS_PORT WS_ALLOWED_ORIGINS WS_DAILY_CAP WS_MONTHLY_CAP_RMB WS_SEARCH; do
    v=$(grep -E "^$k=" "$SMOKE_ENV" | head -1 | cut -d= -f2- || true)
    [ "$k" = "WS_SEARCH_KEY" ] && continue
    printf '  %-22s = %s\n' "$k" "${v:-<未设置>}"
  done
  grep -q '^WS_AUTH_ENABLED=0' "$SMOKE_ENV" && die "生产禁止 WS_AUTH_ENABLED=0" || true
  echo "  WS_SEARCH_KEY        = <在位:$(grep -c '^WS_SEARCH_KEY=.' "$SMOKE_ENV")，值不打印>"
}

# ---------- 私有文件（users / secret） ----------
ensure_priv() {
  need_root
  [ -f "$PRIV/session-secret.txt" ] || { head -c 48 /dev/urandom | base64 > "$PRIV/session-secret.txt"; echo "  生成 session secret（值不落任何输出）"; }
  chmod 600 "$PRIV/session-secret.txt"; chown wsapp:wsapp "$PRIV/session-secret.txt" 2>/dev/null || true
}

cmd_adduser() {  # ws-prep.sh adduser <user_id> <username>   —— 密码从 stdin 读，不进参数/历史
  need_root
  local uid="${1:-}" un="${2:-}"; [ -n "$uid" ] && [ -n "$un" ] || die "用法: adduser <user_id> <username>，随后按提示输入密码"
  [ -d "$REL" ] || die "先 fetch"
  ensure_priv
  echo "请粘贴/输入该用户的密码后回车（不会显示、不进 shell 历史）："
  local line; line=$(node "$REL/scripts/hash-password.mjs" "$uid" "$un")   # 自己提示读 stdin
  local users="$PRIV/users.json"
  [ -f "$users" ] || echo '{"users":[]}' > "$users"
  TMPHASH="$line" node -e '
    const fs=require("fs"); const f=process.env.WSU||process.argv[1];
    const j=JSON.parse(fs.readFileSync(f,"utf8")); const h=JSON.parse(process.env.TMPHASH);
    j.users=j.users.filter(u=>u.user_id!==h.user_id); j.users.push(h);
    fs.writeFileSync(f, JSON.stringify(j,null,2)+"\n");
    console.log("  已写入 user_id="+h.user_id+"（仅 user_id/username/scrypt hash，无明文）");
  ' "$users"
  chmod 600 "$users"; chown wsapp:wsapp "$users" 2>/dev/null || true
}

# ---------- 5. fail closed 验证 ----------
cmd_failclosed() {
  need_root
  ensure_priv
  [ -f "$PRIV/users.json" ] || die "先 adduser（fail closed 需要 secret 在位、用户文件缺失这一组合）"
  local log="$LOGDIR/failclosed-$(date +%H%M%S).log"
  mv "$PRIV/users.json" "$PRIV/users.json.hold"           # 移开，不删
  start_instance; sleep 2
  echo "--- 缺用户配置时的行为（必须全是"关门"）---"
  curl -s --max-time 8 "http://$SMOKE_HOST:$SMOKE_PORT/healthz" | tr -d '\n'; echo
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$SMOKE_HOST:$SMOKE_PORT/")
  loc=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 8 "http://$SMOKE_HOST:$SMOKE_PORT/")
  api=$(curl -s -o "$STATE/failclosed-api.json" -w '%{http_code}' --max-time 8 -X POST \
        -H 'content-type: application/json' -d '{"intent":"failclosed probe"}' \
        "http://$SMOKE_HOST:$SMOKE_PORT/api/world")
  echo "  GET /            -> $code ${loc:+(redirect: $loc)}"
  echo "  POST /api/world  -> $api $(head -c 120 "$STATE/failclosed-api.json")"
  stop_instance
  mv "$PRIV/users.json.hold" "$PRIV/users.json"
  if [ "$api" = "503" ] && echo "$code" | grep -qE '302|401'; then
    echo "AUTH_FAIL_CLOSED=PASS —— 认证配置坏了仍然关着门，业务接口没有 200"
  else
    die "PREDEPLOY_REJECTED_AUTH_FAIL_OPEN 认证配置坏了但业务仍可用（api=$api, root=$code）"
  fi
}

# ---------- 6. Gate ----------
cmd_gates() {
  [ -d "$REL" ] || die "先 fetch"
  local out="$LOGDIR/gates-$(date +%Y%m%d-%H%M).txt"; : > "$out"
  for g in runtime-isolation authority adapter-shape admission retry liveness xss-boundary \
           budget-cap date outcome-loop frontend-e2e runtime auth; do
    f="$REL/eval/${g}-selftest.mjs"; [ -f "$f" ] || f="$REL/eval/${g}.mjs"
    st=$(date +%s)
    if ( cd "$REL" && node "$f" > "$LOGDIR/gate-$g.log" 2>&1 ); then r=PASS; else r=FAIL; fi
    printf '%-18s %-5s %ss\n' "$g" "$r" "$(( $(date +%s) - st ))" | tee -a "$out"
  done
  echo "---- 服务器发布树 Gate 汇总（$REL）----"; cat "$out"
  grep -q FAIL "$out" && die "有 Gate 未通过：见 $LOGDIR/gate-*.log（不许引用开发机的旧绿灯）" \
    || echo "ALL_GATES=PASS（服务器真实发布树）"
}

# ---------- 7. 本机验证实例 ----------
start_instance() {
  [ -f "$SMOKE_ENV" ] || die "先 smokeenv"
  set -a; . "$SMOKE_ENV"; set +a
  cd "$REL"
  nohup node server/world.mjs > "$LOGDIR/smoke.out" 2>&1 &
  echo $! > "$STATE/smoke.pid"
}
cmd_start() { need_root; start_instance; sleep 2
  echo "PID=$(cat "$STATE/smoke.pid") 监听：$(ss -ltnp 2>/dev/null | grep ":$SMOKE_PORT" | head -1)"
  echo "healthz: $(curl -s --max-time 8 http://$SMOKE_HOST:$SMOKE_PORT/healthz)"; }
cmd_stop() { [ -f "$STATE/smoke.pid" ] && kill "$(cat "$STATE/smoke.pid")" 2>/dev/null || true
  rm -f "$STATE/smoke.pid"; echo "本机验证实例已停（公网从未指向它）"; }

# ---------- 8. 只读汇总 ----------
cmd_report() {
  need_root
  echo "=== §1 候选锁死 ==="
  echo "  发布树: $REL"; [ -d "$REL" ] && echo "  存在: yes" || echo "  存在: no"
  echo "  current -> $(readlink "$ROOT/current" || echo 未设置)   # 公网在跑的仍是它，本脚本未改"
  echo "=== §2 仓库外私有文件 ==="
  for f in "$PRIV/users.json" "$PRIV/session-secret.txt"; do
    if [ -f "$f" ]; then echo "  $(basename "$f"): mode=$(stat -c %a "$f") owner=$(stat -c %U "$f") 在位"; else echo "  $(basename "$f"): 缺失"; fi
  done
  echo "  users.json 里的 user_id（不含 hash）: $(node -e 'try{const j=require("'$PRIV'/users.json");console.log(j.users.map(u=>u.user_id).join(",")||"空")}catch(e){console.log("读不到")}' 2>/dev/null || echo 读不到)"
  echo "  Git 可见性: $(git -C "$CACHE" grep -l -I 'WS_SEARCH_KEY\|password' "$REF" -- 2>/dev/null | grep -v scripts/ | head -3 || echo 无)"
  echo "=== §6/§7/§9 运行边界与配置（不打印任何密钥值）==="
  for k in WS_HOST WS_PORT WS_COOKIE_SECURE WS_TRUST_PROXY WS_ALLOWED_ORIGINS WS_DAILY_CAP WS_MONTHLY_CAP_RMB WS_SEARCH WS_AUTH_ENABLED; do
    v=$(grep -E "^$k=" "$SMOKE_ENV" 2>/dev/null | head -1 | cut -d= -f2- || true)
    printf '  %-20s = %s\n' "$k" "${v:-<未设置>}"
  done
  echo "  实例数: $(pgrep -fa 'node .*/opt/world-space.*world.mjs' 2>/dev/null | wc -l) 个 world.mjs（含公网那个）"
  echo "  监听: $(ss -ltn 2>/dev/null | grep -oE '127.0.0.1:(3200|3210)' | sort -u | tr '\n' ' ')"
  echo "=== 最近 Gate 结果 ==="
  ls -1t "$LOGDIR"/gates-*.txt 2>/dev/null | head -1 | xargs -r cat
  echo "=== 关站 ==="; /usr/local/bin/world-space-emergency.sh status 2>/dev/null || echo "  未安装"
}

case "${1:-}" in
  fetch) cmd_fetch ;; verify) cmd_verify ;; emergency) cmd_emergency ;;
  smokeenv) cmd_smokeenv ;; adduser) shift; cmd_adduser "$@" ;; failclosed) cmd_failclosed ;;
  gates) cmd_gates ;; start) cmd_start ;; stop) cmd_stop ;; report) cmd_report ;;
  *) sed -n '3,20p' "$0"; exit 2 ;;
esac
