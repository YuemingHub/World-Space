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
# 候选版本必须显式指定（2026-11-01 收紧 P0-B）：
#   本脚本不再有任何默认版本。WS_REF 必须是完整的 40 位提交号，且必须能通过发布身份验证：
#   解析成同一个提交、发布线（refs/heads/v2）在它的历史里、不是 legacy 单面、发布目录逐文件等于
#   该提交的树、并且相对当前线上版本是前进而不是回退。任何一步不成立 → 零写入 + 明确报错。
#   旧版本只能走显式回滚：WS_MODE=rollback WS_ROLLBACK_TO=<sha> WS_REF=<同一个 sha>。
#
# 用法（root，服务器上）：
#   WS_REF=<40位候选> ws-prep.sh fetch       # 1. 取批准 SHA 的发布树（不动 current）
#   WS_REF=<40位候选> ws-prep.sh verify      # 2. 逐文件证明部署树 = 该 SHA，并登记批准点
#   WS_MODE=rollback WS_ROLLBACK_TO=<sha> WS_REF=<sha> ws-prep.sh fetch|verify   # 显式回滚
#   ws-prep.sh emergency          # 3. 装关站方案 + 独立进程预演（不 reload 公网入口）
#   ws-prep.sh smokeenv           # 4. 从生产 env 派生仓库外 smoke env（600），补访问门配置
#   ws-prep.sh failclosed         # 5. 先验证"认证配置坏了绝不退化成公开访问"
#   ws-prep.sh gates              # 6. 在服务器发布树跑全部 Gate（离线桩，0 外网 0 花费）
#   ws-prep.sh start|stop         # 7. 起/停本机验证实例（仅 127.0.0.1:3210）
#   ws-prep.sh report             # 8. 汇总只读事实（不含任何密钥值）
set -euo pipefail
# 只用真实对象关系判断祖先：replace refs 可以在缓存里伪造"谁是谁的祖先"
export GIT_NO_REPLACE_OBJECTS=1

ROOT="${WS_ROOT:-/opt/world-space}"
REPO="${WS_REPO:-https://github.com/YuemingHub/World-Space}"
BRANCH="${WS_BRANCH:-v2}"                         # 发布线：升级候选必须包含它的最新提交
REF="${WS_REF:-}"                                 # 必须显式给出，不做任何默认
MODE="${WS_MODE:-upgrade}"                        # upgrade | rollback
ROLLBACK_TO="${WS_ROLLBACK_TO:-}"                 # 回滚的第二把钥匙
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

die() { echo "FAIL: $*" >&2; exit "${2:-1}"; }
need_root() { [ "$(id -u)" = 0 ] || die "需要 root" 2; }
ensure_dirs() { mkdir -p "$LOGDIR" "$STATE"; }

need_ref() { # 零写入的第一道闸：没有显式候选就什么都不做
  case "$REF" in
    ''|*[!0-9a-f]*) die "PREDEPLOY_ABORT_TARGET_REQUIRED 必须显式给出 WS_REF=<40 位提交号>（本脚本不再默认任何旧版本）" 2 ;;
  esac
  [ "${#REF}" -eq 40 ] || die "PREDEPLOY_ABORT_TARGET_INVALID WS_REF 不是完整 40 位提交号：$REF" 2
}

check_mode() {
  case "$MODE" in
    upgrade|rollback) ;;
    *) die "PREDEPLOY_ABORT_MODE_INVALID WS_MODE=$MODE（只认 upgrade 或 rollback）" 2 ;;
  esac
}

policy_abort() { echo "FAIL: PREDEPLOY_ABORT_$1  $2" >&2; exit 2; }

face_of_commit() {
  local n
  n=$(git -C "$CACHE" cat-file blob "$1:server/world.mjs" 2>/dev/null | grep -c 'opsPort' || true)
  [ "${n:-0}" -gt 0 ] && printf 'dual_face' || printf 'legacy_single_face'
}

facade_of_commit() { # none | valid | invalid
  local size blob
  size=$(git -C "$CACHE" cat-file -s "$1:web/v2/public/index.html" 2>/dev/null) || { printf 'none'; return; }
  [ "${size:-0}" -ge 8000 ] || { printf 'invalid'; return; }
  blob=$(git -C "$CACHE" cat-file blob "$1:web/v2/public/index.html" 2>/dev/null) || { printf 'invalid'; return; }
  printf '%s' "$blob" | grep -q '你想做什么事' || { printf 'invalid'; return; }
  printf '%s' "$blob" | grep -q 'id="btn-write"'  || { printf 'invalid'; return; }
  printf '%s' "$blob" | grep -q '</html>'          || { printf 'invalid'; return; }
  printf 'valid'
}

is_ancestor() { git -C "$CACHE" merge-base --is-ancestor "$1" "$2" 2>/dev/null; }

# 发布身份与策略验证（只读）。所有"未知/回退/越线/形状不符"都在这里停下，调用方不得先写后验。
verify_target_policy() {
  local ref=$1 live live_sha face facade
  [ -d "$CACHE" ] || policy_abort GIT_CACHE_MISSING "本机 git 缓存不在位（$CACHE）"
  git -C "$CACHE" cat-file -e "$ref^{commit}" 2>/dev/null \
    || policy_abort TARGET_IDENTITY_UNKNOWN "WS_REF=$ref 在缓存里解析不到（未知版本不许登记）"
  [ "$(git -C "$CACHE" rev-parse "$ref^{commit}" 2>/dev/null)" = "$ref" ] \
    || policy_abort TARGET_IDENTITY_MISMATCH "WS_REF=$ref 解析成了另一个提交"
  git -C "$CACHE" cat-file -e "$ref:server/world.mjs" 2>/dev/null \
    || policy_abort TARGET_NOT_A_RELEASE "该提交里没有 server/world.mjs，不是 World Space 发布树"
  face=$(face_of_commit "$ref")
  facade=$(facade_of_commit "$ref")
  [ "$facade" = invalid ] && policy_abort FACADE_INVALID "目标树里的 web/v2/public/index.html 存在但不是完整门面（<8000 字节或缺物证）"

  live=$(readlink "$ROOT/current" 2>/dev/null || true)
  live_sha=""
  [ -n "$live" ] && live_sha=$(basename "$live")
  if [ -n "$live_sha" ]; then
    git -C "$CACHE" cat-file -e "$live_sha^{commit}" 2>/dev/null \
      || policy_abort LIVE_IDENTITY_UNKNOWN "当前线上版本 $live_sha 在缓存里解析不到，无法判断前后代关系"
  elif [ "$MODE" = upgrade ]; then
    policy_abort LIVE_IDENTITY_UNKNOWN "没有可识别的 current（$ROOT/current 不存在或不是符号链接），升级无法判断这是不是一次前进"
  fi

  if [ "$MODE" = upgrade ]; then
    [ "$face" = legacy_single_face ] && policy_abort LEGACY_AS_UPGRADE "升级路径不接受 legacy 单面旧版；回滚旧版必须显式 WS_MODE=rollback + WS_ROLLBACK_TO"
    git -C "$CACHE" rev-parse --verify -q "refs/heads/$BRANCH^{commit}" >/dev/null 2>&1 \
      || policy_abort RELEASE_LINE_UNKNOWN "缓存里没有发布线 refs/heads/$BRANCH，无法判断候选是否在发布线上"
    is_ancestor "refs/heads/$BRANCH" "$ref" \
      || policy_abort NOT_IN_RELEASE_LINE "候选 $ref 不包含发布线 $BRANCH 的最新提交（不在预期发布线上）"
    if [ -n "$live_sha" ]; then
      [ "$live_sha" = "$ref" ] && policy_abort ALREADY_LIVE "候选就是当前线上版本，无需准备"
      is_ancestor "$live_sha" "$ref" || policy_abort VERSION_REGRESSION "候选不是当前线上版本的后代（版本回退或分叉）"
    fi
  else
    [ -n "$ROLLBACK_TO" ] || policy_abort ROLLBACK_TARGET_REQUIRED "回滚必须显式给出 WS_ROLLBACK_TO=<40 位提交号>（第二把钥匙）"
    [ "$ROLLBACK_TO" = "$ref" ] || policy_abort ROLLBACK_TARGET_MISMATCH "WS_ROLLBACK_TO=$ROLLBACK_TO 与 WS_REF=$ref 不一致"
    [ -n "$live_sha" ] || policy_abort ROLLBACK_NO_LIVE "没有 current，无法判断要回滚到哪个版本之前"
    [ "$live_sha" = "$ref" ] && policy_abort ALREADY_LIVE "候选就是当前线上版本，无需回滚"
    is_ancestor "$ref" "$live_sha" || policy_abort ROLLBACK_NOT_ANCESTOR "回滚目标 $ref 不是当前线上版本 $live_sha 的祖先（这不是往回走）"
    echo "  WARN: 回滚路径：允许登记旧版（${face}），这是显式授权且可留档的路径。"
  fi
}

# ---------- 1. 取发布树 ----------
cmd_fetch() {
  need_root
  need_ref
  check_mode
  [ -d "$ROOT" ] || die "PREDEPLOY_ABORT_ROOT_MISSING $ROOT 不存在" 2
  install -d -m 755 "$ROOT/.git-cache"
  if [ ! -d "$CACHE" ]; then
    git init --bare -q "$CACHE"
    git -C "$CACHE" remote add origin "$REPO"
  fi
  # 先取全部分支（发布线、当前线上版本、候选通常都在上面）；远端不支持时退回按提交号直接取。
  if ! timeout 300 git -C "$CACHE" fetch -q --force origin '+refs/heads/*:refs/heads/*' 2>/dev/null; then
    timeout 300 git -C "$CACHE" fetch -q --force origin "$REF" 2>/dev/null \
      || die "PREDEPLOY_ABORT_FETCH_FAILED 取不到 $REF（远端不可达，或该提交不在任何分支上）" 2
  fi
  git -C "$CACHE" cat-file -e "$REF^{commit}" 2>/dev/null \
    || die "PREDEPLOY_ABORT_TARGET_IDENTITY_UNKNOWN 远端取回来了，但缓存里仍解析不到 $REF" 2
  [ "$(git -C "$CACHE" rev-parse "$REF^{commit}" 2>/dev/null)" = "$REF" ] \
    || die "PREDEPLOY_ABORT_TARGET_IDENTITY_MISMATCH WS_REF=$REF 解析成了另一个提交" 2

  # 身份与策略通过之后才允许写发布树
  verify_target_policy "$REF"
  ensure_dirs
  install -d -m 755 "$(dirname "$REL")"
  if [ -d "$REL" ]; then
    echo "已存在：$REL（不重复展开；verify 会逐文件核对内容）"
    return 0
  fi
  install -d -m 755 "$REL"
  # 逐文件从该 SHA 展开（不带 .git，避免"目录里有个 git 仓库"被误当成可改的工作区）
  git -C "$CACHE" archive "$REF" | tar -x -C "$REL"
  git -C "$CACHE" ls-tree -r --full-name "$REF" | sha256sum > "$STATE/tree-manifest-$REF.sha256"
  echo "OK 发布树就位：$REL"
  echo "   树清单：$(cat "$STATE/tree-manifest-$REF.sha256")"
}

# ---------- 2. 证明部署树就是候选 SHA（只读比对，不往发布树写任何东西） ----------
# 反面教训（本轮真的踩过）：不要对刚 git init、HEAD 还不存在的临时仓库跑 status --porcelain，
# 那会把每个文件都报成 "A"，制造 100% 误报的 GIT_DRIFT；checkout -- . 还会顺手改写发布树。
cmd_verify() {
  need_root
  need_ref
  check_mode
  [ -d "$REL" ]  || die "PREDEPLOY_ABORT_RELEASE_TREE_MISSING 先跑 fetch（$REL 不存在）" 2
  [ -d "$CACHE" ] || die "PREDEPLOY_ABORT_GIT_CACHE_MISSING 与发布树对应的 git 缓存不在位（$CACHE）" 2
  # 先验身份、形状、发布线、前后代关系；不过就退出，批准点一个字都不写
  verify_target_policy "$REF"
  ensure_dirs

  local exp act missing extra scratch
  # 被 gitignore 的运行期暂存：Gate 在发布树里跑自测时会生成 var/、eval/out/ 下的文件
  # （本轮实测多出 var/auth-8951.json）。把它们算进"该 SHA 之外的文件"会让逐文件校验
  # 永远红，校验本身就变成假的——所以显式排除，并报告排除了几个。
  # 但符号链接/特殊文件不能放行：find -type f 看不见链接，运行时会顺着它把树外文件发出去。
  local irregular
  irregular=$(cd "$REL" && find . \( -type l -o \( ! -type f ! -type d \) \) -print 2>/dev/null | head -1)
  [ -z "$irregular" ] || die "PREDEPLOY_ABORT_GIT_DRIFT 发布树含符号链接或特殊文件（$irregular）：只允许普通文件" 2
  if git -C "$CACHE" ls-tree -r "$REF" | awk '$1=="120000"{print $4; exit}' | grep -q .; then
    die "PREDEPLOY_ABORT_GIT_DRIFT 该提交本身含符号链接；发布树只允许普通文件" 2
  fi
  exp=$(git -C "$CACHE" ls-tree -r --name-only "$REF" | sort)
  act=$(cd "$REL" && find . -type f | sed 's|^\./||' | grep -vE '^(var|eval/out)/' | sort)
  scratch=$(cd "$REL" && find . -type f | sed 's|^\./||' | grep -cE '^(var|eval/out)/' || true)
  echo "  运行期暂存（自测生成，不计入比对）：$scratch 个，位于 var/ 与 eval/out/"
  missing=$(comm -23 <(echo "$exp") <(echo "$act"))
  extra=$(comm -13 <(echo "$exp") <(echo "$act"))
  if [ -n "$missing" ]; then echo "  缺文件:"; echo "$missing" | head -20
    die "PREDEPLOY_ABORT_GIT_DRIFT 发布树缺该 SHA 的文件" 2; fi
  if [ -n "$extra" ]; then echo "  多出的文件:"; echo "$extra" | head -20
    die "PREDEPLOY_ABORT_GIT_DRIFT 发布树有该 SHA 之外的文件" 2; fi

  local bad=0 n=0 path sha want have
  while IFS= read -r path; do
    n=$((n+1))
    sha=$(git -C "$CACHE" rev-parse "$REF:$path" 2>/dev/null) || { echo "  取不到 blob: $path"; bad=$((bad+1)); continue; }
    want=$(git -C "$CACHE" cat-file blob "$sha" | sha256sum | awk '{print $1}')
    have=$(sha256sum "$REL/$path" | awk '{print $1}')
    [ "$want" = "$have" ] || { echo "  内容不一致: $path"; bad=$((bad+1)); }
  done <<< "$exp"
  [ "$bad" = 0 ] || die "PREDEPLOY_ABORT_GIT_DRIFT $bad 个文件内容与 $REF 不一致" 2

  # 全部通过之后才登记批准点（原子写：读者永远看不到半个 SHA）
  local tmp="$STATE/.approved-sha.tmp.$$"
  printf '%s\n' "$REF" > "$tmp" && mv -f "$tmp" "$STATE/approved-sha"
  echo "  批准点已登记：$STATE/approved-sha = $REF（路径 $MODE$([ "$MODE" = rollback ] && echo " → $ROLLBACK_TO")）"
  echo "GIT=PASS  发布树 $n 个文件逐内容与 $REF 相同，无缺失、无多余（只读比对，未写发布树）"
  echo "  树清单留档：$(cat "$STATE/tree-manifest-$REF.sha256" 2>/dev/null || echo 无)"
  echo "  current 仍指向：$(readlink "$ROOT/current" || echo 未设置)（本脚本从不改它）"
}

# ---------- 3. 关站方案 ----------
cmd_emergency() {
  need_root
  ensure_dirs
  [ -x /usr/local/bin/world-space-emergency.sh ] || die "先 scp world-space-emergency.sh 到 /usr/local/bin 并 chmod 755" 2
  [ -d "$EMERG/staging" ] || die "先 scp emergency-closed/{world-space-closed.conf,maintenance.html} 到 $EMERG/staging" 2
  world-space-emergency.sh install
  world-space-emergency.sh preflight
  world-space-emergency.sh status | tee "$STATE/status-$(date +%Y%m%d-%H%M%S).txt"
  echo "EMERGENCY_CLOSED=READY（已装 + 已预演；关站块未启用，公网入口未动）"
}

# ---------- 4. 派生 smoke env（不碰生产 env） ----------
cmd_smokeenv() {
  need_root
  [ -f "$PROD_ENV" ] || die "读不到 $PROD_ENV" 2
  ensure_dirs
  [ -f "$SMOKE_ENV" ] && cp -f "$SMOKE_ENV" "$SMOKE_ENV.bak-$(date +%Y%m%d-%H%M%S)"
  install -d -m 750 -o root -g wsapp "$PRIV"   # 不能写 700：那会让 wsapp 进不了目录读用户文件，直接 auth broken
  # 只改这几项；env 里其它生产值（provider / 模型 / token 上限）原样继承
  {
    grep -vE '^(WS_PORT|WS_HOST|WS_AUTH_USERS_FILE|WS_SESSION_SECRET_FILE|WS_COOKIE_SECURE|WS_TRUST_PROXY|WS_ALLOWED_ORIGINS|WS_DAILY_CAP|WS_MONTHLY_CAP_RMB|WS_STATE_FILE)=' "$PROD_ENV"
    echo "WS_PORT=$SMOKE_PORT"
    echo "WS_HOST=$SMOKE_HOST"
    echo "WS_AUTH_USERS_FILE=$PRIV/users.json"
    echo "WS_SESSION_SECRET_FILE=$PRIV/session-secret.txt"
    echo "WS_COOKIE_SECURE=1"
    echo "WS_TRUST_PROXY=1"
    echo "WS_ALLOWED_ORIGINS=$OUTCOME_URL"
    echo "WS_DAILY_CAP=50"
    echo "WS_MONTHLY_CAP_RMB=20"
    # 预算账本单独一份：公网实例正在读写 shared/data/budget.json，
    # 第二个实例并发写同一文件有覆盖风险——预算是钱，宁可分账也不能写坏生产账本。
    echo "WS_STATE_FILE=$ROOT/shared/data/budget-smoke.json"
  } > "$SMOKE_ENV"
  chmod 600 "$SMOKE_ENV"; chown wsapp:wsapp "$SMOKE_ENV" 2>/dev/null || true
  echo "OK $SMOKE_ENV（600，wsapp 可读；生产 env 未改动）"
  echo "   ⚠️ 本机实例用独立账本 budget-smoke.json；真实月度花费 = 生产账本 + 这份账本"
  # 认证相关配置逐项回读（不打印任何密钥值）
  for k in WS_AUTH_ENABLED WS_COOKIE_SECURE WS_TRUST_PROXY WS_HOST WS_PORT WS_ALLOWED_ORIGINS WS_DAILY_CAP WS_MONTHLY_CAP_RMB WS_SEARCH WS_STATE_FILE; do
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

cmd_adduser() {
  echo "账号与口令由 make-priv-files.sh 统一生成（口令只在服务器上一个 600 的文件里，不进屏幕）。"
  echo "跑：bash /usr/local/bin/make-priv-files.sh"
  echo "要手工单独加一个人：把明文口令放进程标准输入喂给 hash-password.mjs，"
  echo "  不要在命令行参数里写口令（会留在 shell 历史），也不要在非 tty 的 SSH 里等交互输入（会挂住）。"
}

# ---------- 5. fail closed 验证 ----------
# 移开用户文件这一步必须保证"无论成败都放回去"：本轮就因为我调了个不存在的
# stop_instance，脚本半路死掉，users.json 一直留在 .hold 名字上没人恢复。
hold_users() { mv "$PRIV/users.json" "$PRIV/users.json.hold"; }
restore_users() { [ -f "$PRIV/users.json.hold" ] && mv -f "$PRIV/users.json.hold" "$PRIV/users.json" && echo "  users.json 已放回原位"; return 0; }

cmd_failclosed() {
  need_root
  ensure_dirs
  ensure_priv
  [ -f "$PRIV/users.json" ] || die "先跑 make-priv-files.sh 生成 users.json" 2
  trap 'stop_instance >/dev/null 2>&1 || true; restore_users' EXIT
  hold_users                                           # 移开，不删
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
  restore_users
  trap - EXIT
  if [ "$api" = "503" ] && echo "$code" | grep -qE '302|401'; then
    echo "AUTH_FAIL_CLOSED=PASS —— 认证配置坏了仍然关着门，业务接口没有 200"
  else
    die "PREDEPLOY_REJECTED_AUTH_FAIL_OPEN 认证配置坏了但业务仍可用（api=$api, root=$code）" 2
  fi
}

# ---------- 6. Gate ----------
cmd_gates() {
  need_ref
  ensure_dirs
  [ -d "$REL" ] || die "先 fetch" 2
  local out="$LOGDIR/gates-$(date +%Y%m%d-%H%M).txt"; : > "$out"
  # 清单与仓库 eval/ 保持同步；换候选后先数一下项数，漏跑一项就等于没跑那一轮（13 → 14）
  for g in runtime-isolation authority adapter-shape admission retry liveness xss-boundary \
           budget-cap date outcome-loop frontend-e2e runtime auth search-key-failover; do
    f="$REL/eval/${g}-selftest.mjs"; [ -f "$f" ] || f="$REL/eval/${g}.mjs"
    st=$(date +%s)
    if ( cd "$REL" && node "$f" > "$LOGDIR/gate-$g.log" 2>&1 ); then r=PASS; else r=FAIL; fi
    printf '%-18s %-5s %ss\n' "$g" "$r" "$(( $(date +%s) - st ))" | tee -a "$out"
  done
  echo "---- 服务器发布树 Gate 汇总（$REL）----"; cat "$out"
  grep -q FAIL "$out" && die "有 Gate 未通过：见 $LOGDIR/gate-*.log（不许引用开发机的旧绿灯）" 2 \
    || echo "ALL_GATES=PASS（服务器真实发布树）"
}

# ---------- 7. 本机验证实例 ----------
start_instance() {
  [ -f "$SMOKE_ENV" ] || die "先 smokeenv" 2
  ensure_dirs
  set -a; . "$SMOKE_ENV"; set +a
  cd "$REL"
  nohup node server/world.mjs > "$LOGDIR/smoke.out" 2>&1 &
  echo $! > "$STATE/smoke.pid"
}
stop_instance() {
  if [ -f "$STATE/smoke.pid" ]; then
    kill "$(cat "$STATE/smoke.pid")" 2>/dev/null || true
    rm -f "$STATE/smoke.pid"
  fi
  echo "本机验证实例已停（公网从未指向它）"
}
cmd_start() { need_root; need_ref; ensure_dirs; start_instance; sleep 2
  echo "PID=$(cat "$STATE/smoke.pid") 监听：$(ss -ltnp 2>/dev/null | grep ":$SMOKE_PORT" | head -1)"
  echo "healthz: $(curl -s --max-time 8 http://$SMOKE_HOST:$SMOKE_PORT/healthz)"; }
cmd_stop() { need_root; stop_instance; }

# ---------- 8. 只读汇总 ----------
cmd_report() {
  need_root
  local show_ref show_rel
  show_ref="${WS_REF:-$(cat "$STATE/approved-sha" 2>/dev/null || true)}"
  show_rel="$ROOT/releases/${show_ref:-<未登记>}"
  echo "=== §1 候选锁死 ==="
  echo "  候选（WS_REF / 已登记批准点）: ${show_ref:-<未登记>}"
  echo "  发布树: $show_rel"; [ -d "$show_rel" ] && echo "  存在: yes" || echo "  存在: no"
  echo "  current -> $(readlink "$ROOT/current" || echo 未设置)   # 公网在跑的仍是它，本脚本未改"
  echo "=== §2 仓库外私有文件 ==="
  for f in "$PRIV/users.json" "$PRIV/session-secret.txt"; do
    if [ -f "$f" ]; then echo "  $(basename "$f"): mode=$(stat -c %a "$f") owner=$(stat -c %U "$f") 在位"; else echo "  $(basename "$f"): 缺失"; fi
  done
  echo "  users.json 里的 user_id（不含 hash）: $(node -e 'try{const j=require("'$PRIV'/users.json");console.log(j.users.map(u=>u.user_id).join(",")||"空")}catch(e){console.log("读不到")}' 2>/dev/null || echo 读不到)"
  echo "  Git 可见性: $(git -C "$CACHE" grep -l -I 'WS_SEARCH_KEY\|password' "$show_ref" -- 2>/dev/null | grep -v scripts/ | head -3 || echo 无)"
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
  *) sed -n '17,28p' "$0"; exit 2 ;;
esac
