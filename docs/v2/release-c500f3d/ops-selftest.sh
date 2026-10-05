#!/usr/bin/env bash
# ops-selftest.sh —— 切流工具链的回归自测（离线假面，0 外网、0 生产接触）
#
# 覆盖三件事，每件都配红绿一对（只见过一种状态的判据不算验证过）：
#   A. ws-verify-faces.sh 对双面/单面、字段缺失、身份不符、门失效的分类与退出码
#   B. cutover.sh 的关站边界：只有"公网面确实不可用"才允许 close；
#      新版诊断面出问题必须留现场不关站（这正是 2026-10-05 的兼容性缺口）
#   C. ws-env-put.sh 对无换行文件的安全性（我把 WS_SEARCH_KEY_2 改坏过的那一类事故）
#
# 用法：bash ops-selftest.sh          （退出码 0 = 全部通过）
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
VERIFY="$HERE/ws-verify-faces.sh"
ENVPUT="$HERE/ws-env-put.sh"
FIXTURE="$HERE/ops-fixture-face.mjs"
T=$(mktemp -d)
PIDS=""
FAILED=0
TOTAL=0
# 测试端口基址可换：共享机器上不能假设某几个端口一定空着
BASE=${WS_TEST_PORT_BASE:-4711}
P1=$((BASE));     O1=$((BASE+1))
PB=$((BASE+10));  OB=$((BASE+11))
DEAD1=$((BASE+88)); DEAD2=$((BASE+89))
FREE_OK=1
for p in $P1 $O1 $PB $OB $DEAD1 $DEAD2; do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$p/" 2>/dev/null; then
    printf 'FAIL  端口 %s 已被占用（这台机器上有别的服务/会话在跑）——换 WS_TEST_PORT_BASE 再跑\n' "$p"; FREE_OK=0
  fi
done
[ "$FREE_OK" = "1" ] || exit 6
printf '测试端口基址 %s（%s 对已确认空闲）\n' "$BASE" "3"

cleanup() {
  for p in $PIDS; do kill "$p" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT

# 假 ss：把「监听表」变成可控输入，这样 loopback 这项判据既能判绿也能判红
printf '#!/usr/bin/env bash\nprintf "LISTEN 0 511 127.0.0.1:%s 0.0.0.0:*\\n" %s\n' "$O1" "$O1" > "$T/ss-loop"
printf '#!/usr/bin/env bash\nprintf "LISTEN 0 511 0.0.0.0:%s 0.0.0.0:*\\n" %s\n'   "$O1" "$O1" > "$T/ss-wide"
printf '#!/usr/bin/env bash\nexit 1\n'                                            > "$T/ss-missing"
chmod +x "$T/ss-loop" "$T/ss-wide" "$T/ss-missing"

# 静态探针的输入：一个"新版"发布树（含 opsPort），一个"旧版"发布树（不含）
mkdir -p "$T/rel-dual/server" "$T/rel-legacy/server"
printf 'const CFG = { opsPort: 3201 };\n' > "$T/rel-dual/server/world.mjs"
printf 'const CFG = { webDir: 1 };\n'      > "$T/rel-legacy/server/world.mjs"

ok()   { TOTAL=$((TOTAL+1)); printf '  \033[32m✓\033[0m %-58s %s\n' "$1" "${2:-}"; }
no()   { TOTAL=$((TOTAL+1)); FAILED=$((FAILED+1)); printf '  \033[31m✗\033[0m %-58s %s\n' "$1" "${2:-}"; }
SKIPPED=0
skip() { SKIPPED=$((SKIPPED+1)); printf '  \033[33m-\033[0m %-58s %s\n' "$1" "${2:-}"; }
# 本平台若能真建符号链接才允许跑切流语义；否则必须显式 SKIP，绝不静默算过
have_symlinks() { mkdir -p "$T/symdir"; rm -f "$T/symprobe"; ln -s "$T/symdir" "$T/symprobe" 2>/dev/null && [ -L "$T/symprobe" ]; }
eq()   { # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1" "=$3"; else no "$1" "期望 $2 实得 $3"; fi
}
has()  { if printf '%s' "$3" | grep -q "$2"; then ok "$1" "含 /$2/"; else no "$1" "缺 /$2/（输出：$(printf '%s' "$3" | tr '\n' ' ' | head -c 120)）"; fi; }

start_fixture() { # start_fixture <pub> <ops> [VAR=val ...]  → 等就绪
  local pub="$1" ops="$2"; shift 2
  local log="$T/fx-$pub.log"
  env PUB_PORT="$pub" OPS_PORT="$ops" "$@" node "$FIXTURE" > "$log" 2>&1 &
  local pid=$!
  PIDS="$PIDS $pid"
  local i=0
  while [ $i -lt 100 ]; do
    if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$pub/healthz"; then return 0; fi
    if grep -q FIXTURE_FAIL "$log" 2>/dev/null; then return 1; fi
    sleep 0.1; i=$((i+1))
  done
  return 1
}
stop_fixture() { for p in $PIDS; do kill "$p" 2>/dev/null; done; PIDS=""; sleep 0.3; }

vrun() { # vrun <label> <expected_exit> [VAR=val ...]
  local label="$1" exp="$2"; shift 2
  local out code
  out=$(env WS_RESOLVE_HOST= WS_CURL_TIMEOUT=4 "$@" bash "$VERIFY" 2>&1); code=$?
  eq "$label 退出码" "$exp" "$code"
  if [ "$code" != "$exp" ]; then printf '%s\n' "$out" | grep -E 'FAIL|VERDICT|MODE=|SKIP' | sed 's/^/        ↳ /'; fi
  LAST_OUT="$out"; LAST_CODE="$code"
}

# ───────────────────────── A. 核验器 ─────────────────────────
echo "=== A. ws-verify-faces.sh 的面判定 ==="
# A1 旧版单面（诊断字段仍在公网、没有 3201）→ 应判 PASS，且明确标出 legacy
if start_fixture $P1 0 MODE=legacy; then
  vrun "A1 legacy 单面（回滚状态）" 0 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_TARGET_REL="$T/rel-legacy" WS_SS_CMD=echo
  eq "A1 MODE" "legacy_single_face" "$(printf '%s' "$LAST_OUT" | grep '^MODE=' | cut -d= -f2)"
  has "A1 打出旧版警告" "WARN=LEGACY_SINGLE_FACE" "$LAST_OUT"
  stop_fixture
else no "A1 fixture 起不来" ""; fi

# A2 新版双面健康 → PASS + MODE=dual_face
if start_fixture $P1 $O1 MODE=dual PID=4242; then
  vrun "A2 dual 双面健康" 0 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_TARGET_REL="$T/rel-dual" WS_SS_CMD="$T/ss-loop"
  eq "A2 MODE" "dual_face" "$(printf '%s' "$LAST_OUT" | grep '^MODE=' | cut -d= -f2)"
  stop_fixture
else no "A2 fixture 起不来" ""; fi

# A3 新版但诊断面没监听 → 退出码 2（不是关站码）
if start_fixture $P1 0 MODE=dual; then
  vrun "A3 dual 但 3201 缺失" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A3 fixture 起不来" ""; fi

# A4 诊断面自报 app_port 与公网口不符（串台到别的服务）→ 2
if start_fixture $P1 $O1 MODE=dual APP_PORT=1; then
  vrun "A4 app_port 自报不符" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A4 fixture 起不来" ""; fi

# A5 诊断面自报 pid 与 MainPID 不符 → 2
if start_fixture $P1 $O1 MODE=dual PID=7; then
  vrun "A5 pid 与服务不符" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A5 fixture 起不来" ""; fi

# A6 诊断面少字段（fail_closed 不见了）→ 2
if start_fixture $P1 $O1 MODE=dual DROP=fail_closed; then
  vrun "A6 诊断字段不完整" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  has "A6 点名缺哪个字段" "fail_closed" "$LAST_OUT"
  stop_fixture
else no "A6 fixture 起不来" ""; fi

# A7 公网面把诊断细节外露（/healthz/detail 给 200）→ 3
if start_fixture $P1 $O1 MODE=dual DETAIL=200; then
  vrun "A7 detail 对外可见" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A7 fixture 起不来" ""; fi

# A8 访问门失效（未登录 POST /api/world 返回 200）→ 3
if start_fixture $P1 $O1 MODE=dual API=200; then
  vrun "A8 未登录 API 被放行" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A8 fixture 起不来" ""; fi

# A9 首页不再 302 → 3
if start_fixture $P1 $O1 MODE=dual ROOT=200; then
  vrun "A9 未登录首页放行" 3 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD=echo
  stop_fixture
else no "A9 fixture 起不来" ""; fi

# A10 什么都没监听 → 5（唯一可能关站的码）
vrun "A10 服务完全不可达" 5 WS_PUBLIC_PORT=$DEAD1 WS_OPS_PORT=$DEAD2 WS_GATE_BASE="http://127.0.0.1:$DEAD1" WS_SS_CMD=echo

# A11 静态探针与运行时矛盾（代码说双面，跑出来是单面）→ 4
if start_fixture $P1 0 MODE=legacy; then
  FAKE="$T/rel-dual"; mkdir -p "$FAKE/server"; printf 'const CFG={opsPort:3201}\n' > "$FAKE/server/world.mjs"
  vrun "A11 静态与运行时矛盾" 4 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_TARGET_REL="$FAKE" WS_SS_CMD=echo
  stop_fixture
else no "A11 fixture 起不来" ""; fi

# A12 诊断面被别的地址绑走（非 loopback）→ 2
if start_fixture $P1 $O1 MODE=dual PID=4242; then
  vrun "A12 诊断口非 loopback 绑定" 2 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD="$T/ss-wide"
  stop_fixture
else no "A12 fixture 起不来" ""; fi

# A13 ss 不可用 → 该项必须记 SKIP，不许冒充通过
if start_fixture $P1 $O1 MODE=dual PID=4242; then
  vrun "A13 ss 不可用时不冒充通过" 0 WS_PUBLIC_PORT=$P1 WS_OPS_PORT=$O1 WS_GATE_BASE="http://127.0.0.1:$P1" WS_EXPECT_PID=4242 WS_SS_CMD="$T/ss-missing"
  has "A13 明确标 SKIP" "ops_face_loopback_only.*SKIP" "$LAST_OUT"
  stop_fixture
else no "A13 fixture 起不来" ""; fi

# ─────────────────────── B. 切流边界 ───────────────────────
echo "=== B. cutover.sh 的关站边界（假 EMERG 记账）==="
if have_symlinks; then
SHA=aaaa00000000000000000000000000000000aaaa
PREV=bbbb00000000000000000000000000000000bbbb
SB=$T/root
mkdir -p "$SB/state" "$SB/etc" "$SB/releases/$SHA/server" "$SB/releases/$PREV/server"
printf '%s\n' "$SHA" > "$SB/state/approved-sha"
ln -sfn "$SB/releases/$PREV" "$SB/current"
: > "$T/emerg.log"
cat > "$T/fake-emerg.sh" <<'EM'
#!/usr/bin/env bash
echo "$1" >> "$EMERG_LOG"
exit 0
EM
chmod +x "$T/fake-emerg.sh"
printf 'const CFG = { opsPort: 3201 };\n' > "$SB/releases/$SHA/server/world.mjs"   # 新版双面
printf 'const CFG = { webDir: 1 };\n'        > "$SB/releases/$PREV/server/world.mjs" # 旧版单面

crun() { # crun <label> <expected_exit> <grep-for-verdict> <pub> <ops-or-0> [extra VAR=val]
  local label="$1" exp="$2" needle="$3" pub="$4" ops="$5"; shift 5
  local out code
  out=$(env WS_ROOT="$SB" WS_EMERG="$T/fake-emerg.sh" WS_VERIFY="$VERIFY" WS_ROTATE_SECRET=0 \
        WS_RESTART_CMD=true WS_PID_CMD="echo 4242" EMERG_LOG="$T/emerg.log" \
        WS_PUBLIC_PORT="$pub" WS_OPS_PORT="$ops" WS_GATE_BASE="http://127.0.0.1:$pub" \
        WS_RESOLVE_HOST= WS_CURL_TIMEOUT=4 WS_POLL_TRIES=3 WS_SS_CMD="$T/ss-missing" "$@" \
        bash "$HERE/cutover.sh" 2>&1); code=$?
  CRUN_OUT="$out"
  eq "$label 退出码" "$exp" "$code"
  has "$label 结论行" "$needle" "$out"
}

# B1 新版双面健康 → 切流成功，且 current 真的换了，且一次都没关站
if start_fixture $PB $OB MODE=dual PID=4242; then
  crun "B1 新版健康切换" 0 "CUTOVER=OK" $PB $OB
  eq "B1 current 已切换" "$SHA" "$(basename "$(readlink "$SB/current")")"
  eq "B1 关站次数" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  stop_fixture
else no "B1 fixture 起不来" ""; fi

# B2 公网面看起来正常但诊断面没起来 → 必须"留现场不关站"（旧版会在这里误关）
: > "$T/emerg.log"; ln -sfn "$SB/releases/$PREV" "$SB/current"
if start_fixture $PB 0 MODE=dual; then
  crun "B2 诊断面缺失" 1 "CUTOVER=FAILED_SCENE_PRESERVED" $PB $OB
  eq "B2 关站次数（关键：必须 0）" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  stop_fixture
else no "B2 fixture 起不来" ""; fi

# B3 真的什么都没起 → 才允许关站
: > "$T/emerg.log"
crun "B3 服务确实不可用" 1 "CUTOVER=FAILED_AND_CLOSED" $DEAD1 $DEAD2
eq "B3 关站次数（应恰好 1）" "1" "$(grep -c '^close$' "$T/emerg.log" || true)"

# B4 回滚到旧版单面 → 认出 legacy 并完成，不关站
: > "$T/emerg.log"
printf '%s\n' "$PREV" > "$SB/state/approved-sha"
if start_fixture $PB 0 MODE=legacy; then
  crun "B4 旧版回滚路径" 0 "CUTOVER=OK" $PB $OB
  eq "B4 关站次数" "0" "$(grep -c '^close$' "$T/emerg.log" || true)"
  has "B4 认为目标是旧面" "legacy_single_face" "$CRUN_OUT"
  stop_fixture
else no "B4 fixture 起不来" ""; fi

else
  skip "B1 新版健康切换"      "本平台 ln -s 不产生符号链接，切流语义需在 Linux 上验（见报告）"
  skip "B2 诊断面缺失不关站"  "同上"
  skip "B3 真不可用才关站"    "同上"
  skip "B4 旧版回滚路径"      "同上"
fi

# ─────────────────────── C. env 写入安全 ───────────────────────
echo "=== C. ws-env-put.sh 的无换行防护 ==="
mk_env() { # mk_env <path> <trailing_newline:1|0>
  printf 'WS_PROVIDER=openai_compatible\nWS_LLM_KEY=sk-fixture-not-real\nWS_SEARCH_KEY_2=tvly-fixture==' > "$1"
  [ "$2" = "1" ] && printf '\n' >> "$1"
}
line_hash() { sed -n "$2p" "$1" | tr -d '\n' | sha256sum | cut -c1-12; }

# C1 末行无换行（事故现场）：追加后原有一行不许被污染
F="$T/env-noNL"; mk_env "$F" 0
before_sensitive=$(line_hash "$F" 3); before_bytes=$(wc -c < "$F")
OUT=$(env WS_ENV_FILE="$F" bash "$ENVPUT" WS_OPS_PORT 3201 2>&1); code=$?
eq "C1 无换行文件退出码" "0" "$code"
has "C1 报告动作" "action=appended" "$OUT"
eq "C1 WS_SEARCH_KEY_2 未变" "$before_sensitive" "$(line_hash "$F" 3)"
eq "C1 行首锚定=1" "1" "$(grep -c '^WS_OPS_PORT=' "$F" || true)"
eq "C1 全文出现=1（无粘连）" "1" "$(grep -c 'WS_OPS_PORT=' "$F" || true)"
eq "C1 字节算式" "$((before_bytes + 1 + 17))" "$(wc -c < "$F")"
eq "C1 行数" "4" "$(wc -l < "$F")"
# C1b 同一把尺子的红侧：预先造成粘连形状，--check 必须判红
BAD="$T/env-polluted"; mk_env "$BAD" 1; printf 'WS_OTHER=xWS_OPS_PORT=3201\n' >> "$BAD"
env WS_ENV_FILE="$BAD" bash "$ENVPUT" --check WS_OPS_PORT > /dev/null 2>&1
eq "C1b 污染形状必须判红" "2" "$?"
env WS_ENV_FILE="$F" bash "$ENVPUT" --check WS_OPS_PORT > /dev/null 2>&1
eq "C1c 干净文件判绿" "0" "$?"

# C2 末行有换行：只多一行，其余逐行不动
G="$T/env-NL"; mk_env "$G" 1
g_before=$(sed '4d' "$G" | sha256sum | cut -c1-12)
OUT=$(env WS_ENV_FILE="$G" bash "$ENVPUT" WS_OPS_PORT 3201 2>&1); code=$?
eq "C2 有换行文件退出码" "0" "$code"
eq "C2 行数" "4" "$(wc -l < "$G")"
eq "C2 原有三行未动" "$g_before" "$(sed '4d' "$G" | sha256sum | cut -c1-12)"

# C3 幂等：再写一次同值，内容一字不变
H="$T/env-idem"; mk_env "$H" 0
env WS_ENV_FILE="$H" bash "$ENVPUT" WS_OPS_PORT 3201 > /dev/null 2>&1
c1v=$(sha256sum "$H" | cut -c1-12)
OUT=$(env WS_ENV_FILE="$H" bash "$ENVPUT" WS_OPS_PORT 3201 2>&1)
c2v=$(sha256sum "$H" | cut -c1-12)
eq "C3 二次写入内容不变" "$c1v" "$c2v"
has "C3 第二次是 replaced" "action=replaced" "$OUT"
eq "C3 锚定仍为 1" "1" "$(grep -c '^WS_OPS_PORT=' "$H" || true)"

# C4 改值：只动那一行，且含 '=' 的 base64 值不许被牵连
K="$T/env-val"; mk_env "$K" 1
kv_before=$(line_hash "$K" 3)
env WS_ENV_FILE="$K" bash "$ENVPUT" WS_OPS_PORT 3202 > /dev/null 2>&1
eq "C4 改值生效" "WS_OPS_PORT=3202" "$(grep '^WS_OPS_PORT=' "$K")"
eq "C4 敏感行仍未动" "$kv_before" "$(line_hash "$K" 3)"

# C5 用法错误必须拒写且文件不变
M="$T/env-bad"; mk_env "$M" 1; m0=$(sha256sum "$M" | cut -c1-12)
env WS_ENV_FILE="$M" bash "$ENVPUT" WS_OPS_PORT "" > /dev/null 2>&1; eq "C5 空值被拒" "6" "$?"
env WS_ENV_FILE="$M" bash "$ENVPUT" bad_lower 1   > /dev/null 2>&1; eq "C5 小写键被拒" "6" "$?"
env WS_ENV_FILE="$M" bash "$ENVPUT" WS_NEW "a
b" > /dev/null 2>&1; eq "C5 含换行的值被拒" "6" "$?"
eq "C5 文件一字未动" "$m0" "$(sha256sum "$M" | cut -c1-12)"

# C6 备份确实在位且可用
eq "C6 生成了备份" "yes" "$(ls "$T/env-noNL".bak-envput-* >/dev/null 2>&1 && echo yes || echo no)"

# C7 「末行有没有换行」这条读数本身（上一版就是它错，导致给有换行的文件多加空行）
PNL="$T/probe-nl"; PNN="$T/probe-nonl"; mk_env "$PNL" 1; mk_env "$PNN" 0
has "C7 有换行 → 读成 yes" "is_newline  *yes" "$(env WS_ENV_FILE="$PNL" bash "$ENVPUT" --check WS_PROVIDER 2>&1)"
has "C7 无换行 → 读成 no"  "is_newline  *no"  "$(env WS_ENV_FILE="$PNN" bash "$ENVPUT" --check WS_PROVIDER 2>&1)"

# ─────────────────────── D. 语法与静态检查 ───────────────────────
echo "=== D. 语法 / 静态检查 ==="
for f in cutover.sh ws-verify-faces.sh ws-env-put.sh ops-selftest.sh; do
  if bash -n "$HERE/$f" 2> "$T/syn"; then ok "bash -n $f" ""; else no "bash -n $f" "$(cat "$T/syn" | head -2)"; fi
done
if node --check "$FIXTURE" 2> "$T/syn2"; then ok "node --check fixture" ""; else no "node --check fixture" "$(head -2 "$T/syn2")"; fi
# 自测绝不允许碰生产路径：每一次调用 ENVPUT 都必须显式带着 WS_ENV_FILE 指向临时文件
unguarded=$(grep '\$ENVPUT' "$0" | grep -vc 'WS_ENV_FILE=' || true)
eq "每次 ws-env-put 调用都被 WS_ENV_FILE 圈住" "0" "${unguarded:-0}"
unguarded2=$(grep 'bash "\$HERE/cutover.sh"' "$0" | wc -l)
eq "cutover 调用只经由 crun（带 WS_ROOT 沙箱）" "1" "$unguarded2"

echo
printf '自测合计 %s 项，失败 %s 项，跳过 %s 项\n' "$TOTAL" "$FAILED" "$SKIPPED"
[ "$SKIPPED" = "0" ] || echo "注意：有 $SKIPPED 项被跳过（本平台缺能力）—— 跳过 ≠ 通过，须在 Linux 上补跑"
[ "$FAILED" = "0" ] || exit 1
[ "$SKIPPED" = "0" ] || exit 3
echo "OPS_SELFTEST=PASS"
