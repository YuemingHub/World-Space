#!/usr/bin/env bash
# World Space V0.1 切流（Founder 明示批准后执行）
#
# 边界（写死在这里，不给临场判断留缝）：
#   动：/opt/world-space/current 符号链接、world-space.service 的一次重启、session 签名密钥轮换
#   不动：DNS、解析记录、nginx 站点配置、其它任何站点、共享账本、旧 release 目录
#   失败时：走 emergency close（nginx 503 维护页）—— 绝不把无访问门的旧版本重新公开
set -uo pipefail

ROOT=/opt/world-space
STATE=$ROOT/state
SHA=$(cat "$STATE/approved-sha" 2>/dev/null || true)
REL=$ROOT/releases/$SHA
LIVE=$(readlink "$ROOT/current" || echo none)
EMERG=/usr/local/bin/world-space-emergency.sh

[ -n "$SHA" ] || { echo "FAIL: 没有登记批准点（先跑 ws-prep.sh verify）"; exit 1; }
[ -d "$REL" ] || { echo "FAIL: 批准树不存在 $REL"; exit 1; }
[ -x "$EMERG" ] || { echo "FAIL: 关站脚本不在位，切流前必须先装好回滚方案"; exit 1; }

echo "批准点：$SHA"
echo "当前线上：$(basename "$LIVE")"

# 1) 轮换 session 签名密钥：让此前任何泄漏过/打印过的会话令牌全部失效
echo "=== 1) 轮换会话签名密钥（作废所有旧令牌）==="
head -c 48 /dev/urandom | base64 > "$ROOT/etc/session-secret.txt"
chmod 600 "$ROOT/etc/session-secret.txt"; chown wsapp:wsapp "$ROOT/etc/session-secret.txt"
echo "  已重写（值不回显）。所有账号需要重新登录一次，口令不变。"

# 2) 切版本 + 重启，并量出真实中断时长
echo "=== 2) 换 current 并重启 ==="
ln -sfn "$REL" "$ROOT/current"
echo "  current: $(basename "$LIVE") -> $(basename "$(readlink "$ROOT/current")")"
T0=$(date +%s.%N)
systemctl restart world-space.service
OK=no
for _ in $(seq 1 200); do
  if curl -s -o /dev/null --max-time 2 http://127.0.0.1:3200/healthz; then OK=yes; break; fi
  sleep 0.2
done
T1=$(date +%s.%N)
printf "  恢复探测：%s（约 %.1f 秒）\n" "$([ "$OK" = yes ] && echo 成功 || echo 失败)" "$(echo "$T1 - $T0" | bc)"

# 3) 核验：门必须是 ready，未登录必须进不来
echo "=== 3) 切后核验 ==="
HZ=$(curl -s --max-time 8 http://127.0.0.1:3200/healthz)
echo "  healthz: $HZ"
CHECK_FAIL=""
echo "$HZ" | grep -q '"auth":"ready"'            || CHECK_FAIL="$CHECK_FAIL auth_not_ready"
echo "$HZ" | grep -q '"search_keys":2'           || CHECK_FAIL="$CHECK_FAIL search_keys_not_2"
echo "$HZ" | grep -q '"fail_closed":true'        || CHECK_FAIL="$CHECK_FAIL budget_not_failclosed"
RC=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 --resolve ymai.fun:443:127.0.0.1 https://ymai.fun/)
[ "$RC" = "302" ]                               || CHECK_FAIL="$CHECK_FAIL unauth_root_not_302($RC)"
LOC=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 15 --resolve ymai.fun:443:127.0.0.1 https://ymai.fun/)
echo "$LOC" | grep -q '/login'                  || CHECK_FAIL="$CHECK_FAIL redirect_not_login($LOC)"
API=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST \
      -H 'content-type: application/json' -d '{"intent":"cutover probe"}' \
      --resolve ymai.fun:443:127.0.0.1 https://ymai.fun/api/world)
[ "$API" = "401" ]                              || CHECK_FAIL="$CHECK_FAIL unauth_api_not_401($API)"
PAGE=$(curl -s --max-time 15 --resolve ymai.fun:443:127.0.0.1 https://ymai.fun/login)
echo "$PAGE" | grep -q '进入你的空间'             || CHECK_FAIL="$CHECK_FAIL login_page_missing"
echo "  公网未登录：GET / → $RC ($LOC)   POST /api/world → $API"
echo "  登录页有内容：$([ -n "$PAGE" ] && echo yes)"

if [ -n "$CHECK_FAIL" ]; then
  echo "=== 核验未过：$CHECK_FAIL ==="
  echo "按 §10：宁可关站，不回无门公开版（不把 current 切回 $LIVE）"
  $EMERG close
  echo "CUTOVER=FAILED_AND_CLOSED  现场留在此状态等人判断，不自动重试"
  exit 1
fi

# 4) 留档
mkdir -p "$STATE"
{ date -u +%FT%TZ; echo "approved=$SHA"; echo "previous=$LIVE"; echo "recovery_s=$(echo "$T1 - $T0" | bc)"; echo "$HZ"; } \
  > "$STATE/cutover-$(date +%Y%m%d-%H%M%S).txt"

echo "=== 切流完成 ==="
echo "CUTOVER=OK  线上现在是 $SHA"
echo "  关站（一条命令）：$EMERG close"
echo "  撤销关站：$EMERG restore"
echo "  版本级回退只允许在本系列内含访问门的提交之间进行，$LIVE 不是安全回滚目标"
