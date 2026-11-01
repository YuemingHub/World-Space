#!/usr/bin/env bash
# install-verifier.sh —— 把被钉住的核验器（含两个同目录辅助文件）装进生产。
# 需要 Owner 批准后以 root 执行；本脚本自身不判断"该不该装"，只保证"装得可证、错了可退"。
#
# 为什么要带辅助文件：ws-verify-faces.sh 用 $HERE/face-probe.mjs 做静态面探针、
# 用 $HERE/release-id.mjs 从批准发布树现算身份。生产 /usr/local/bin 现在两个都没有；
# 只装核验器本体 → 每次核验都 STATIC_PROBE_FAILED(6)，切流永远拿不到 OK。所以三件必须同装。
#
# 性质：幂等 / 先备份后写 / 装完读回校验 / 失败自动还原 / 不删任何旧文件。
# 全部判据不过就零写入退出；写入动作只有同一目录内的 rename（原子）。
#
# 用法（生产）：
#   sudo WS_VERIFY_EXPECT=<64hex> bash install-verifier.sh
#   可选：WS_VERIFY_SRC=<path>/ws-verify-faces.sh  WS_VERIFY_PIN_SRC=<path>/ws-verify-faces.sh.sha256
#         WS_VERIFY_HELPERS_PIN=<path>/HELPERS.sha256  WS_VERIFY_TO=/usr/local/bin/ws-verify-faces.sh
#         WS_BACKUP_ROOT=/root/backups
#   辅助文件默认从核验器同目录取：face-probe.mjs / release-id.mjs，装到核验器同目录。
#
# 退出码：0 成功（或已是最新）/ 2 用法或前置不满足（零写入）/ 3 读回不一致（已自动还原）
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${WS_VERIFY_SRC:-$HERE/ws-verify-faces.sh}
PIN_SRC=${WS_VERIFY_PIN_SRC:-$HERE/ws-verify-faces.sh.sha256}
HELPER_PIN=${WS_VERIFY_HELPERS_PIN:-$HERE/HELPERS.sha256}
TO=${WS_VERIFY_TO:-/usr/local/bin/ws-verify-faces.sh}
PIN_TO=${WS_VERIFY_PIN_TO:-$TO.sha256}
TO_DIR=$(dirname "$TO")
EXPECT=${WS_VERIFY_EXPECT:-$(awk 'NR==1{print $1}' "$PIN_SRC" 2>/dev/null || true)}
BACKUP_ROOT=${WS_BACKUP_ROOT:-/root/backups}
STAMP=$(date +%Y%m%d-%H%M%S)
B="$BACKUP_ROOT/world-space-verifier-$STAMP"
REC="$B/receipt.txt"
HELPERS="face-probe.mjs release-id.mjs"

say() { printf '%s\n' "$*"; }
fail() { say "VERIFIER_INSTALL=FAIL_$1  $2"; exit "${3:-2}"; }
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
helper_expect() { awk -v n="$1" '$2==n{print $1}' "$HELPER_PIN" 2>/dev/null | head -1; }

[ "$(id -u)" = "0" ] || fail ROOT_REQUIRED "必须以 root 执行（安装目录 /usr/local/bin）"
[ -f "$SRC" ] || fail SOURCE_MISSING "找不到源文件 $SRC"
[ -f "$PIN_SRC" ] || fail PIN_MISSING "找不到哈希钉 $PIN_SRC"
[ -f "$HELPER_PIN" ] || fail HELPERS_PIN_MISSING "找不到辅助文件哈希钉 $HELPER_PIN"
printf '%s' "$EXPECT" | grep -Eq '^[0-9a-f]{64}$' || fail EXPECT_INVALID "期望哈希不是 64 位十六进制：'$EXPECT'"
SRC_H=$(sha "$SRC"); [ "$SRC_H" = "$EXPECT" ] || fail SOURCE_HASH_MISMATCH "源文件 sha256=$SRC_H ≠ 期望 $EXPECT"
bash -n "$SRC" || fail SOURCE_SYNTAX "源文件 bash 语法不通过"
for c in bash curl sha256sum node stat install mv awk cp ls; do
  command -v "$c" >/dev/null 2>&1 || fail DEP_MISSING "缺命令 $c"
done
[ -d "$TO_DIR" ] || fail TARGET_DIR_MISSING "目标目录不存在：$TO_DIR"
SRC_DIR=$(dirname "$SRC")
for h in $HELPERS; do
  [ -f "$SRC_DIR/$h" ] || fail HELPER_SOURCE_MISSING "找不到辅助源文件 $SRC_DIR/$h"
  E=$(helper_expect "$h")
  printf '%s' "$E" | grep -Eq '^[0-9a-f]{64}$' || fail HELPER_PIN_INVALID "$HELPER_PIN 里没有 $h 的合法哈希"
  H=$(sha "$SRC_DIR/$h"); [ "$H" = "$E" ] || fail HELPER_HASH_MISMATCH "$h sha256=$H ≠ 期望 $E"
  node --check "$SRC_DIR/$h" >/dev/null 2>&1 || fail HELPER_SYNTAX "$h node 语法不通过"
done

PRE_EXISTED=no; PRE_H=""; PRE_MODE=""; PRE_OWNER=""
if [ -f "$TO" ]; then
  PRE_EXISTED=yes; PRE_H=$(sha "$TO"); PRE_MODE=$(stat -c '%a' "$TO"); PRE_OWNER=$(stat -c '%U:%G' "$TO")
fi

CURRENT=yes
[ "$PRE_H" = "$EXPECT" ] || CURRENT=no
[ -f "$PIN_TO" ] && [ "$(awk 'NR==1{print $1}' "$PIN_TO")" = "$EXPECT" ] || CURRENT=no
for h in $HELPERS; do
  [ -f "$TO_DIR/$h" ] && [ "$(sha "$TO_DIR/$h")" = "$(helper_expect "$h")" ] || CURRENT=no
done
if [ "$CURRENT" = "yes" ]; then
  say "VERIFIER_INSTALL=NOOP_ALREADY_CURRENT  sha256=$EXPECT"
  exit 0
fi

mkdir -p "$B" || fail BACKUP_DIR "建不了备份目录 $B"
{ printf 'mode=install\nat=%s\ntarget=%s\nexpected=%s\npre_existed=%s\npre_sha256=%s\npre_mode=%s\npre_owner=%s\n' \
    "$STAMP" "$TO" "$EXPECT" "$PRE_EXISTED" "$PRE_H" "$PRE_MODE" "$PRE_OWNER"
  for h in $HELPERS; do
    printf 'pre_helper_%s_exists=%s\npre_helper_%s_sha256=%s\n' \
      "$h" "$([ -f "$TO_DIR/$h" ] && echo yes || echo no)" "$h" "$(sha "$TO_DIR/$h")"
  done; } > "$REC" || fail RECEIPT "写不了回执"
if [ "$PRE_EXISTED" = "yes" ]; then
  cp -a "$TO" "$B/ws-verify-faces.sh.orig" || fail BACKUP_COPY "备份失败"
  [ "$(sha "$B/ws-verify-faces.sh.orig")" = "$PRE_H" ] || fail BACKUP_VERIFY "备份读回哈希不一致"
fi
if [ -f "$PIN_TO" ]; then cp -a "$PIN_TO" "$B/ws-verify-faces.sh.sha256.orig" 2>/dev/null || true; fi
for h in $HELPERS; do
  if [ -f "$TO_DIR/$h" ]; then
    cp -a "$TO_DIR/$h" "$B/$h.orig" || fail BACKUP_COPY "备份 $h 失败"
    [ "$(sha "$B/$h.orig")" = "$(sha "$TO_DIR/$h")" ] || fail BACKUP_VERIFY "$h 备份读回不一致"
  fi
done
# 顺带记下调用方身份（只读，帮忙判断"换核验器后谁受影响"）
for f in /usr/local/bin/cutover.sh /usr/local/bin/ws-prep.sh /usr/local/bin/ops-selftest.sh; do
  [ -f "$f" ] && printf '%s sha256=%s\n' "$f" "$(sha "$f")"
done >> "$REC"

# 还原面：把任何已写入的件退回安装前状态；安装前不存在的辅助文件移到备份目录（不删除）
restore() {
  if [ "$PRE_EXISTED" = "yes" ]; then
    cp -a "$B/ws-verify-faces.sh.orig" "$TO.restore.$STAMP" && mv -f "$TO.restore.$STAMP" "$TO"
    [ "$(sha "$TO")" = "$PRE_H" ] || fail RESTORE_MISMATCH "还原后核验器哈希 $(sha "$TO") ≠ $PRE_H（需人工介入）" 3
    say "  已还原旧核验器（sha256=$PRE_H）"
  elif [ -f "$TO" ]; then
    mv -f "$TO" "$B/failed-install-verifier.$STAMP" && say "  安装前无旧核验器：把失败的安装件移到 $B/failed-install-verifier.$STAMP（未删除）"
  fi
  for h in $HELPERS; do
    if [ -f "$B/$h.orig" ]; then
      cp -a "$B/$h.orig" "$TO_DIR/$h.restore.$STAMP" && mv -f "$TO_DIR/$h.restore.$STAMP" "$TO_DIR/$h"
      say "  已还原 $h"
    elif [ -f "$TO_DIR/$h.new.$STAMP" ]; then
      mv -f "$TO_DIR/$h.new.$STAMP" "$B/failed-install-$h.$STAMP" && say "  $h 安装前不存在：把失败件移到 $B/failed-install-$h.$STAMP（未删除）"
    elif [ -f "$TO_DIR/$h" ]; then
      mv -f "$TO_DIR/$h" "$B/failed-install-$h.$STAMP" && say "  $h 安装前不存在：把新写入的 $h 移到 $B/failed-install-$h.$STAMP（未删除）"
    fi
  done
}

install -m 0755 -o root -g root "$SRC" "$TO.new.$STAMP" || fail STAGE_WRITE "写暂存文件失败"
mv -f "$TO.new.$STAMP" "$TO" || fail INSTALL_RENAME "rename 失败（旧文件未动）"

POST_H=$(sha "$TO"); POST_SIZE=$(stat -c '%s' "$TO"); POST_MODE=$(stat -c '%a' "$TO"); POST_OWNER=$(stat -c '%U:%G' "$TO")
printf 'post_sha256=%s\npost_size=%s\npost_mode=%s\npost_owner=%s\n' "$POST_H" "$POST_SIZE" "$POST_MODE" "$POST_OWNER" >> "$REC"
if [ "$POST_H" != "$EXPECT" ] || [ "$POST_SIZE" != "$(stat -c '%s' "$SRC")" ]; then
  restore
  say "VERIFIER_INSTALL=FAIL_READBACK  installed=$POST_H size=$POST_SIZE（期望 $EXPECT）"
  exit 3
fi

for h in $HELPERS; do
  install -m 0644 -o root -g root "$SRC_DIR/$h" "$TO_DIR/$h.new.$STAMP" || { restore; fail HELPER_STAGE "写 $h 暂存文件失败（已还原）" 3; }
  mv -f "$TO_DIR/$h.new.$STAMP" "$TO_DIR/$h" || { restore; fail HELPER_RENAME "rename $h 失败（已还原）" 3; }
  PH=$(sha "$TO_DIR/$h"); PS=$(stat -c '%s' "$TO_DIR/$h"); PM=$(stat -c '%a' "$TO_DIR/$h"); PO=$(stat -c '%U:%G' "$TO_DIR/$h")
  printf 'post_helper_%s_sha256=%s size=%s mode=%s owner=%s\n' "$h" "$PH" "$PS" "$PM" "$PO" >> "$REC"
  if [ "$PH" != "$(helper_expect "$h")" ] || [ "$PS" != "$(stat -c '%s' "$SRC_DIR/$h")" ]; then
    restore
    say "VERIFIER_INSTALL=FAIL_HELPER_READBACK  $h installed=$PH（期望 $(helper_expect "$h")）"
    exit 3
  fi
done

# 哈希钉同步写到位（cutover 默认从 $HERE/ws-verify-faces.sh.sha256 读期望值）
install -m 0644 -o root -g root "$PIN_SRC" "$PIN_TO.new.$STAMP" && mv -f "$PIN_TO.new.$STAMP" "$PIN_TO" \
  || { restore; fail PIN_WRITE "哈希钉写入失败（已还原）" 3; }
PIN_H=$(awk 'NR==1{print $1}' "$PIN_TO")
[ "$PIN_H" = "$EXPECT" ] || { restore; fail PIN_READBACK "哈希钉读回 $PIN_H ≠ $EXPECT（已还原）" 3; }

# 用法自测：无参调用会真的去探生产两面（只读但联网），不是用法错误。
# 用 WS_EXPECTED_ROOT 非法值走真正的 usage 分支（在任何网络探测之前退出），证明装了新核验器
# 之后参数契约仍然可用，且这条自测不碰网络。
USAGE_OUT=$(WS_EXPECTED_ROOT=__invalid__ bash "$TO" 2>&1); USAGE_RC=$?
printf 'usage_rc=%s\nstatus=OK\n' "$USAGE_RC" >> "$REC"
[ "$USAGE_RC" = "6" ] || { restore; fail USAGE_SELFTEST "用法自测退出码=$USAGE_RC（期望 6），已还原" 3; }

say "VERIFIER_INSTALL=OK  sha256=$EXPECT  size=$(stat -c '%s' "$TO")  mode=$POST_MODE  owner=$POST_OWNER"
say "  helpers=$(for h in $HELPERS; do printf '%s=%s ' "$h" "$(sha "$TO_DIR/$h")"; done)"
say "  backup_dir=$B"
say "  pin=$PIN_TO"
say "  回滚命令：cp -a $B/ws-verify-faces.sh.orig $TO && sha256sum $TO（期望 $PRE_H）"
for h in $HELPERS; do
  if [ -f "$B/$h.orig" ]; then
    say "            cp -a $B/$h.orig $TO_DIR/$h"
  else
    say "            mv $TO_DIR/$h $B/uninstall-$h   # 安装前不存在；保留不删除，移交 Owner 决定"
  fi
done
exit 0
