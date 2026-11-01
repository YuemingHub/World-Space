#!/usr/bin/env bash
# verify-production.sh —— 生产核验器只读认证（不写任何文件，不联网）。
#
# 用途：安装前后各跑一次，证明"装的是哪一版、谁在调用它、依赖是否齐"。
# 用法：bash verify-production.sh [期望 sha256]
# 退出码：0 全部符合 / 1 有不符合项
set -uo pipefail
TO=${WS_VERIFY_TO:-/usr/local/bin/ws-verify-faces.sh}
PIN_TO=${WS_VERIFY_PIN_TO:-$TO.sha256}
EXPECT=${1:-${WS_VERIFY_EXPECT:-}}
[ -n "$EXPECT" ] || EXPECT=$(awk 'NR==1{print $1}' "$PIN_TO" 2>/dev/null || true)

N=0; F=0
ck() { N=$((N+1)); if [ "$2" = "$3" ]; then echo "PASS $1 = $2"; else echo "FAIL $1 = $2（期望 $3）"; F=$((F+1)); fi; }
has() { N=$((N+1)); if printf '%s' "$2" | grep -qF -- "$3"; then echo "PASS $1 含「$3」"; else echo "FAIL $1 缺「$3」"; F=$((F+1)); fi; }
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

echo "=== 核验器文件 ==="
ck exists "$([ -f "$TO" ] && echo yes || echo no)" yes
[ -f "$TO" ] || { echo; echo "PROD_VERIFIER_CERT=FAIL"; exit 1; }
H=$(sha "$TO")
ck sha256 "$H" "$EXPECT"
if [ -n "${WS_EXPECT_SIZE:-}" ]; then
  ck size_bytes "$(stat -c '%s' "$TO")" "$WS_EXPECT_SIZE"
else
  echo "INFO size_bytes=$(stat -c '%s' "$TO")（未给 WS_EXPECT_SIZE，本项不作判据）"
fi
ck owner "$(stat -c '%U:%G' "$TO")" "root:root"
ck executable_bits "$(stat -c '%a' "$TO")" "755"
ck syntax "$(bash -n "$TO" >/dev/null 2>&1 && echo ok || echo bad)" ok
echo "=== 哈希钉 ==="
ck pin_exists "$([ -f "$PIN_TO" ] && echo yes || echo no)" yes
ck pin_sha256 "$(awk 'NR==1{print $1}' "$PIN_TO" 2>/dev/null)" "$EXPECT"
echo "=== 依赖 ==="
for c in bash curl sha256sum node stat install; do
  ck "dep_$c" "$(command -v "$c" >/dev/null 2>&1 && echo ok || echo missing)" ok
done
echo "=== 同目录辅助文件（新版核验器用 \$HERE/face-probe.mjs 与 \$HERE/release-id.mjs） ==="
HD=$(dirname "$TO")
HELPER_PIN=${WS_VERIFY_HELPERS_PIN:-$(dirname "$0")/HELPERS.sha256}
for h in face-probe.mjs release-id.mjs; do
  ck "helper_${h}_exists" "$([ -f "$HD/$h" ] && echo yes || echo no)" yes
  [ -f "$HD/$h" ] || continue
  EHP=$(awk -v n="$h" '$2==n{print $1}' "$HELPER_PIN" 2>/dev/null | head -1)
  if [ -n "$EHP" ]; then
    ck "helper_${h}_sha256" "$(sha "$HD/$h")" "$EHP"
  else
    echo "INFO helper_${h}_sha256=$(sha "$HD/$h")（未提供 $HELPER_PIN，本项不作判据）"
  fi
  ck "helper_${h}_syntax" "$(node --check "$HD/$h" >/dev/null 2>&1 && echo ok || echo bad)" ok
done
echo "=== 用法自测（WS_EXPECTED_ROOT 非法值 → 在任何网络探测前退出 6） ==="
# 注意：无参调用 = 生产默认全量核验（只读但联网），它的退出码不是 6，别拿它当用法自测。
OUT=$(WS_EXPECTED_ROOT=__invalid__ bash "$TO" 2>&1); RC=$?
ck usage_exit "$RC" 6
has usage_verdict "$OUT" 'USAGE_ERROR'
echo "=== 调用方（只读枚举） ==="
CALLERS=$(grep -l "ws-verify-faces" /usr/local/bin/*.sh 2>/dev/null | tr '\n' ' ')
echo "  callers=${CALLERS:-none}"
for f in /usr/local/bin/cutover.sh /usr/local/bin/ws-prep.sh /usr/local/bin/ops-selftest.sh; do
  [ -f "$f" ] || { echo "  （$f 不存在）"; continue; }
  echo "  $f sha256=$(sha "$f")"
done
echo "=== 运行中服务面（只读） ==="
PUB=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:3200/healthz 2>/dev/null || true)
[ -n "$PUB" ] || PUB=000
DET=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:3200/healthz/detail 2>/dev/null || true)
[ -n "$DET" ] || DET=000
OPS=$(curl -s --max-time 3 http://127.0.0.1:3201/healthz 2>/dev/null || true)
ck public_healthz "$PUB" 200
ck detail_not_public "$DET" 404
echo "  ops_healthz=${OPS:-none}"

echo
echo "PROD_VERIFIER_CERT_TOTAL=$N  FAILS=$F"
[ "$F" -eq 0 ] && echo "PROD_VERIFIER_CERT=PASS" || echo "PROD_VERIFIER_CERT=FAIL"
exit "$F"
