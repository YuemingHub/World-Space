#!/usr/bin/env bash
# World Space 双面 healthz 核验器 —— 只读：不写文件、不改服务、不关站。
#
# 为什么要单独成篇：切流工具必须把「公网面」和「内部诊断面」分开判。
# 这套判断若只能依附在切流动作里，就永远没被人真正跑红过（判据没红过 = 没有判据）。
# 拆出来之后，ops-selftest.sh 能用假面把它逐条判红、判绿。
#
# 用法：
#   ws-verify-faces.sh                     # 生产默认（公网 127.0.0.1:3200 / 诊断 3201 / https://ymai.fun）
#   WS_* 覆盖后指向 fixture（见 ops-selftest.sh）
#
# 退出码是**契约**，调用方只按码动作，不许靠读中文猜：
#   0  通过（当前模式的断言全成立）
#   2  新版面不完整：3201 不可达／自报身份不符／app_port 不符／诊断字段缺项／
#      发布身份缺失或与批准版本不符／进程启动时间早于本次切流
#   3  公网面本身不对：形状不对、detail 对外可见、访问门失效，或首页形状与发布树物证不符
#   4  静态探针（目标代码里有没有诊断面）与运行时形状互相矛盾
#   5  公网面完全探测不到 —— 只有这一码代表「服务确实不可用」
#   6  用法或环境错误（含 WS_EXPECTED_ROOT 非法，或显式预期与发布树物证矛盾）
#   7  身份不可核实：旧版单面没有诊断面，无法证明"正在服务的是批准提交" —— 不返回 OK
#
# 匿名首页的预期形状由**发布树物证**决定，不由人临时声明：
#   WS_EXPECTED_ROOT=auto（默认）  目标树有 web/v2/public/index.html → facade，否则 → auth_only
#   WS_EXPECTED_ROOT=facade       要求未登录 / 返回 200 + HTML + 门面标志串（不是"任何 200 都算过"）
#   WS_EXPECTED_ROOT=auth_only    要求未登录 / 返回 302 → /login（旧版回滚状态）
# 未给 WS_TARGET_REL 时记 unbound：只接受「带内容物证的 200 门面」或「302 → /login」两种之一，
# 并打印 WARN；它无法把两种物证分开，所以正式切流必须经 cutover.sh（它总会传 WS_TARGET_REL）。
#
# 2/3/4 一律「保留现场交人判断」，不得自动关站：它们证明的是我的判断不过，
# 不是网站挂了。把它们当成关站条件，就会把一次正确部署误关成 503。
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PUBLIC_PORT="${WS_PUBLIC_PORT:-3200}"
OPS_PORT="${WS_OPS_PORT:-3201}"
PROBE_HOST="${WS_PROBE_HOST:-127.0.0.1}"
TARGET_REL="${WS_TARGET_REL:-}"                          # 目标发布树；给了才做静态探针
EXPECTED_ROOT="${WS_EXPECTED_ROOT:-auto}"                # auto | facade | auth_only
EXPECT_PID="${WS_EXPECT_PID:-}"                          # 服务 MainPID；给了才要求诊断口自报同一 pid
# ── 发布身份绑定（2026-11-01 R3 P0）─────────────────────────────────────
# 期望身份优先**由本脚本从批准发布树现算**（WS_TARGET_REL），env 只是交叉核对；
# 两边都没有 = 不可核实 → 拒绝 OK（不能凭调用方一句声明就放行）。
EXPECT_RELEASE_ID="${WS_EXPECT_RELEASE_ID:-}"
EXPECT_START_AFTER="${WS_EXPECT_START_AFTER:-}"          # 本次切流重启前的时间（毫秒）
GATE_BASE="${WS_GATE_BASE:-https://ymai.fun}"            # 访问门的既有行为从这里验
RESOLVE_HOST="${WS_RESOLVE_HOST:-ymai.fun:443:127.0.0.1}" # 空串＝不加 --resolve（fixture 用）
TIMEOUT="${WS_CURL_TIMEOUT:-8}"
SS_CMD="${WS_SS_CMD:-ss -lnt}"                            # 覆盖成 "echo" 可关掉 loopback 绑定这项

# 门面物证：必须同时命中标题语义、交互锚点和完整文档收尾，避免空壳 200 冒充
FACADE_MARK_A='你想做什么事'
FACADE_MARK_B='id="btn-write"'
FACADE_MARK_C='</html>'
FACADE_MIN_BYTES=8000

# 诊断面必须带的字段：少一个就说明这个面不是我以为的那个面。
# release_id/release_id_scheme/started_at_ms/diagnostic_face 是"正在服务哪份字节"的物证。
REQUIRED_OPS_FIELDS="auth provider model search search_configured today_calls daily_cap month_cost_rmb monthly_cap_rmb fail_closed app_port pid diagnostic_face release_id release_id_scheme started_at_ms"

PUB="http://$PROBE_HOST:$PUBLIC_PORT"
OPS="http://$PROBE_HOST:$OPS_PORT"
RES=()
[ -n "$RESOLVE_HOST" ] && RES=(--resolve "$RESOLVE_HOST")

CHECKS=0
FAIL_LIST=""
PUBFAIL=""            # 公网面类失败 → 退出码 3
OPSFAIL=""            # 诊断面类失败 → 退出码 2
CLASS=pub             # bad() 归属哪一类，由下面两段分别设定
MODE="unknown"
PROFILE="pending"
note() { printf '  %-46s %s\n' "$1" "$2"; }
bad()  { CHECKS=$((CHECKS+1)); FAIL_LIST="$FAIL_LIST $1"
         if [ "$CLASS" = ops ]; then OPSFAIL="$OPSFAIL $1"; else PUBFAIL="$PUBFAIL $1"; fi
         note "$1" "FAIL  $2"; }
good() { CHECKS=$((CHECKS+1)); note "$1" "PASS  $2"; }
verdict() {   # verdict <VERDICT_TEXT> <exit code>
  printf 'MODE=%s\nPROFILE=%s\nCHECKS=%s\nFAILS=%s\nVERDICT=%s\nEXIT=%s\n' \
    "$MODE" "$PROFILE" "$CHECKS" "${FAIL_LIST:- none}" "$1" "$2"
  exit "$2"
}
curl_get() { [ ${#RES[@]} -gt 0 ] && curl -s "${RES[@]}" -o /dev/null -w "$2" --max-time "$TIMEOUT" "$1" || curl -s -o /dev/null -w "$2" --max-time "$TIMEOUT" "$1"; }
curl_post() { [ ${#RES[@]} -gt 0 ] && curl -s "${RES[@]}" -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data "$2" --max-time "$TIMEOUT" "$1" || curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data "$2" --max-time "$TIMEOUT" "$1"; }
curl_post_h() { local url="$1" data="$2"; shift 2
  [ ${#RES[@]} -gt 0 ] && curl -s "${RES[@]}" -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' "$@" --data "$data" --max-time "$TIMEOUT" "$url" || curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' "$@" --data "$data" --max-time "$TIMEOUT" "$url"; }
body_meta() { local url="$1"; shift
  [ ${#RES[@]} -gt 0 ] && curl -s "${RES[@]}" "$@" -w $'\n%{http_code}|%{content_type}|%{redirect_url}' --max-time "$TIMEOUT" "$url" || curl -s "$@" -w $'\n%{http_code}|%{content_type}|%{redirect_url}' --max-time "$TIMEOUT" "$url"; }
root_expect() { # root_expect <label> <raw body+meta> —— 按 PROFILE 判匿名首页形状
  local label="$1" raw="$2" meta code ct loc body bytes proof=no
  meta=$(printf '%s' "$raw" | awk 'END{print}')
  code=$(printf '%s' "$meta" | cut -d'|' -f1)
  ct=$(printf '%s' "$meta" | cut -d'|' -f2)
  loc=$(printf '%s' "$meta" | cut -d'|' -f3)
  body=$(printf '%s' "$raw" | sed '$d')
  bytes=$(printf '%s' "$body" | wc -c | tr -d ' ')
  if grep -qF "$FACADE_MARK_A" <<<"$body" \
     && grep -qF "$FACADE_MARK_B" <<<"$body" \
     && grep -qF "$FACADE_MARK_C" <<<"$body" \
     && [ "$bytes" -ge "$FACADE_MIN_BYTES" ]; then proof=yes; fi
  case "$PROFILE" in
    facade)
      if [ "$code" = 200 ] && grep -qi 'text/html' <<<"$ct" && [ "$proof" = yes ]; then
        good "$label" "200 facade html ${bytes}B"
      else
        bad "$label" "期望 200 门面（HTML+标志串+≥${FACADE_MIN_BYTES}B），实得 code=$code ct=$ct bytes=$bytes"
      fi ;;
    auth_only)
      if [ "$code" = 302 ] && grep -q '/login' <<<"$loc"; then
        good "$label" "302 → /login"
      else
        bad "$label" "期望 302 → /login，实得 code=$code loc=${loc:-none}"
      fi ;;
    *)
      if { [ "$code" = 200 ] && [ "$proof" = yes ]; } || { [ "$code" = 302 ] && grep -q '/login' <<<"$loc"; }; then
        good "$label" "unbound: code=$code（门面物证/登录跳转二选一）"
      else
        bad "$label" "unbound: code=$code bytes=$bytes 既无门面物证也无 /login 跳转"
      fi ;;
  esac
}
body_get() { [ ${#RES[@]} -gt 0 ] && curl -s "${RES[@]}" -w $'\n%{http_code}' --max-time "$TIMEOUT" "$1" || curl -s -w $'\n%{http_code}' --max-time "$TIMEOUT" "$1"; }
status_of() { printf '%s' "$1" | awk 'END{print}'; }
body_of()   { printf '%s' "$1" | sed '$d'; }
json_keys() { printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(Object.keys(JSON.parse(s)).sort().join(","))}catch(e){console.log("UNPARSABLE")}})' 2>/dev/null || echo UNPARSABLE; }

# ---------- 静态探针：目标代码里到底有没有第二个面 ----------
STATIC=""
if [ -n "$TARGET_REL" ]; then
  wf="$TARGET_REL/server/world.mjs"
  if [ ! -f "$wf" ]; then
    MODE=static_probe_failed
    bad "static_probe_target_readable" "发布树里找不到 $wf"
    verdict "STATIC_PROBE_FAILED" 6
  fi
  # 去注释/字符串后再判：一行注释不能把 legacy 冒充成 dual_face（Deep 复核 P8）
  STATIC=$(node "$HERE/face-probe.mjs" "$wf" 2>/dev/null || true)
  case "$STATIC" in
    dual_face|legacy_single_face) good "static_probe_code_face_mode" "$STATIC" ;;
    *) STATIC=""; MODE=static_probe_failed
       bad "static_probe_code_face_mode" "无法从 $wf 读出诊断面能力"
       verdict "STATIC_PROBE_FAILED" 6 ;;
  esac
fi

# ---------- 期望发布身份：优先从批准发布树现算；env 只做交叉核对 ----------
EXPECTED_RELEASE_ID=""; IDENTITY_EXPECT_ERROR=""
case "$EXPECT_RELEASE_ID" in
  '') ;;
  *) if grep -Eq '^[0-9a-f]{64}$' <<<"$EXPECT_RELEASE_ID"; then EXPECTED_RELEASE_ID="$EXPECT_RELEASE_ID"
     else IDENTITY_EXPECT_ERROR="WS_EXPECT_RELEASE_ID 不是 64 位小写 hex"; fi ;;
esac
if [ -n "$TARGET_REL" ]; then
  if [ -f "$HERE/release-id.mjs" ]; then
    CALC=$(node "$HERE/release-id.mjs" "$TARGET_REL" 2>/dev/null || true)
    if ! grep -Eq '^[0-9a-f]{64}$' <<<"$CALC"; then
      IDENTITY_EXPECT_ERROR="无法从发布树 $TARGET_REL 算出发布身份"
    elif [ -n "$EXPECTED_RELEASE_ID" ] && [ "$EXPECTED_RELEASE_ID" != "$CALC" ]; then
      IDENTITY_EXPECT_ERROR="WS_EXPECT_RELEASE_ID=$EXPECTED_RELEASE_ID 与发布树实算 $CALC 不一致"
    else
      EXPECTED_RELEASE_ID="$CALC"
    fi
  elif [ -z "$EXPECTED_RELEASE_ID" ]; then
    IDENTITY_EXPECT_ERROR="找不到 $HERE/release-id.mjs，且没有 WS_EXPECT_RELEASE_ID"
  fi
elif [ -z "$EXPECTED_RELEASE_ID" ]; then
  IDENTITY_EXPECT_ERROR="既没有 WS_TARGET_REL 也没有 WS_EXPECT_RELEASE_ID，身份不可核实"
fi
START_EXPECT_ERROR=""
case "$EXPECT_START_AFTER" in
  ''|*[!0-9]*) START_EXPECT_ERROR="WS_EXPECT_START_AFTER 缺失或不是毫秒整数" ;;
esac

# ---------- 匿名首页预期：由发布树物证决定（不是"任何 200 都算过"） ----------
ARTIFACT_FACADE=no
if [ -n "$TARGET_REL" ] && [ -s "$TARGET_REL/web/v2/public/index.html" ]; then ARTIFACT_FACADE=yes; fi
case "$EXPECTED_ROOT" in
  auto)
    if [ -z "$TARGET_REL" ]; then
      PROFILE=unbound
      note "expected_root_profile" "WARN=UNBOUND 未给 WS_TARGET_REL；只认内容物证或 302 之一"
    elif [ "$ARTIFACT_FACADE" = yes ]; then
      PROFILE=facade
      note "expected_root_profile" "facade（发布树有 web/v2/public/index.html）"
    else
      PROFILE=auth_only
      note "expected_root_profile" "auth_only（发布树无门面文件）"
    fi ;;
  facade|auth_only)
    PROFILE="$EXPECTED_ROOT"
    if [ -n "$TARGET_REL" ]; then
      HAVE=auth_only; [ "$ARTIFACT_FACADE" = yes ] && HAVE=facade
      if [ "$HAVE" != "$PROFILE" ]; then
        MODE=expected_root_conflict
        bad "expected_root_matches_artifact" "显式声明 $PROFILE，但发布树物证是 $HAVE"
        verdict "EXPECTED_ROOT_CONFLICT" 6
      fi
    fi
    note "expected_root_profile" "$PROFILE（显式声明）" ;;
  *)
    MODE=usage_error
    bad "expected_root_valid" "WS_EXPECTED_ROOT=$EXPECTED_ROOT 不是 auto|facade|auth_only"
    verdict "USAGE_ERROR" 6 ;;
esac

# ---------- 公网面先探：不可达是唯一可能触发关站的情形 ----------
R=$(body_get "$PUB/healthz") || true
S=$(status_of "$R"); B=$(body_of "$R")
if [ -z "$S" ] || [ "$S" = "000" ]; then
  MODE=unreachable
  bad "public_face_reachable" "$PUB/healthz 探测不到响应"
  verdict "SERVICE_UNAVAILABLE" 5
fi
PUB_KEYS=$(json_keys "$B")
case ",$PUB_KEYS," in
  *,provider,*|*,auth,*) MODE=legacy_single_face ;;
  ",ok,")                MODE=dual_face ;;
  *)                     MODE=unknown ;;
esac

# ---------- 静态与运行时矛盾 → 交人判断，不动站点 ----------
if [ -n "$STATIC" ] && [ "$STATIC" != "$MODE" ]; then
  bad "mode_consistency_static_vs_runtime" "目标代码说 $STATIC，运行时是 $MODE"
  verdict "MODE_CONFLICT" 4
fi

# ---------- 公网面通用断言（两种模式都必须成立） ----------
[ "$S" = "200" ] && good "public_healthz_http200" "$S" || bad "public_healthz_http200" "$S"
if [ "$PUB_KEYS" = "UNPARSABLE" ]; then
  bad "public_healthz_is_json" "$(printf '%s' "$B" | head -c 60)"
else
  good "public_healthz_is_json" "keys=$PUB_KEYS"
fi
if grep -q '"ok"[[:space:]]*:[[:space:]]*true' <<<"$B"; then
  good "public_healthz_ok_true" ""
else
  bad "public_healthz_ok_true" "$(printf '%s' "$B" | head -c 60)"
fi
DS=$(curl_get "$PUB/healthz/detail" '%{http_code}')
[ "$DS" = "404" ] && good "public_healthz_detail_not_exposed" "$DS" || bad "public_healthz_detail_not_exposed" "HTTP $DS"

# 匿名首页：形状由 PROFILE 决定（facade 200+物证 / auth_only 302→login / unbound 二选一）
R0=$(body_meta "$GATE_BASE/")
root_expect "unauth_root_matches_expected" "$R0"
# /index.html 与 / 走同一分支；若被旧静态文件覆盖，这里会红
R1=$(body_meta "$GATE_BASE/index.html")
root_expect "unauth_index_matches_expected" "$R1"
# 过期/伪造 session：首页不得被当成已登录（门面仍是门面，旧版仍是登录跳转）
REX=$(body_meta "$GATE_BASE/" -H 'Cookie: ws_sess=invalid.expired.token')
root_expect "expired_session_root_not_logged_in" "$REX"
G2=$(curl_post "$GATE_BASE/api/world" '{"intent":"verify probe"}')
[ "$G2" = "401" ] && good "unauth_api_still_401" "$G2" || bad "unauth_api_still_401" "$G2"
G2B=$(curl_post_h "$GATE_BASE/api/world" '{"intent":"verify probe"}' -H 'Cookie: ws_sess=invalid.expired.token')
[ "$G2B" = "401" ] && good "expired_session_api_401" "$G2B" || bad "expired_session_api_401" "$G2B"
ME=$(curl_get "$GATE_BASE/api/auth/me" '%{http_code}')
[ "$ME" = "401" ] && good "unauth_me_401" "$ME" || bad "unauth_me_401" "$ME"
# 空凭据必须被登录端点拒绝（400），且这一步不触发失败计数（不做真实口令尝试）
L0=$(curl_post "$GATE_BASE/api/auth/login" '{}')
[ "$L0" = "400" ] && good "login_endpoint_rejects_empty" "$L0" || bad "login_endpoint_rejects_empty" "$L0"
LPR=$(body_get "$GATE_BASE/login")
LPS=$(status_of "$LPR")
if [ "$LPS" = "200" ] && grep -q '进入你的空间' <<<"$(body_of "$LPR")"; then
  good "login_page_serves_gate" "$LPS"
else
  bad "login_page_serves_gate" "HTTP $LPS 或缺登录页标志串"
fi

# ---------- 分模式断言 ----------
if [ "$MODE" = "unknown" ]; then
  bad "public_face_shape_recognised" "键=$PUB_KEYS：既不是纯存活面，也不是旧版详细面"
  verdict "PUBLIC_FACE_BAD" 3
fi

if [ "$MODE" = "legacy_single_face" ]; then
  printf 'WARN=LEGACY_SINGLE_FACE 诊断字段仍在公网面上（未登录可读 provider／预算／用量）\n'
  if grep -q '"auth"' <<<"$B"; then good "legacy_still_reports_auth" ""; else bad "legacy_still_reports_auth" "$B"; fi
  # P0：没有诊断面就没有"正在服务哪份字节"的物证 → 不得给出 OK（7 = 身份不可核实）。
  if [ -z "$PUBFAIL" ]; then
    printf 'WARN=IDENTITY_UNVERIFIABLE 旧版单面没有诊断面，无法证明正在服务的是批准提交\n'
    verdict "IDENTITY_UNVERIFIABLE" 7
  fi
elif [ "$MODE" = "dual_face" ]; then
  if [ "$PUB_KEYS" != "ok" ]; then
    bad "public_face_minimal_shape" "公网面上还挂着别的键：$PUB_KEYS"
    verdict "PUBLIC_FACE_BAD" 3
  fi
  good "public_face_minimal_shape" "只有 ok"

  CLASS=ops
  O=$(body_get "$OPS/healthz") || true
  OS=$(status_of "$O"); OB=$(body_of "$O")
  if [ -z "$OS" ] || [ "$OS" = "000" ]; then
    bad "ops_face_reachable" "$OPS/healthz 探测不到 —— 新版必须有这个面"
    verdict "NEW_INCOMPLETE" 2
  fi
  [ "$OS" = "200" ] && good "ops_face_http200" "$OS" || bad "ops_face_http200" "$OS"
  if [ "$(json_keys "$OB")" = "UNPARSABLE" ]; then
    bad "ops_face_is_json" "$(printf '%s' "$OB" | head -c 60)"
    verdict "NEW_INCOMPLETE" 2
  fi
  miss=""
  for k in $REQUIRED_OPS_FIELDS; do
    grep -q "\"$k\"" <<<"$OB" || miss="$miss $k"
  done
  if [ -z "$miss" ]; then
    good "ops_face_has_all_fields" "$(json_keys "$OB" | tr ',' '\n' | wc -l) 键"
  else
    bad "ops_face_has_all_fields" "缺:$miss"
  fi
  jget() { printf '%s' "$OB" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log(j[process.argv[1]])}catch(e){console.log("ERR")}})' "$1" 2>/dev/null || echo ERR; }
  OAUTH=$(jget auth); OPORT=$(jget app_port); OPID=$(jget pid)
  OFACE=$(jget diagnostic_face); OIDENT=$(jget release_id); OSCHEME=$(jget release_id_scheme); OSTART=$(jget started_at_ms)
  [ "$OAUTH" = "ready" ] && good "ops_auth_ready" "$OAUTH" || bad "ops_auth_ready" "$OAUTH"
  if [ "$OPORT" = "$PUBLIC_PORT" ]; then good "ops_app_port_matches_public" "$OPORT"; else bad "ops_app_port_matches_public" "自报 $OPORT ≠ 公网口 $PUBLIC_PORT"; fi
  if [ -n "$EXPECT_PID" ]; then
    if [ "$OPID" = "$EXPECT_PID" ]; then good "ops_pid_matches_service" "$OPID"; else bad "ops_pid_matches_service" "自报 $OPID ≠ MainPID $EXPECT_PID"; fi
  else
    bad "ops_pid_matches_service" "未给 WS_EXPECT_PID：无法证明这个诊断面属于被重启的进程"
  fi
  # ── P0：正在服务的字节身份 ─────────────────────────────────────────
  [ "$OFACE" = "ops-v1" ] && good "ops_diagnostic_face_marker" "$OFACE" || bad "ops_diagnostic_face_marker" "自报 '$OFACE' ≠ ops-v1"
  [ "$OSCHEME" = "world-release-tree-v1" ] && good "ops_release_id_scheme" "$OSCHEME" || bad "ops_release_id_scheme" "自报 '$OSCHEME'"
  if grep -Eq '^[0-9a-f]{64}$' <<<"$OIDENT"; then
    good "ops_release_id_shape" "sha256"
    if [ -n "$EXPECTED_RELEASE_ID" ]; then
      if [ "$OIDENT" = "$EXPECTED_RELEASE_ID" ]; then good "ops_release_id_matches_approved" "$OIDENT"
      else bad "ops_release_id_matches_approved" "运行中 $OIDENT ≠ 批准版本 $EXPECTED_RELEASE_ID"; fi
    else
      bad "ops_release_id_matches_approved" "无可核实的期望身份：${IDENTITY_EXPECT_ERROR:-未知}"
    fi
  else
    bad "ops_release_id_shape" "缺失或不是 64 位 hex：'${OIDENT}'"
    bad "ops_release_id_matches_approved" "运行身份不可核实"
  fi
  if [ -n "$START_EXPECT_ERROR" ]; then
    bad "ops_started_after_cutover" "$START_EXPECT_ERROR"
  elif ! grep -Eq '^[0-9]+$' <<<"$OSTART"; then
    bad "ops_started_after_cutover" "自报启动时间 '$OSTART' 不是毫秒整数"
  elif [ "$OSTART" -lt "$((EXPECT_START_AFTER - 1000))" ]; then
    bad "ops_started_after_cutover" "自报启动 $OSTART 早于本次切流 $EXPECT_START_AFTER：这是旧进程，重启没有生效"
  else
    good "ops_started_after_cutover" "$OSTART ≥ $EXPECT_START_AFTER"
  fi
  OL=$(curl_get "$OPS/login" '%{http_code}')
  OA=$(curl_post "$OPS/api/world" '{}')
  [ "$OL" = "404" ] && good "ops_face_no_app_pages" "$OL" || bad "ops_face_no_app_pages" "$OL"
  [ "$OA" = "404" ] && good "ops_face_no_business_api" "$OA" || bad "ops_face_no_business_api" "$OA"
  SS_OUT=$($SS_CMD 2>/dev/null); SSG=$?
  if [ "$SSG" -ne 0 ] || [ -z "$SS_OUT" ]; then
    note "ops_face_loopback_only" "SKIP  「$SS_CMD」不可用（退出 $SSG）—— 这项没量到，不算过"
  else
    LB=$(printf '%s\n' "$SS_OUT" | grep -E "[:.]$OPS_PORT\b" | grep -vcE "127\.0\.0\.1:$OPS_PORT\b" || true)
    [ -z "$LB" ] && LB=0
    if [ "$LB" != "0" ]; then bad "ops_face_loopback_only" "$LB 个非 loopback 绑定"; else good "ops_face_loopback_only" "0"; fi
  fi
fi

# 退出码按**失败类别**给，不给" whichever 模式"的笼统码：
# 公网面不对（3）与诊断面不完整（2）在调用方是完全不同的动作。
if [ -n "$PUBFAIL" ]; then
  verdict "PUBLIC_FACE_BAD" 3
elif [ -n "$OPSFAIL" ]; then
  verdict "NEW_INCOMPLETE" 2
fi
verdict "OK" 0
