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
if [ "$IDX" = "all" ]; then
  [ "$N" -ge 2 ] || { echo "FAIL: 要求主备两把都配，但候选文件里只有 $N 把——不能声称配了备用其实没有" >&2; exit 1; }
  KEY="${KEYS[0]}"; KEY2="${KEYS[1]}"
  echo "双钥匙模式：主=$(FP "$KEY") 备=$(FP "$KEY2")（只出指纹）"
else
  { [ "$IDX" -ge 1 ] && [ "$IDX" -le "$N" ]; } || { echo "第几把超出范围（1..$N）" >&2; exit 1; }
  KEY="${KEYS[$((IDX-1))]}"; KEY2=""
fi

probe_one() { curl -s -o /tmp/sk-probe.json -w '%{http_code}' --max-time 25 -X POST https://api.tavily.com/search \
    -H "Authorization: Bearer $1" -H 'content-type: application/json' \
    -d '{"query":"ping","search_depth":"basic","max_results":1}' || echo ERR; }
if [ "$PROBE" = "--probe" ]; then
  code=$(probe_one "$KEY")
  cnt=$(node -e 'try{const j=require("/tmp/sk-probe.json");console.log((j.results||[]).length)}catch(e){console.log(0)}' 2>/dev/null || echo 0)
  echo "  主钥匙探针：HTTP=$code 结果 $cnt 条"
  if [ "$code" != "200" ] && [ -n "$KEY2" ]; then
    code2=$(probe_one "$KEY2"); echo "  主钥匙不通 → 备钥匙探针：HTTP=$code2"
    [ "$code2" = "200" ] || { rm -f /tmp/sk-probe.json; echo "FAIL: 两把都被拒，没有写入" >&2; exit 3; }
  elif [ "$code" != "200" ]; then
    rm -f /tmp/sk-probe.json; echo "FAIL: 这把直连被拒且无备用可试，没有写入" >&2; exit 3
  fi
  rm -f /tmp/sk-probe.json
fi

OLD=$(grep -E '^WS_SEARCH_KEY=' "$ENVF" | head -1 | cut -d= -f2- || true)
BK="$ENVF.bak-pre-searchkey-$(date +%Y%m%d-%H%M%S)"
cp -p "$ENVF" "$BK"
if [ -n "$OLD" ]; then echo "  原值指纹 $(FP "$OLD")（备份：$BK）"; else echo "  原值不存在，将追加（备份：$BK）"; fi

OLDOWN=$(stat -c '%U:%G' "$ENVF")
put_line() { # put_line <KEY名> <值>   —— 只替换这一行本身，不误伤同前缀的行（如 WS_SEARCH_KEY_2）
  local name="$1" val="$2"
  NEWVAL="$val" NVAR="$name" node -e '
    const fs=require("fs"), f=process.argv[1], n=process.env.NVAR, v=process.env.NEWVAL;
    const lines=fs.readFileSync(f,"utf8").split("\n");
    const re=new RegExp("^"+n+"=");
    let hit=false;
    const out=lines.map(l=>{ if(re.test(l)){ hit=true; return n+"="+v; } return l; });
    if(!hit) out.push(n+"="+v);
    fs.writeFileSync(f,out.join("\n"));
  ' "$ENVF"
}
put_line WS_SEARCH_KEY "$KEY"
if [ -n "$KEY2" ]; then put_line WS_SEARCH_KEY_2 "$KEY2"; fi

chmod 600 "$ENVF"
chown "$OLDOWN" "$ENVF" 2>/dev/null || echo "  注意：属主还原失败，保持现状"
NOW=$(grep -E '^WS_SEARCH_KEY=' "$ENVF" | head -1 | cut -d= -f2-)
NOW2=$(grep -E '^WS_SEARCH_KEY_2=' "$ENVF" | head -1 | cut -d= -f2- || true)
echo "权限实核：$(stat -c '%a %U:%G' "$ENVF")（写入前是 $OLDOWN，已还原；systemd 以 root 读 EnvironmentFile，服务账户不需要拥有它）"
echo "写入完成：$ENVF"
echo "  主 WS_SEARCH_KEY    = $(FP "$NOW")  $([ "$(FP "$NOW")" = "$(FP "$KEY")" ] && echo '回读一致 ✓' || echo '回读不一致 ✗')"
[ "$(FP "$NOW")" = "$(FP "$KEY")" ] || exit 4
if [ -n "$KEY2" ]; then
  echo "  备 WS_SEARCH_KEY_2  = $(FP "$NOW2")  $([ "$(FP "$NOW2")" = "$(FP "$KEY2")" ] && echo '回读一致 ✓' || echo '回读不一致 ✗')"
  [ "$(FP "$NOW2")" = "$(FP "$KEY2")" ] || exit 4
  [ "$(FP "$NOW")" != "$(FP "$NOW2")" ] || { echo "FAIL: 主备被写成同一把，等于没有备用" >&2; exit 5; }
fi
echo "注意：没有重启任何服务；公网那个进程仍用内存里的旧 key。"
