#!/usr/bin/env bash
# prelaunch-repo-regression.sh —— 仓库级完整回归清单执行器。
#
# 规则：
#   - 逐个执行 eval/*.mjs，记录真实退出码；非 0 = FAIL（不因"只是自测"降级）。
#   - 输出含 SKIP 且退出 0 的记为 SKIP，**不计入 PASS**。
#   - 需要外网/真实 provider/浏览器而本机不具备的，显式记 NOT_RUN + 原因，**不伪装成通过**。
#   - 末尾给总数/分类构成，退出码 = FAIL 数。
#
# 用法：bash prelaunch-repo-regression.sh [仓库根]
set -uo pipefail
ROOT=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
cd "$ROOT" || { echo "FAIL 进不了仓库根 $ROOT"; exit 2; }
export WS_PROVIDER=stub WS_SEARCH=fixture
# var/ 是 gitignored 的运行时目录（应用与自测都往里写 fixture）。git archive 出来的新树里没有它，
# 而 auth-selftest / budget-cap-selftest 直接写 var/xxx 不自己建目录 —— 先按它们的契约建好目录，
# 这不是放宽判据（仍要求套件自己跑绿），而是补上检出形态缺的那层目录。
mkdir -p "$ROOT/var" || { echo "FAIL 建不了 $ROOT/var"; exit 2; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ws-repo-reg.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

# 显式不跑的，写下真实原因（SKIP/NOT_RUN 都不算 PASS）
not_run_reason() {
  case "$1" in
    run.mjs) echo "真实 provider 压测（计费+日预算上限），不属于回归套件" ;;
    outcome-journeys.mjs) echo "外部活体服务驱动器，只留痕不判分" ;;
    public-entry-journey.mjs) echo "需要 playwright-core + 浏览器二进制，容器内不装" ;;
    date-selftest.child.mjs) echo "子进程模块，由 date-selftest.mjs 调用，不单独执行" ;;
    *) echo "" ;;
  esac
}

TOTAL=0; PASS=0; FAIL=0; SKIP=0; NOTRUN=0
FAILED_NAMES=""
for f in eval/*.mjs; do
  b=$(basename "$f")
  TOTAL=$((TOTAL+1))
  why=$(not_run_reason "$b")
  if [ -n "$why" ]; then
    echo "NOT_RUN  $b —— $why"
    NOTRUN=$((NOTRUN+1))
    continue
  fi
  # 每个套件独立超时；套件自己起停服务（端口固定），串行执行避免互相抢端口
  timeout 600 node "$f" > "$TMP/$b.log" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL     $b rc=$rc"
    tail -6 "$TMP/$b.log" | sed 's/^/         /'
    FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $b"
    continue
  fi
  if grep -qE '^SKIP[: ]' "$TMP/$b.log"; then
    echo "SKIP     $b —— $(grep -m1 -E '^SKIP[: ]' "$TMP/$b.log")"
    SKIP=$((SKIP+1))
    continue
  fi
  n_ok=$(grep -c '✓' "$TMP/$b.log" 2>/dev/null || true)
  n_ok=$(printf '%s' "${n_ok:-0}" | tr -d ' \r')
  echo "PASS     $b（断言✓=$n_ok）"
  PASS=$((PASS+1))
done

echo
echo "REPO_REGRESSION_TOTAL=$TOTAL  PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP  NOT_RUN=$NOTRUN"
[ -n "$FAILED_NAMES" ] && echo "REPO_REGRESSION_FAILED=$FAILED_NAMES"
echo "REPO_REGRESSION_SKIP_IS_NOT_PASS=yes"
[ "$FAIL" -eq 0 ] && echo "REPO_REGRESSION=PASS" || echo "REPO_REGRESSION=FAIL"
exit "$FAIL"
