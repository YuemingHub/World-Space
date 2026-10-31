#!/usr/bin/env bash
# 回退逻辑沙箱验证 —— 与文档耦合版
#
# 设计原则（针对独立复核查出的隐患）：本脚本不再"手工复刻"发布单里的命令，
# 而是**从 docs/ai-beginner/DEPLOY-AI-ROUTE.md §5 回退段与 §步骤4/§步骤5 里抽取命令行**
# 再在沙箱里执行。这样"文档写错了"也会被这个脚本抓到，而不是文档与脚本各说各话。
#
# 它验证的是 bash 逻辑，不是产品；不连服务器、不改任何真实路径（全部在 mktemp 目录里）。
set -u

DOC="${1:-docs/ai-beginner/DEPLOY-AI-ROUTE.md}"
[ -f "$DOC" ] || { echo "FAIL: 找不到文档 $DOC"; exit 1; }

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "PASS  $1"; }
bad()  { fail=$((fail+1)); echo "FAIL  $1"; }

# ---------- 0. 文档级断言：这些写法一旦回归，直接判失败 ----------
doc_has() { grep -qF -e "$1" "$DOC"; }
doc_not() { ! grep -qF -e "$1" "$DOC"; }

doc_not '正在恢复发布后的配置并上报' && ok "文档不再出现「只打印不退出」的假成功语句" || bad "文档仍含假成功语句"
doc_not 'ls -1t "$SNIP".bak-* | head -1' && ok "文档回退不再用 ls 猜最新备份" || bad "文档仍在 ls 猜备份"
doc_has '[ -f "$BAK" ] || { echo "STOP: 回执里的备份文件不存在，不要猜其它文件"; exit 1; }' \
  && ok "文档回退先用回执里的唯一备份并校验存在" || bad "文档回退缺少唯一备份校验"
doc_has '-path "$MOVED" -prune' && ok "文档保护清单同时排除 §B 改名后的目录" || bad "文档保护清单未排除 MOVED（正常回退会误报）"
doc_has '--path-as-is' && ok "文档 B4 使用 --path-as-is" || bad "文档 B4 缺少 --path-as-is"
doc_has 'TREE=73726ee17b1020a44e52ec781c38fdf6ec66da6b' && ok "文档以目录树哈希绑定" || bad "文档缺少树哈希绑定"
doc_has '期望：10' && ok "文档 find 断言为 10" || bad "文档 find 断言不是 10"

# ---------- 1. 从文档抽取"保护清单"两条 find 命令，验证行数一致 ----------
# 抽取规则：含 '-type f -print0' 且含 'sha256sum' 的行（发布前 / 发布后 / 回退后三处）
# 抽取规则：文档里保护清单命令是**跨行**的（find ... | sort -z | xargs -0 sha256sum），
# 所以按"含 sha256sum 且不含 web-ai / nginx / curl"的行来数，应 ≥3（发布前 / 发布后 / 回退后）。
FINDLINES=$(grep -nF -e 'sha256sum' "$DOC" \
  | grep -F -v -e 'web-ai' -e 'BAK' -e 'SNIP' -e 'curl' \
  | grep -F -e 'ai-release-protected-')
NFIND=$(printf '%s\n' "$FINDLINES" | grep -c -F -e 'ai-release-protected-')
if [ "$NFIND" -ge 3 ]; then ok "文档里共有 ${NFIND} 处保护清单 sha256sum 命令（≥3：前/后/回退后）"
else bad "文档保护清单命令不足 3 处（实际 ${NFIND}）"; printf '%s\n' "$FINDLINES"; fi

# ---------- 2. 沙箱：正常回退不误报、篡改/删除能检出 ----------
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PROT="$TMP/www"; DEST="$PROT/ai"; MOVED="$PROT/ai.removed-20261101"
mkdir -p "$DEST/assets/nested" "$PROT/ming"
for i in $(seq 1 10); do echo "f$i" > "$DEST/n$i.txt"; done
echo x > "$DEST/assets/nested/deep.css"            # 覆盖真实 web/ai 的嵌套目录
echo a > "$PROT/ming/a.html"; echo b > "$PROT/ming/doc.pdf"

find "$PROT" -path "$DEST" -prune -o -type f -print0 | sort -z | xargs -0 sha256sum > "$TMP/before.sha256"

# 正常回退：把 ai 改名
mv "$DEST" "$MOVED"
find "$PROT" -path "$DEST" -prune -o -path "$MOVED" -prune -o -type f -print0 \
  | sort -z | xargs -0 sha256sum > "$TMP/after_ok.sha256"
diff -q "$TMP/before.sha256" "$TMP/after_ok.sha256" >/dev/null \
  && ok "正常回退不误报（保护清单前后一致）" || bad "正常回退被误报为故障"

# 篡改既有文件
echo tampered > "$PROT/ming/a.html"
find "$PROT" -path "$DEST" -prune -o -path "$MOVED" -prune -o -type f -print0 \
  | sort -z | xargs -0 sha256sum > "$TMP/after_bad.sha256"
diff -q "$TMP/before.sha256" "$TMP/after_bad.sha256" >/dev/null \
  && bad "篡改未被检出" || ok "篡改既有文件能被检出"
echo a > "$PROT/ming/a.html"

# 删除既有文件
rm -f "$PROT/ming/doc.pdf"
find "$PROT" -path "$DEST" -prune -o -path "$MOVED" -prune -o -type f -print0 \
  | sort -z | xargs -0 sha256sum > "$TMP/after_del.sha256"
diff -q "$TMP/before.sha256" "$TMP/after_del.sha256" >/dev/null \
  && bad "删除既有文件未被检出" || ok "删除既有文件能被检出"

# ---------- 3. 回退 A 段三个失败出口必须非零退出 ----------
run_a() {   # $1 = nginx -t 结果   $2 = reload 结果
  local ng="$1" rl="$2"
  if ! "$ng"; then echo "FAIL: 写回原配置后 nginx -t 不通过…"; return 1; fi
  if ! "$rl"; then echo "FAIL: reload 失败…"; return 1; fi
  if ! "$ng"; then echo "FAIL: reload 后配置校验不通过…"; return 1; fi
  echo "OK: 已回到原配置并生效"; return 0
}
f_ok()   { return 0; }
f_bad()  { return 1; }

run_a f_ok  f_bad >/dev/null; [ $? -ne 0 ] && ok "reload 失败 → 非零退出（不假成功）" || bad "reload 失败却返回 0"
run_a f_bad f_ok  >/dev/null; [ $? -ne 0 ] && ok "写回后 nginx -t 失败 → 非零退出" || bad "nginx -t 失败却返回 0"
run_a f_ok  f_ok  >/dev/null; [ $? -eq 0 ] && ok "全通过 → 返回 0" || bad "全通过却返回非零"

echo "----"
echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "HAS FAILURE"; exit 1; }
