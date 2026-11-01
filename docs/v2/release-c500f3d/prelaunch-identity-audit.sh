#!/usr/bin/env bash
# prelaunch-identity-audit.sh —— 发布身份机制复审（P2D）。
#
# 证明的是"身份是内容的函数"，不是"脚本声明的值"：
#   1 同树两次计算相同（确定性）
#   2 base / prev / r4 三棵树互不相同（唯一性）
#   3 改一个字节 → 身份变化；改回 → 身份恢复（敏感性 + 可逆）
#   4 批准记录里的 release_id == 最终树实算值（若给 WS_ROOT）
#   5 运行进程自报 == 批准身份（若给 WS_OPS_PORT）
#   6 核验器文件 sha256 == 树内钉住的期望值（工具版本绑定）
#
# 用法：WS_TREE=/srv/trees/r4 WS_TOOL=/srv/trees/r4/docs/v2/release-c500f3d \
#        [WS_BASE=/srv/trees/base] [WS_PREV=/srv/trees/prev] [WS_ROOT=...] [WS_OPS_PORT=3201] \
#        bash prelaunch-identity-audit.sh
set -uo pipefail
: "${WS_TREE:?}" "${WS_TOOL:?}"
N=0; F=0
ck() { N=$((N+1)); if [ "$2" = "$3" ]; then echo "PASS $1 = $2"; else echo "FAIL $1 = $2（期望 $3）"; F=$((F+1)); fi; }
differs() { [ "$2" != "$3" ] && echo different || echo same; }
ID() { node "$WS_TOOL/release-id.mjs" "$1"; }

echo "=== 1) 确定性：同一棵树算两次 ==="
ID_A=$(ID "$WS_TREE"); ID_B=$(ID "$WS_TREE")
ck identity_deterministic "$ID_A" "$ID_B"
ck identity_shape "$(grep -Ec '^[0-9a-f]{64}$' <<<"$ID_A")" 1

echo "=== 2) 唯一性：不同树不同身份 ==="
if [ -n "${WS_BASE:-}" ]; then ck identity_differs_base "$(differs x "$ID_A" "$(ID "$WS_BASE")")" different; fi
if [ -n "${WS_PREV:-}" ]; then ck identity_differs_prev "$(differs x "$ID_A" "$(ID "$WS_PREV")")" different; fi

echo "=== 3) 敏感性：改一个字节身份变，改回身份恢复 ==="
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ws-identity.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
cp -a "$WS_TREE" "$WORK/t" || { echo "FAIL 复制树失败"; exit 1; }
TARGET_FILE=$(find "$WORK/t" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/var/*' | LC_ALL=C sort | head -1)
[ -n "$TARGET_FILE" ] || { echo "FAIL 树里没有可比对的文件"; exit 1; }
BAK="$WORK/orig.bin"; cp "$TARGET_FILE" "$BAK"
ORIG_SIZE=$(wc -c < "$TARGET_FILE" | tr -d ' ')
if [ "$ORIG_SIZE" -gt 0 ]; then
  printf 'X' | dd of="$TARGET_FILE" bs=1 seek=0 conv=notrunc status=none
else
  printf 'X' >> "$TARGET_FILE"
fi
ID_MUT=$(ID "$WORK/t")
ck identity_changes_on_one_byte "$(differs x "$ID_A" "$ID_MUT")" different
cp "$BAK" "$TARGET_FILE"
ck identity_restores_after_revert "$(ID "$WORK/t")" "$ID_A"
echo "  （改动点：${TARGET_FILE#$WORK/t/} 原尺寸=$ORIG_SIZE 字节）"

echo "=== 4) 批准记录 == 最终树（若给 WS_ROOT） ==="
if [ -n "${WS_ROOT:-}" ]; then
  META="$WS_ROOT/state/approved-meta.txt"
  [ -f "$META" ] && ck approval_release_id_matches_tree "$(grep '^release_id=' "$META" | cut -d= -f2)" "$ID_A" \
    || { echo "FAIL 没有 $META"; F=$((F+1)); N=$((N+1)); }
  ck approved_sha_is_full_sha "$(printf '%s' "$(cat "$WS_ROOT/state/approved-sha" 2>/dev/null)" | grep -Ec '^[0-9a-f]{40}$')" 1
fi

echo "=== 5) 运行进程自报 == 批准身份（若给 WS_OPS_PORT） ==="
if [ -n "${WS_OPS_PORT:-}" ]; then
  RID=$(curl -s --max-time 3 "http://127.0.0.1:$WS_OPS_PORT/healthz" 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).release_id||"")}catch(e){console.log("")}})')
  ck runtime_release_id_matches_tree "$RID" "$ID_A"
  ck runtime_scheme "$(curl -s --max-time 3 "http://127.0.0.1:$WS_OPS_PORT/healthz" 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).release_id_scheme||"")}catch(e){console.log("")}})')" world-release-tree-v1
fi

echo "=== 6) 核验器版本绑定 ==="
V="$WS_TOOL/ws-verify-faces.sh"; P="$WS_TOOL/ws-verify-faces.sh.sha256"
H=$(sha256sum "$V" | cut -d' ' -f1)
E=$(awk 'NR==1{print $1}' "$P")
ck verifier_hash_matches_pin "$H" "$E"
ck verifier_pin_shape "$(grep -Ec '^[0-9a-f]{64}$' <<<"$E")" 1

echo
echo "IDENTITY_AUDIT_TOTAL=$N  FAILS=$F"
[ "$F" -eq 0 ] && echo "IDENTITY_AUDIT=PASS" || echo "IDENTITY_AUDIT=FAIL"
exit "$F"
