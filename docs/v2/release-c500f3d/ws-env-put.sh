#!/usr/bin/env bash
# 安全地往 key=value 配置里写入一个变量（默认对象：World Space 生产 env）
#
# 为什么有这支脚本（2026-10-05 真实事故）：
#   我用 `printf 'K=V\n' >> env` 追加 WS_OPS_PORT，而那个文件**末行没有换行符**，
#   于是 17 个字节直接粘进了 WS_SEARCH_KEY_2 的值尾部 —— 一把真实密钥被静默改坏。
#   `>>` 不关心前一个字节是什么；这条判据必须由脚本守住，不能靠人记得住。
#
# 它保证的事（都在 --check / 写后自验里可被读出）：
#   1. 写前先备份并 cmp 证明备份可读；末字节不是换行时先补一个换行再动别的
#   2. 除目标 KEY 那一行之外，其余每一行逐字节不变（用「删掉 KEY 行后整体 cmp」证明）
#   3. 不许出现污染形状：KEY= 只能出现在行首（值里夹着 KEY= 就是事故现场）
#   4. 原地 cat 覆盖，保留 inode / 权限 / 属主（不新建文件，避免 mode 漂成 644）
#   5. 任何一步不过 → 自动从备份还原，退出码 2，且全程不打印任何值
#
# 用法：
#   ws-env-put.sh [--file F] KEY VALUE      写入（幂等）
#   ws-env-put.sh [--file F] --check KEY    只审计：该键是否只有行首一处、文件有无粘连形状
#   ws-env-put.sh [--file F] --dry-run KEY VALUE   只做校验与比对，不落盘
#
# 退出码：0 成功或无需改动 · 2 校验不过（已还原/未落盘） · 6 用法或环境错误
set -uo pipefail

FILE="${WS_ENV_FILE:-/opt/world-space/shared/env/world-space.env}"
MODE=put; KEY=""; VAL=""
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --file)     FILE="$2"; shift 2 ;;
    --check)    MODE=check; shift ;;
    --dry-run)  DRY=1; shift ;;
    -h|--help)  sed -n '1,30p' "$0"; exit 0 ;;
    *)          if [ -z "$KEY" ]; then KEY="$1"; else VAL="$1"; fi; shift ;;
  esac
done

[ -n "$KEY" ] || { echo "FAIL: 需要 KEY"; exit 6; }
printf '%s' "$KEY" | grep -qE '^[A-Z][A-Z0-9_]*$' || { echo "FAIL: KEY 必须是大写下划线形状（不是 '$KEY'）"; exit 6; }
if [ "$MODE" = put ]; then
  [ -n "$VAL" ] || { echo "FAIL: 写入需要非空 VALUE（要删键请人工做，这里不提供）"; exit 6; }
  case "$VAL" in *$'\n'*) echo "FAIL: VALUE 不许含换行"; exit 6 ;; esac
fi
[ -f "$FILE" ] || { echo "FAIL: 文件不存在 $FILE"; exit 6; }
[ -r "$FILE" ] || { echo "FAIL: 文件不可读 $FILE"; exit 6; }
[ "$MODE" = check ] || [ -w "$FILE" ] || { echo "FAIL: 文件不可写 $FILE"; exit 6; }

say() { printf '  %-46s %s\n' "$1" "$2"; }

if [ "$MODE" = check ]; then
  n_anchor=$(grep -c "^$KEY=" "$FILE" || true); n_any=$(grep -c "$KEY=" "$FILE" || true)
  say "check_key_anchor_lines" "$n_anchor"
  say "check_key_appearances" "$n_any"
  lastb=$(tail -c1 "$FILE")
  say "check_last_byte_is_newline" "$([ -z "$lastb" ] && echo yes || echo no)"
  if [ "$n_any" -ne "$n_anchor" ]; then say "VERDICT" "POLLUTED（有 $((n_any-n_anchor)) 处 KEY= 落在值里）"; exit 2; fi
  if [ "$n_anchor" -gt 1 ]; then say "VERDICT" "DUPLICATED（同名键 $n_anchor 行）"; exit 2; fi
  say "VERDICT" "CLEAN"; exit 0
fi

ORIG_BYTES=$(wc -c < "$FILE")
ORIG_LINES=$(wc -l < "$FILE")
# 末字节是不是换行：命令替换会吃掉尾部换行，所以「取末字节后仍非空」才代表末行没有换行。
# （早先用 `tail -c1 | wc -c` 判断，两种情况都得到 1，于是给有换行的文件多加了一个空行。）
NEEDS_nl=0
[ -n "$(tail -c1 "$FILE")" ] && NEEDS_nl=1
say "pre_last_byte_is_newline" "$([ "$NEEDS_nl" -eq 0 ] && echo yes || echo "no（先补换行再追加）")"
say "pre_bytes_lines" "$ORIG_BYTES 字节 / $ORIG_LINES 行"

TMPD=$(mktemp -d) || { echo "FAIL: mktemp"; exit 6; }
trap 'rm -rf "$TMPD"' EXIT
O="$TMPD/orig"; N="$TMPD/new"; NN="$TMPD/newnorm"
cat "$FILE" > "$O"
{ cat "$O"; [ "$NEEDS_nl" -eq 1 ] && printf '\n'; } > "$NN"
if [ "$(grep -c "^$KEY=" "$NN" || true)" -gt 0 ]; then
  awk -v k="$KEY" -v v="$VAL" 'BEGIN{p="^"k"="} $0 ~ p {print k"="v; next} {print}' "$NN" > "$N"
  action=replaced
else
  cp "$NN" "$N"; printf '%s=%s\n' "$KEY" "$VAL" >> "$N"; action=appended
fi

# ---- 写前自验：删掉 KEY 行之后，其余内容必须与（补过换行的）原件逐字节相同 ----
sed "\|^$KEY=|d" "$NN" > "$TMPD/o.k"; sed "\|^$KEY=|d" "$N" > "$TMPD/n.k"
if ! cmp -s "$TMPD/o.k" "$TMPD/n.k"; then
  say "verify_other_lines_untouched" "FAIL（其余行有变动，放弃写入）"; exit 2
fi
say "verify_other_lines_untouched" "PASS"
na=$(grep -c "^$KEY=" "$N" || true); ny=$(grep -c "$KEY=" "$N" || true)
if [ "$na" -ne 1 ] || [ "$ny" -ne 1 ]; then
  say "verify_no_pollution_shape" "FAIL 行首=$na 出现=$ny"; exit 2
fi
say "verify_no_pollution_shape" "PASS（行首 1、全文 1）"
nl_c=$(wc -l < "$N")
if [ "$action" = appended ] && [ "$nl_c" -ne "$(( $(wc -l < "$NN") + 1 ))" ]; then
  say "verify_line_arithmetic" "FAIL 期望 $(( $(wc -l < "$NN") + 1 )) 实得 $nl_c"; exit 2
fi
say "verify_line_count" "$nl_c"

if [ "$DRY" = "1" ]; then
  say "dry_run" "未落盘（新内容 $TMPD 内已比对通过）"; echo "ENVPUT=DRYRUN_OK key=$KEY action=$action"; exit 0
fi

BAK="$FILE.bak-envput-$(date +%Y%m%d-%H%M%S)"
cp -a "$FILE" "$BAK" || { say "backup" "FAIL"; exit 2; }
cmp -s "$FILE" "$BAK" || { say "backup_cmp" "FAIL（备份与原件不同，放弃写入）"; exit 2; }
say "backup" "$BAK"

cat "$N" > "$FILE" || { say "write" "FAIL，正在还原"; cat "$BAK" > "$FILE"; echo "ENVPUT=FAILED_AND_RESTORED"; exit 2; }
cmp -s "$FILE" "$N" || { say "writeback_cmp" "FAIL，正在还原"; cat "$BAK" > "$FILE"; echo "ENVPUT=FAILED_AND_RESTORED"; exit 2; }
say "post_bytes_lines" "$(wc -c < "$FILE") 字节 / $(wc -l < "$FILE") 行"
say "post_perm_owner" "$(stat -c '%a %U:%G' "$FILE")"
printf 'ENVPUT=OK key=%s action=%s file=%s backup=%s\n' "$KEY" "$action" "$FILE" "$BAK"
