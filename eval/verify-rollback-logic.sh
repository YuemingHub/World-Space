#!/usr/bin/env bash
# 回退逻辑沙箱验证（在临时目录里跑，不碰任何真实路径与 nginx）
set -u
TMP=$(mktemp -d)
PROT="$TMP/www"
DEST="$PROT/ai"
mkdir -p "$DEST/assets" "$PROT/ming"
for i in 1 2 3 4 5 6 7 8 9 10; do echo "file$i" > "$DEST/f$i.txt"; done
echo "ming-a" > "$PROT/ming/a.html"
echo "pdf" > "$PROT/ming/doc.pdf"

# 发布前清单
find "$PROT" -path "$DEST" -prune -o -type f -print0 | sort -z | xargs -0 sha256sum > "$TMP/before.sha256"
echo "[setup] before lines=$(wc -l < "$TMP/before.sha256")"

# ---- 场景 1：正常回退（改名后核对，必须 PASS）----
MOVED="$PROT/ai.removed-20261101"
mv "$DEST" "$MOVED"
find "$PROT" -path "$DEST" -prune -o -path "$MOVED" -prune -o -type f -print0 \
  | sort -z | xargs -0 sha256sum > "$TMP/after_ok.sha256"
if diff "$TMP/before.sha256" "$TMP/after_ok.sha256" > /dev/null; then
  echo "SCENARIO1 normal-rollback: PASS (no false alarm)"
  S1=0
else
  echo "SCENARIO1 normal-rollback: FAIL (false alarm)"; diff "$TMP/before.sha256" "$TMP/after_ok.sha256" | head -5
  S1=1
fi

# ---- 场景 2：篡改既有文件（必须 FAIL，能检出）----
echo "tampered" > "$PROT/ming/a.html"
find "$PROT" -path "$DEST" -prune -o -path "$MOVED" -prune -o -type f -print0 \
  | sort -z | xargs -0 sha256sum > "$TMP/after_bad.sha256"
if diff "$TMP/before.sha256" "$TMP/after_bad.sha256" > /dev/null; then
  echo "SCENARIO2 tamper-detect: FAIL (missed tampering)"; S2=1
else
  echo "SCENARIO2 tamper-detect: PASS (tampering detected)"; S2=0
fi
echo "ming-a" > "$PROT/ming/a.html"   # 复原

# ---- 场景 3：reload 失败必须非零退出，不能假成功 ----
fakenginx_ok() { return 0; }
fakenginx_bad() { return 1; }
fakereload_fail() { return 1; }
run_reload_path() {  # $1 = reload 命令
  if ! "$1"; then
    echo "FAIL: reload 失败，磁盘与线上不一致，停止并上报"
    return 1
  fi
  echo "OK: reload 成功"
  return 0
}
if run_reload_path fakereload_fail; then
  echo "SCENARIO3 reload-fail: FAIL (returned 0, fake success)"; S3=1
else
  echo "SCENARIO3 reload-fail: PASS (non-zero exit)"; S3=0
fi
if run_reload_path fakenginx_ok; then
  echo "SCENARIO3b reload-ok: PASS"; S3b=0
else
  echo "SCENARIO3b reload-ok: FAIL"; S3b=1
fi

rm -rf "$TMP"
echo "----"
echo "SUMMARY S1=$S1 S2=$S2 S3=$S3 S3b=$S3b"
[ $((S1+S2+S3+S3b)) -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "HAS FAILURE"; exit 1; }
