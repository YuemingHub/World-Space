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
#   2  新版面不完整：3201 不可达／自报身份不符／app_port 不符／诊断字段缺项
#   3  公网面本身不对：形状不对、detail 对外可见、或访问门失效
#   4  静态探针（目标代码里有没有诊断面）与运行时形状互相矛盾
#   5  公网面完全探测不到 —— 只有这一码代表「服务确实不可用」
#   6  用法或环境错误
#
# 2/3/4 一律「保留现场交人判断」，不得自动关站：它们证明的是我的判断不过，
# 不是网站挂了。把它们当成关站条件，就会把一次正确部署误关成 503。
set -uo pipefail

PUBLIC_PORT="${WS_PUBLIC_PORT:-3200}"
OPS_PORT="${WS_OPS_PORT:-3201}"
PROBE_HOST="${WS_PROBE_HOST:-127.0.0.1}"
TARGET_REL="${WS_TARGET_REL:-}"                          # 目标发布树；给了才做静态探针
EXPECT_PID="${WS_EXPECT_PID:-}"                          # 服务 MainPID；给了才要求诊断口自报同一 pid
GATE_BASE="${WS_GATE_BASE:-https://ymai.fun}"            # 访问门的既有行为从这里验
RESOLVE_HOST="${WS_RESOLVE_HOST:-ymai.fun:443:127.0.0.1}" # 空串＝不加 --resolve（fixture 用）
TIMEOUT="${WS_CURL_TIMEOUT:-8}"
SS_CMD="${WS_SS_CMD:-ss -lnt}"                            # 覆盖成 "echo" 可关掉 loopback 绑定这项

# 诊断面必须带的字段：少一个就说明这个面不是我以为的那个面
REQUIRED_OPS_FIELDS="auth provider model search search_configured today_calls daily_cap month_cost_rmb monthly_cap_rmb fail_closed app_port pid"

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
note() { printf '  %-46s %s\n' "$1" "$2"; }
bad()  { CHECKS=$((CHECKS+1)); FAIL_LIST="$FAIL_LIST $1"
         if [ "$CLASS" = ops ]; then OPSFAIL="$OPSFAIL $1"; else PUBFAIL="$PUBFAIL $1"; fi
         note "$1" "FAIL  $2"; }
good() { CHECKS=$((CHECKS+1)); note "$1" "PASS  $2"; }
verdict() {   # verdict <VERDICT_TEXT> <exit code>
  printf 'MODE=%s\nCHECKS=%s\nFAILS=%s\nVERDICT=%s\nEXIT=%s\n' \
    "$MODE" "$CHECKS" "${FAIL_LIST:- none}" "$1" "$2"
  exit "$2"
}
curl_get() { [ ${#RES[@]} -gt 0 ] && curl -s "${RES[@]}" -o /dev/null -w "$2" --max-time "$TIMEOUT" "$1" || curl -s -o /dev/null -w "$2" --max-time "$TIMEOUT" "$1"; }
curl_post() { [ ${#RES[@]} -gt 0 ] && curl -s "${RES[@]}" -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data "$2" --max-time "$TIMEOUT" "$1" || curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data "$2" --max-time "$TIMEOUT" "$1"; }
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
  if [ "$(grep -c 'opsPort' "$wf")" -gt 0 ]; then STATIC=dual_face; else STATIC=legacy_single_face; fi
  good "static_probe_code_face_mode" "$STATIC"
fi

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
if printf '%s' "$B" | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
  good "public_healthz_ok_true" ""
else
  bad "public_healthz_ok_true" "$(printf '%s' "$B" | head -c 60)"
fi
DS=$(curl_get "$PUB/healthz/detail" '%{http_code}')
[ "$DS" = "404" ] && good "public_healthz_detail_not_exposed" "$DS" || bad "public_healthz_detail_not_exposed" "HTTP $DS"

G1=$(curl_get "$GATE_BASE/" '%{http_code} %{redirect_url}')
# 注意：curl 的 %{redirect_url} 给的是**绝对地址**（https://ymai.fun/login），不是 /login；
# 按字面 "/login" 精确匹配会永远不成立 —— 这条在真机上会把一次正确切流判成门失效。
case "$G1" in "302 "*) RC302=1 ;; *) RC302=0 ;; esac
case "$G1" in */login*) HASLOGIN=1 ;; *) HASLOGIN=0 ;; esac
if [ "$RC302" = "1" ] && [ "$HASLOGIN" = "1" ]; then
  good "unauth_root_still_302_login" "$G1"
else
  bad  "unauth_root_still_302_login" "$G1"
fi
G2=$(curl_post "$GATE_BASE/api/world" '{"intent":"verify probe"}')
[ "$G2" = "401" ] && good "unauth_api_still_401" "$G2" || bad "unauth_api_still_401" "$G2"
LPR=$(body_get "$GATE_BASE/login")
LPS=$(status_of "$LPR")
if [ "$LPS" = "200" ] && printf '%s' "$(body_of "$LPR")" | grep -q '进入你的空间'; then
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
  if printf '%s' "$B" | grep -q '"auth"'; then good "legacy_still_reports_auth" ""; else bad "legacy_still_reports_auth" "$B"; fi
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
    printf '%s' "$OB" | grep -q "\"$k\"" || miss="$miss $k"
  done
  if [ -z "$miss" ]; then
    good "ops_face_has_all_fields" "$(json_keys "$OB" | tr ',' '\n' | wc -l) 键"
  else
    bad "ops_face_has_all_fields" "缺:$miss"
  fi
  OAUTH=$(printf '%s' "$OB" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.auth)})' 2>/dev/null || echo ERR)
  OPORT=$(printf '%s' "$OB" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.app_port)})' 2>/dev/null || echo ERR)
  OPID=$(printf '%s' "$OB"  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.pid)})' 2>/dev/null || echo ERR)
  [ "$OAUTH" = "ready" ] && good "ops_auth_ready" "$OAUTH" || bad "ops_auth_ready" "$OAUTH"
  if [ "$OPORT" = "$PUBLIC_PORT" ]; then good "ops_app_port_matches_public" "$OPORT"; else bad "ops_app_port_matches_public" "自报 $OPORT ≠ 公网口 $PUBLIC_PORT"; fi
  if [ -n "$EXPECT_PID" ]; then
    if [ "$OPID" = "$EXPECT_PID" ]; then good "ops_pid_matches_service" "$OPID"; else bad "ops_pid_matches_service" "自报 $OPID ≠ MainPID $EXPECT_PID"; fi
  else
    note "ops_pid_matches_service" "SKIP  未给 WS_EXPECT_PID（自报 pid=$OPID）"
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
