#!/usr/bin/env bash
# 把服务器上的候选 key 文件里的某一把，写入指定 env 的 WS_SEARCH_KEY
#
# 为什么要有这个脚本，而不是手敲 sed：命令行里出现 key 明文就等于把它第二次写进
# shell 历史与日志。所以本脚本只从文件里取值，屏幕上**只出指纹**。
#
# 用法：set-search-key.sh <候选key文件> <第几把(1起)> <目标env> [--probe]
#   --probe 顺手拿这把 key 直连 Tavily 发一次最小请求，只报 HTTP 状态与结果条数
#
# 本脚本只改 env 文件，**不重启任何服务**：正在跑的进程仍用内存里的旧环境，
# 公网行为不变；下一次重启（切流时的那一次）才生效。
set -euo pipefail

CAND="${1:-}"; IDX="${2:-}"; ENVF="${3:-}"; PROBE="${4:-}"
[ -n "$CAND" ] && [ -n "$IDX" ] && [ -n "$ENVF" ] || {
  echo "用法: set-search-key.sh <候选key文件> <第几把> <目标env> [--probe]" >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "需要 root" >&2; exit 1; }
[ -f "$CAND" ] || { echo "候选文件不存在: $CAND" >&2; exit 1; }
[ -f "$ENVF" ] || { echo "目标 env 不存在: $ENVF" >&2; exit 1; }
chmod 600 "$CAND" 2>/dev/null || true

FP() { printf %s "$1" | sha256sum | cut -c1-12; }

# 按文件出现顺序去重取第 N 把
mapfile -t KEYS < <(grep -oE 'tvly-[A-Za-z0-9_-]{20,}' "$CAND" | awk '!seen[$0]++')
N=${#KEYS[@]}
echo "候选文件里找到 $N 把 tvly 形态的 key（按出现顺序，只列指纹）："
for ((i=0;i<N;i++)); do echo "  第 $((i+1)) 把  $(FP "${KEYS[$i]}")"; done
[ "$IDX" -ge 1 ] && [ "$IDX" -le "$N" ] || { echo "第几把超出范围（1..$N）" >&2; exit 1; }
KEY="${KEYS[$((IDX-1))]}"

if [ "$PROBE" = "--probe" ]; then
  code=$(curl -s -o /tmp/sk-probe.json -w '%{http_code}' --max-time 25 -X POST https://api.tavily.com/search \
    -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
    -d '{"query":"ping","search_depth":"basic","max_results":1}' || echo ERR)
  cnt=$(node -e 'try{const j=require("/tmp/sk-probe.json");console.log((j.results||[]).length)}catch(e){console.log(0)}' 2>/dev/null || echo 0)
  rm -f /tmp/sk-probe.json
  echo "直连探针：HTTP=$code 结果条数=$cnt  → $([ "$code" = 200 ] && echo "这把能用" || echo "这把不能用，没有写入")"
  [ "$code" = "200" ] || exit 3
fi

OLD=$(grep -E '^WS_SEARCH_KEY=' "$ENVF" | head -1 | cut -d= -f2- || true)
BK="$ENVF.bak-pre-searchkey-$(date +%Y%m%d-%H%M%S)"
cp -p "$ENVF" "$BK"
if [ -n "$OLD" ]; then echo "  原值指纹 $(FP "$OLD")（备份：$BK）"; else echo "  原值不存在，将追加（备份：$BK）"; fi

if grep -qE '^WS_SEARCH_KEY=' "$ENVF"; then
  NEWKEY="$KEY" node -e '
    const fs=require("fs"), f=process.argv[1];
    const lines=fs.readFileSync(f,"utf8").split("\n");
    fs.writeFileSync(f, lines.map(l=>/^WS_SEARCH_KEY=/.test(l) ? "WS_SEARCH_KEY="+process.env.NEWKEY : l).join("\n"));
  ' "$ENVF"
else
  printf 'WS_SEARCH_KEY=%s\n' "$KEY" >> "$ENVF"
fi

chmod 600 "$ENVF"; chown wsapp:wsapp "$ENVF" 2>/dev/null || true
NOW=$(grep -E '^WS_SEARCH_KEY=' "$ENVF" | head -1 | cut -d= -f2-)
echo "写入完成：$ENVF 现在用的是第 $IDX 把（指纹 $(FP "$NOW")）"
[ "$(FP "$NOW")" = "$(FP "$KEY")" ] && echo "回读一致 ✓" || { echo "回读不一致，检查 env 是否有重复行" >&2; exit 4; }
echo "注意：没有重启任何服务；公网那个进程仍用内存里的旧 key。"
