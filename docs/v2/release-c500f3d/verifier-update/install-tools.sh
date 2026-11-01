#!/usr/bin/env bash
# install-tools.sh —— 把这一版发布配套的 /usr/local/bin 工具集一次性装齐（需要 Owner 批准后以 root 执行）。
#
# 为什么必须整组装：新核验器的 A 段判据与新 ops-selftest、新 cutover、新 ws-prep 是一对一契约。
# 只换其中一件会让"守护自己的守卫"变红（例：新核验器 + 旧 ops-selftest = A1 期望 0 实得 7）。
# 本脚本拒绝对"只装一部分"负责：它要求 TOOLS.sha256 里每一件都在、都对上，否则零写入退出。
#
# 源文件默认取本脚本上一级目录（= 发布树里的 docs/v2/release-c500f3d/）。
# 用法（生产）：
#   sudo bash install-tools.sh                 # 装到 /usr/local/bin
#   可选：WS_TOOLS_SRC=<发布工具目录>  WS_TOOLS_TO=/usr/local/bin  WS_BACKUP_ROOT=/root/backups
#
# 退出码：0 成功 / 2 前置或校验不满足（零写入）/ 3 读回不一致（已尽量还原，需人工）
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${WS_TOOLS_SRC:-$(cd "$HERE/.." && pwd)}
PIN=${WS_TOOLS_PIN:-$HERE/TOOLS.sha256}
TO=${WS_TOOLS_TO:-/usr/local/bin}
BACKUP_ROOT=${WS_BACKUP_ROOT:-/root/backups}
STAMP=$(date +%Y%m%d-%H%M%S)
B="$BACKUP_ROOT/world-space-tools-$STAMP"
REC="$B/receipt.txt"

# 工具 → 目标模式。核验器与辅助文件由 install-verifier.sh 负责的同一份字节，这里一并核对。
FILES="cutover.sh ops-selftest.sh ws-prep.sh ops-fixture-face.mjs ws-verify-faces.sh ws-verify-faces.sh.sha256 face-probe.mjs release-id.mjs"
mode_of() { case "$1" in *.sh) echo 0755 ;; *) echo 0644 ;; esac; }

say() { printf '%s\n' "$*"; }
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

[ "$(id -u)" = "0" ] || { say "TOOLS_INSTALL=FAIL_ROOT_REQUIRED  必须以 root 执行"; exit 2; }
[ -d "$SRC" ] || { say "TOOLS_INSTALL=FAIL_SOURCE_DIR  找不到源目录 $SRC"; exit 2; }
[ -f "$PIN" ] || { say "TOOLS_INSTALL=FAIL_PIN_MISSING  找不到 $PIN"; exit 2; }
[ -d "$TO" ] || { say "TOOLS_INSTALL=FAIL_TARGET_DIR  目标目录不存在 $TO"; exit 2; }
for c in bash node sha256sum stat install mv cp awk ls; do
  command -v "$c" >/dev/null 2>&1 || { say "TOOLS_INSTALL=FAIL_DEP  缺命令 $c"; exit 2; }
done

# 1) 源文件全部核真（缺一件、错一件都零写入）
for f in $FILES; do
  [ -f "$SRC/$f" ] || { say "TOOLS_INSTALL=FAIL_SOURCE_MISSING  缺 $SRC/$f"; exit 2; }
  E=$(awk -v n="$f" '$2==n{print $1}' "$PIN" 2>/dev/null | head -1)
  grep -Eq '^[0-9a-f]{64}$' <<<"$E" || { say "TOOLS_INSTALL=FAIL_PIN_ENTRY  $PIN 里没有 $f 的合法哈希"; exit 2; }
  H=$(sha "$SRC/$f"); [ "$H" = "$E" ] || { say "TOOLS_INSTALL=FAIL_SOURCE_HASH  $f sha256=$H ≠ 期望 $E"; exit 2; }
done
bash -n "$SRC/cutover.sh" && bash -n "$SRC/ops-selftest.sh" && bash -n "$SRC/ws-prep.sh" && bash -n "$SRC/ws-verify-faces.sh" \
  || { say "TOOLS_INSTALL=FAIL_SYNTAX  有脚本 bash -n 不通过"; exit 2; }
for m in ops-fixture-face.mjs face-probe.mjs release-id.mjs; do
  node --check "$SRC/$m" >/dev/null 2>&1 || { say "TOOLS_INSTALL=FAIL_SYNTAX  $m node 语法不通过"; exit 2; }
done

# 2) 全部已是最新则 NOOP
ALL_CURRENT=yes
for f in $FILES; do
  [ -f "$TO/$f" ] && [ "$(sha "$TO/$f")" = "$(awk -v n="$f" '$2==n{print $1}' "$PIN" | head -1)" ] || ALL_CURRENT=no
done
if [ "$ALL_CURRENT" = "yes" ]; then
  say "TOOLS_INSTALL=NOOP_ALREADY_CURRENT  set=$(printf '%s' "$FILES" | tr ' ' ',')"
  exit 0
fi

mkdir -p "$B" || { say "TOOLS_INSTALL=FAIL_BACKUP_DIR  建不了 $B"; exit 2; }
{ printf 'mode=install-tools\nat=%s\ntarget_dir=%s\nsource_dir=%s\n' "$STAMP" "$TO" "$SRC"; } > "$REC"
for f in $FILES; do
  printf 'pre_%s_exists=%s\npre_%s_sha256=%s\n' "$f" "$([ -f "$TO/$f" ] && echo yes || echo no)" "$f" "$(sha "$TO/$f")" >> "$REC"
  if [ -f "$TO/$f" ]; then
    cp -a "$TO/$f" "$B/$f.orig" || { say "TOOLS_INSTALL=FAIL_BACKUP  $f 备份失败"; exit 2; }
    [ "$(sha "$B/$f.orig")" = "$(sha "$TO/$f")" ] || { say "TOOLS_INSTALL=FAIL_BACKUP_VERIFY  $f 备份读回不一致"; exit 2; }
  fi
done

# 3) 逐个原子替换并读回；任何一件读回不符就整体回滚
rollback() {
  for f in $FILES; do
    if [ -f "$B/$f.orig" ]; then
      cp -a "$B/$f.orig" "$TO/$f.restore.$STAMP" && mv -f "$TO/$f.restore.$STAMP" "$TO/$f"
      [ "$(sha "$TO/$f")" = "$(awk -v n="$f" '$2==n{print $1}' "$PIN" | head -1)" ] && say "  !! 回滚后 $f 仍是新版，需人工介入"
    else
      [ -f "$TO/$f" ] && mv -f "$TO/$f" "$B/failed-install-$f.$STAMP" && say "  $f 安装前不存在，失败件已移到 $B（未删除）"
    fi
  done
  say "TOOLS_INSTALL=FAIL_READBACK  已尝试整体回滚；备份目录 $B"
  exit 3
}
for f in $FILES; do
  M=$(mode_of "$f")
  install -m "$M" -o root -g root "$SRC/$f" "$TO/$f.new.$STAMP" || { say "TOOLS_INSTALL=FAIL_STAGE  $f 写暂存失败"; rollback; }
  mv -f "$TO/$f.new.$STAMP" "$TO/$f" || { say "TOOLS_INSTALL=FAIL_RENAME  $f rename 失败"; rollback; }
  PH=$(sha "$TO/$f")
  printf 'post_%s_sha256=%s\n' "$f" "$PH" >> "$REC"
  if [ "$PH" != "$(awk -v n="$f" '$2==n{print $1}' "$PIN" | head -1)" ]; then
    say "TOOLS_INSTALL=FAIL_READBACK  $f installed=$PH"
    rollback
  fi
done

# 4) 装完的契约自测（离线、不碰生产端口）
USAGE_RC=0
WS_EXPECTED_ROOT=__invalid__ bash "$TO/ws-verify-faces.sh" >/dev/null 2>&1; USAGE_RC=$?
printf 'usage_rc=%s\n' "$USAGE_RC" >> "$REC"
if [ "$USAGE_RC" != "6" ]; then
  say "TOOLS_INSTALL=FAIL_USAGE_SELFTEST  /usr/local/bin/ws-verify-faces.sh 用法自测退出码=$USAGE_RC（期望 6）"
  rollback
fi
bash -n "$TO/cutover.sh" && bash -n "$TO/ops-selftest.sh" && bash -n "$TO/ws-prep.sh" \
  || { say "TOOLS_INSTALL=FAIL_POST_SYNTAX  装完语法复查失败"; rollback; }

say "TOOLS_INSTALL=OK  files=$(printf '%s' "$FILES" | tr ' ' ',')"
say "  backup_dir=$B"
say "  回滚（整组）：for f in $FILES; do [ -f $B/\$f.orig ] && cp -a $B/\$f.orig $TO/\$f; done"
say "  注意：核验器本体/辅助文件/哈希钉也由 install-verifier.sh 负责，两者装的是同一份字节。"
exit 0
