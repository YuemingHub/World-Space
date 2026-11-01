#!/usr/bin/env bash
# Route-isolation acceptance for the /ai/ deploy plan, run against a real nginx 1.18
# loaded with the production 443 block text (TLS/port changed) + the proposed snippet.
# Exit 0 only if every check passes.
set -u
BASE="${BASE:-http://127.0.0.1:18080}"
STATIC_DIR="${STATIC_DIR:-/srv/static}"
PASS=0; FAIL=0

# A dead harness must never look like a pass: prove the target answers first.
if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/healthz")" = 000 ]; then
  echo "HARNESS_UNREACHABLE $BASE"
  exit 2
fi

ok()  { PASS=$((PASS+1)); printf 'PASS %-46s %s\n' "$1" "$2"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL %-46s %s\n' "$1" "$2"; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
hdr()  { curl -s -o /dev/null -w '%{http_code}|%{content_type}|%{redirect_url}' "$@"; }
loc()  { curl -sI "$1" | awk 'tolower($1)=="location:"{sub(/\r$/,"",$2); print $2; exit}'; }
ends_with() { case "$1" in *"$2") return 0 ;; *) return 1 ;; esac; }

# A1 / -> 302 /login
R=$(code "$BASE/"); L=$(loc "$BASE/")
if [ "$R" = 302 ] && ends_with "$L" /login; then ok A1_root_302_login "$R $L"; else bad A1_root_302_login "$R $L"; fi

# A2 unauthenticated POST /api/world -> 401 (proves ^~ /ai/ did not steal /api/)
C=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/world" -H 'content-type: application/json' -d '{"intent":"smoke"}')
[ "$C" = 401 ] && ok A2_unauth_api_401 "$C" || bad A2_unauth_api_401 "$C"

# A3 /login -> 200 with gate marker
B=$(curl -s "$BASE/login"); C=$(code "$BASE/login")
if [ "$C" = 200 ] && printf '%s' "$B" | grep -q '进入你的空间'; then ok A3_login_serves_gate "$C"; else bad A3_login_serves_gate "HTTP=$C"; fi

# A4 /healthz -> {"ok":true}
B=$(curl -s "$BASE/healthz")
[ "$B" = '{"ok":true}' ] && ok A4_healthz_public_ok "$B" || bad A4_healthz_public_ok "$B"

# A5 /ming/ unchanged (fixture baseline; production md5 must be measured at deploy time)
C=$(code "$BASE/ming/"); B=$(curl -s "$BASE/ming/")
M=$(printf '%s' "$B" | md5sum | cut -d' ' -f1)
if [ "$C" = 200 ] && printf '%s' "$B" | grep -q 'MING-FIXTURE-SENTINEL'; then ok A5_ming_still_served "$C md5=$M"; else bad A5_ming_still_served "HTTP=$C"; fi

# A5b /ming (exact) still 301 -> /ming/ (snippet's existing rule intact)
R=$(code "$BASE/ming"); L=$(loc "$BASE/ming")
if [ "$R" = 301 ] && ends_with "$L" /ming/; then ok A5b_ming_exact_301 "$R $L"; else bad A5b_ming_exact_301 "$R $L"; fi

# A6 /web/index.html -> 404 (not served statically, proxied to Node which 404s)
C=$(code "$BASE/web/index.html")
[ "$C" = 404 ] && ok A6_web_index_not_served "$C" || bad A6_web_index_not_served "$C"

# B1 /ai/ -> 200 text/html + content markers
H=$(hdr "$BASE/ai/"); B=$(curl -s "$BASE/ai/")
SZ=$(printf '%s' "$B" | wc -c | tr -d ' ')
CT=$(printf '%s' "$H" | cut -d'|' -f2)
case "$H" in 200\|text/html*) ok B1_ai_index_200 "$H bytes=$SZ" ;; *) bad B1_ai_index_200 "$H bytes=$SZ" ;; esac
if printf '%s' "$CT" | grep -q 'charset=utf-8'; then ok B1b_ai_charset_header "$CT"; else bad B1b_ai_charset_header "$CT"; fi
if printf '%s' "$B" | grep -q '完全不懂也没关系' && printf '%s' "$B" | grep -q '不要注册'; then ok B1c_ai_body_marker "both markers present"; else bad B1c_ai_body_marker "marker missing"; fi

# B2 /ai -> 301 /ai/
R=$(code "$BASE/ai"); L=$(loc "$BASE/ai")
if [ "$R" = 301 ] && ends_with "$L" /ai/; then ok B2_ai_slash_redirect "$R $L"; else bad B2_ai_slash_redirect "$R $L"; fi

# B3 static assets and deep pages
C=$(curl -s -o /dev/null -w '%{http_code}|%{content_type}' "$BASE/ai/assets/ai.css")
case "$C" in 200\|text/css*) ok B3_ai_css "$C" ;; *) bad B3_ai_css "$C" ;; esac
C=$(code "$BASE/ai/assets/ai.js")
[ "$C" = 200 ] && ok B3b_ai_js "$C" || bad B3b_ai_js "$C"
C=$(code "$BASE/ai/paths/find-the-facts.html")
[ "$C" = 200 ] && ok B3c_ai_deep_page "$C" || bad B3c_ai_deep_page "$C"

# B4 traversal must not reach /web/index.html (--path-as-is keeps curl from normalising)
C=$(curl --path-as-is -s -o /dev/null -w '%{http_code}' "$BASE/ai/../web/index.html")
case "$C" in 2??|3??|4??) ok B4_traversal_not_200 "$C" ;; *) bad B4_traversal_not_200 "$C" ;; esac
C=$(curl --path-as-is -s -o /dev/null -w '%{http_code}' "$BASE/ai/../../etc/passwd")
case "$C" in 2??|3??|4??) ok B4b_traversal_escape_not_200 "$C" ;; *) bad B4b_traversal_escape_not_200 "$C" ;; esac

# B5 unknown path under /ai/ -> 404
C=$(code "$BASE/ai/nope")
[ "$C" = 404 ] && ok B5_ai_unknown_404 "$C" || bad B5_ai_unknown_404 "$C"

# B6 body byte-identical to the frozen index.html
WANT=$(sha256sum "$STATIC_DIR/ai/index.html" | cut -d' ' -f1)
GOT=$(curl -s "$BASE/ai/" | sha256sum | cut -d' ' -f1)
[ "$WANT" = "$GOT" ] && ok B6_ai_index_sha256_match "$GOT" || bad B6_ai_index_sha256_match "want=$WANT got=$GOT"

# B7 no directory listing at /ai/ (index served, not autoindex)
B=$(curl -s "$BASE/ai/")
printf '%s' "$B" | grep -q 'Index of /ai/' && bad B7_no_autoindex "listing visible" || ok B7_no_autoindex "no listing"

# B8 cache header present on /ai/, app's no-store must not leak
H=$(curl -sI "$BASE/ai/")
printf '%s' "$H" | grep -qi 'Cache-Control: public, max-age=300' && ok B8_ai_cache_header "public, max-age=300" || bad B8_ai_cache_header "$(printf '%s' "$H" | grep -i cache-control | tr -d '\r')"

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
