#!/usr/bin/env bash
# git-metadata-adversarial.sh —— 独立构造 Git 元数据伪造，证明切流不会被骗。
#
# 两段：
#   A 语义段（纯 git，不碰切流）：证明 replace refs / info/grafts 确实能让"非后代提交"
#     在普通 git 眼里变成后代；并证明 GIT_NO_REPLACE_OBJECTS=1 只挡 replace、挡不住 grafts，
#     所以"拒绝其存在"这条前置检查是必要的，不是多余。
#   B 切流段（用真 cutover）：在一份**缓存副本**上投毒（不污染真实缓存），要求 cutover
#     以 CUTOVER=ABORT_GIT_METADATA_TAMPERED、退出码 3 中止，且 current / 进程 / 回执零变化；
#     清掉投毒后同一套参数能越过元数据闸（在更后面的核验器闸上被拒），证明拒绝是精确的。
#
# 用法（容器内）：WS_ROOT=... WS_CACHE=... WS_CUTOVER=... bash git-metadata-adversarial.sh
# 退出码：失败项数；末行 GIT_METADATA_ADVERSARIAL=PASS|FAIL
set -uo pipefail
: "${WS_ROOT:?}" "${WS_CACHE:?}" "${WS_CUTOVER:?}"
TARGET=${WS_TARGET:-$(cat "$WS_ROOT/state/approved-sha")}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ws-meta-adv.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

N=0; F=0
ck() { N=$((N+1)); if [ "$2" = "$3" ]; then echo "PASS $1 = $2"; else echo "FAIL $1 = $2（期望 $3）"; F=$((F+1)); fi; }
has() { N=$((N+1)); if printf '%s' "$2" | grep -qF -- "$3"; then echo "PASS $1 含「$3」"; else echo "FAIL $1 缺「$3」"; F=$((F+1)); fi; }
hasnt() { N=$((N+1)); if printf '%s' "$2" | grep -qF -- "$3"; then echo "FAIL $1 不该含「$3」"; F=$((F+1)); else echo "PASS $1 无「$3」"; fi; }
cutover_rc() { # 用给定 WS_CACHE / 额外环境跑 cutover，输出到 $TMP/out，返回退出码
  local cache=$1; shift
  ( cd "$WS_CUTOVER_DIR" && WS_ROOT="$WS_ROOT" WS_CACHE="$cache" WS_EMERG="${WS_EMERG:?}" \
      WS_VERIFY="${WS_VERIFY:?}" WS_GATE_BASE="${WS_GATE_BASE:?}" WS_RESOLVE_HOST="" \
      WS_RESTART_CMD="${WS_RESTART_CMD:?}" WS_PID_CMD="${WS_PID_CMD:?}" \
      WS_PUBLIC_PORT="${WS_PUBLIC_PORT:-3200}" WS_OPS_PORT="${WS_OPS_PORT:-3201}" \
      WS_POLL_TRIES=5 WS_MODE="${WS_MODE:-upgrade}" WS_ROLLBACK_TO="${WS_ROLLBACK_TO:-}" \
      env "$@" bash ./cutover.sh ) > "$TMP/out" 2>&1
  echo $?
}
snapshot() { # 现场指纹：current + pid + 回执数
  printf '%s|%s|%s' "$(readlink "$WS_ROOT/current")" \
    "$(curl -s --max-time 3 "http://127.0.0.1:${WS_OPS_PORT:-3201}/healthz" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).pid||"")}catch(e){console.log("")}})')" \
    "$(ls "$WS_ROOT"/state/cutover-*.txt 2>/dev/null | wc -l | tr -d ' ')"
}

echo "=== A) 纯 git 语义：伪造确实有效，防护也确实有边界 ==="
A="$TMP/mini"; git init -q -b v2 "$A"; git -C "$A" config user.email adv@local; git -C "$A" config user.name adv
printf 'a\n' > "$A/f"; git -C "$A" add f; git -C "$A" commit -q -m A; A_SHA=$(git -C "$A" rev-parse HEAD)
printf 'b\n' >> "$A/f"; git -C "$A" commit -qam B; B_SHA=$(git -C "$A" rev-parse HEAD)
# 无关的孤儿提交（攻击目标：它并不在发布线上）
O_TREE=$(git -C "$A" write-tree)
O_SHA=$(printf 'orphan\n' | git -C "$A" commit-tree "$O_TREE")
anc() { git -C "$A" merge-base --is-ancestor "$1" "$2" >/dev/null 2>&1; echo $?; }
anc_at() { git -C "$1" merge-base --is-ancestor "$2" "$3" >/dev/null 2>&1; echo $?; }
ck a_plain_not_ancestor "$(anc "$B_SHA" "$O_SHA")" 1

# replace：把孤儿提交对象替换成"父=发布线tip"的假提交
FAKE=$(printf 'forged\n' | git -C "$A" commit-tree "$O_TREE" -p "$B_SHA")
git -C "$A" replace "$O_SHA" "$FAKE"
ck a_replace_forges "$(anc "$B_SHA" "$O_SHA")" 0
ck a_git_no_replace_defends "$(GIT_NO_REPLACE_OBJECTS=1 anc_at "$A" "$B_SHA" "$O_SHA")" 1
git -C "$A" replace -d "$O_SHA" >/dev/null
ck a_replace_removed_restores "$(anc "$B_SHA" "$O_SHA")" 1

# grafts：info/grafts 直接把父关系写进 graft 文件
printf '%s %s\n' "$O_SHA" "$B_SHA" > "$A/.git/info/grafts"
ck a_grafts_forge "$(anc "$B_SHA" "$O_SHA")" 0
ck a_git_no_replace_does_not_stop_grafts "$(GIT_NO_REPLACE_OBJECTS=1 anc_at "$A" "$B_SHA" "$O_SHA")" 0
rm -f "$A/.git/info/grafts"
ck a_grafts_removed_restores "$(anc "$B_SHA" "$O_SHA")" 1

echo "=== B) 真 cutover：投毒必须在任何写入之前被拒 ==="
WS_CUTOVER_DIR=$(cd "$(dirname "$WS_CUTOVER")" && pwd)
SNAP0=$(snapshot)
REC0=$(ls "$WS_ROOT"/state/cutover-*.txt 2>/dev/null | wc -l | tr -d ' ')

cp -a "$WS_CACHE" "$TMP/cache-replace" || { echo "FAIL 复制缓存失败"; exit 1; }
cp -a "$WS_CACHE" "$TMP/cache-grafts" || { echo "FAIL 复制缓存失败"; exit 1; }
cp -a "$WS_CACHE" "$TMP/cache-clean" || { echo "FAIL 复制缓存失败"; exit 1; }
# 在副本里投毒（对象与 ref 都真实存在，不是空目录占位）
if git -C "$TMP/cache-replace" cat-file -e "$TARGET^{commit}" 2>/dev/null; then
  TTREE=$(git -C "$TMP/cache-replace" rev-parse "$TARGET^{tree}")
  F2=$(printf 'forged %s\n' "$TARGET" | git -C "$TMP/cache-replace" -c user.email=a@b -c user.name=a commit-tree "$TTREE" -p "$TARGET")
  git -C "$TMP/cache-replace" replace "$TARGET" "$F2"
else
  echo "  （目标 $TARGET 不在缓存里，退化为投毒一个已知提交）"
  ANY=$(git -C "$TMP/cache-replace" rev-parse HEAD 2>/dev/null || git -C "$TMP/cache-replace" rev-list -n1 --all | head -1)
  TTREE=$(git -C "$TMP/cache-replace" rev-parse "$ANY^{tree}")
  F2=$(printf 'forged\n' | git -C "$TMP/cache-replace" -c user.email=a@b -c user.name=a commit-tree "$TTREE" -p "$ANY")
  git -C "$TMP/cache-replace" replace "$ANY" "$F2"
fi
ck b_replace_ref_present "$(git -C "$TMP/cache-replace" for-each-ref --format='%(refname)' refs/replace | wc -l | tr -d ' ')" 1
RC=$(cutover_rc "$TMP/cache-replace"); OUT=$(cat "$TMP/out")
ck b_replace_exit "$RC" 3
has b_replace_token "$OUT" 'CUTOVER=ABORT_GIT_METADATA_TAMPERED'
ck b_replace_current_unchanged "$(snapshot)" "$SNAP0"
ck b_replace_no_receipt "$(ls "$WS_ROOT"/state/cutover-*.txt 2>/dev/null | wc -l | tr -d ' ')" "$REC0"

G_CHILD=$(git -C "$TMP/cache-grafts" rev-parse HEAD)
G_PARENT=$(git -C "$TMP/cache-grafts" rev-parse "$G_CHILD^" 2>/dev/null || echo "$G_CHILD")
printf '%s %s\n' "$G_CHILD" "$G_PARENT" > "$TMP/cache-grafts/info/grafts"
RC=$(cutover_rc "$TMP/cache-grafts"); OUT=$(cat "$TMP/out")
ck b_grafts_exit "$RC" 3
has b_grafts_token "$OUT" 'CUTOVER=ABORT_GIT_METADATA_TAMPERED'
ck b_grafts_current_unchanged "$(snapshot)" "$SNAP0"
ck b_grafts_no_receipt "$(ls "$WS_ROOT"/state/cutover-*.txt 2>/dev/null | wc -l | tr -d ' ')" "$REC0"

echo "=== C) 清掉投毒后同一套参数能越过元数据闸（拒绝是精确的，不是一律误伤） ==="
# 用"换了一份核验器"制造一个更靠后的闸：它能证明元数据闸已放行，而核验器闸仍按设计拒绝。
# 注意不能用 WS_VERIFY_SHA256 覆盖：树内 .sha256 优先，那个变量在有钉文件时不生效（本轮实测）。
cp "$WS_VERIFY" "$TMP/bad-verifier.sh"
printf '\n# tampered in adversarial test\n' >> "$TMP/bad-verifier.sh"
RC=$(cutover_rc "$TMP/cache-clean" WS_VERIFY="$TMP/bad-verifier.sh")
OUT=$(cat "$TMP/out")
ck c_clean_exit "$RC" 3
has c_clean_reaches_verifier_gate "$OUT" 'CUTOVER=ABORT_VERIFIER_IDENTITY_MISMATCH'
hasnt c_clean_not_metadata_rejected "$OUT" 'GIT_METADATA_TAMPERED'
ck c_clean_current_unchanged "$(snapshot)" "$SNAP0"
ck c_clean_no_receipt "$(ls "$WS_ROOT"/state/cutover-*.txt 2>/dev/null | wc -l | tr -d ' ')" "$REC0"

echo
echo "GIT_METADATA_ADVERSARIAL_TOTAL=$N  FAILS=$F"
[ "$F" -eq 0 ] && echo "GIT_METADATA_ADVERSARIAL=PASS" || echo "GIT_METADATA_ADVERSARIAL=FAIL"
exit "$F"
