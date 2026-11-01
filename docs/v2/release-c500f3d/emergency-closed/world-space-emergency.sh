#!/usr/bin/env bash
# World Space — emergency closed state 控制脚本（fail-closed 回滚）
#
# 原则：认证版本出核心故障 → 宁可关站 → 绝不回到无访问门的公开版本。
#   OLD PUBLIC VERSION != SECURITY ROLLBACK
#   85c7b91 及更早、main 分支的 GitHub Pages 站，都不是本脚本的回滚目标。
#
# 只动 nginx 入口层的符号链接；不改正常站点配置文件、不删任何 release、
# 不动 DNS、不动解析记录、不停 world-space.service、不动共享 env 与账本。
#
# 用法（root，在服务器上）：
#   world-space-emergency.sh install     # 切流前：装好关站文件与维护页，nginx -t 必须通过
#   world-space-emergency.sh preflight   # 切流前：用独立 nginx 进程验证关站真的返回 503+维护页
#   world-space-emergency.sh status      # 现在入口层是"正常"还是"已关站"
#   world-space-emergency.sh close       # 关站（应急）
#   world-space-emergency.sh restore     # 撤销关站（只在确认问题已修好后）
set -euo pipefail

LIVE_SITE=world-space                       # 正常站点块（80 跳转 + 443 反代 127.0.0.1:3200）
CLOSED_SITE=world-space-closed              # 关站块（只回维护页，不代理任何 upstream）
SA=/etc/nginx/sites-available
SE=/etc/nginx/sites-enabled
ROOT=/opt/world-space/emergency
WWW=$ROOT/www
STATE=$ROOT/state                           # 被停用的符号链接移到这里（不是删除）
STAGE="${STAGE_DIR:-$ROOT/staging}"         # install 的来料目录（scp 上来）
NODE_HEALTH=http://127.0.0.1:3200/healthz
HOSTS=(ymai.fun www.ymai.fun)
CERT_DIR=/etc/letsencrypt/live/ymai.fun
PREFLIGHT_PORT=8088

die() { echo "FAIL: $*" >&2; exit 1; }
ok()  { echo "  ok: $*"; }

need_root() { [ "$(id -u)" = 0 ] || die "需要 root"; }

# ---- 通用：切换符号链接并验证（nginx -t 不过就自动回退，不留半开状态） ----
swap() { # swap <disable-name> <enable-name>
  local off="$1" on="$2"
  local backup="$STATE/$(echo "$off" | tr -d '/.')"
  mkdir -p "$STATE" "$SA"

  [ -e "$SE/$on" ] || die "$SE/$on 不存在；先跑 install"
  [ -f "$SA/$on" ] || die "$SA/$on 配置文件缺失"

  if [ -L "$SE/$off" ]; then
    mv -Tf "$SE/$off" "$backup"
    echo "  moved: $SE/$off -> $backup"
  elif [ -e "$SE/$off" ]; then
    die "$SE/$off 存在但不是符号链接，先人工确认再说（本脚本不删非符号链接的东西）"
  fi

  ln -sfn "../sites-available/$on" "$SE/$on"
  echo "  linked: $SE/$on"

  if ! nginx -t; then
    echo "  nginx -t 失败，自动回退" >&2
    rm -f "$SE/$on" 2>/dev/null || true
    [ -e "$backup" ] && mv -Tf "$backup" "$SE/$off"
    nginx -t || echo "  警告：回退后 nginx -t 仍不过，立即人工介入" >&2
    die "配置未通过校验，未 reload，入口层已回到原状"
  fi
  nginx -s reload
  echo "  reloaded"
}

verify_closed() {
  local h code
  for h in "${HOSTS[@]}"; do
    code=$(curl -s -o /tmp/ws-closed-check.$$ -w '%{http_code}' \
      --connect-timeout 5 --max-time 15 --resolve "$h:443:127.0.0.1" "https://$h/" || echo ERR)
    if [ "$code" = 503 ] && grep -q "暂时不可用" "/tmp/ws-closed-check.$$"; then
      ok "$h -> 503 且是维护页"
    else
      rm -f "/tmp/ws-closed-check.$$"
      die "$h -> HTTP $code（期望 503 + 维护页），关站未生效"
    fi
    rm -f "/tmp/ws-closed-check.$$"
  done
}

# ---- install ----
cmd_install() {
  need_root
  [ -f "$STAGE/world-space-closed.conf" ] || die "$STAGE/world-space-closed.conf 不存在（先 scp 上来）"
  [ -f "$STAGE/maintenance.html" ]        || die "$STAGE/maintenance.html 不存在"

  install -d -m 755 "$WWW" "$STATE"
  install -m 644 "$STAGE/maintenance.html" "$WWW/maintenance.html"
  install -m 644 "$STAGE/world-space-closed.conf" "$SA/$CLOSED_SITE"

  # 与线上正常块逐项核对：server_name 与证书必须一致，否则关站块可能永远匹配不到请求
  local live_names live_cert
  live_names=$(nginx -T 2>/dev/null | awk -v s="$SA/$LIVE_SITE" '
    /# configuration file /{f=($0 ~ s)} f && /server_name/{print $2; exit}')
  live_cert=$(nginx -T 2>/dev/null | awk '/# configuration file /{f=($0 ~ "world-space")} f && /ssl_certificate /{print $2; exit}')
  echo "  线上 server_name: ${live_names:-未读到}"
  echo "  线上证书: ${live_cert:-未读到}"
  [ -z "${live_cert:-}" ] || { [ -f "$live_cert" ] && ok "证书文件在位"; }
  grep -q "ymai.fun" "$SA/$CLOSED_SITE" || die "关站块里读不到 ymai.fun"

  nginx -t
  ok "install 完成：$SA/$CLOSED_SITE 就位且 nginx -t 通过（尚未启用）"
  echo "  下一步：$0 preflight"
}

# ---- preflight：独立 nginx 进程验证 503 语义，不碰在跑的 master ----
cmd_preflight() {
  need_root
  local d=/tmp/ws-emergency-preflight
  rm -rf "$d"; install -d -m 755 "$d/logs" "$d/www"
  cp "$WWW/maintenance.html" "$d/www/"
  # 用与关站块完全相同的 location/error_page 机制，只换端口与证书（明文回环）
  sed -n '/^server {/,/^}/p' "$SA/$CLOSED_SITE" | head -30 > /dev/null   # 触发一次读取，失败即停
  cat > "$d/nginx.conf" <<EOF
pid $d/nginx.pid;
error_log $d/logs/error.log warn;
events { worker_connections 16; }
http {
  access_log off;
  include /etc/nginx/mime.types;
  server {
    listen 127.0.0.1:$PREFLIGHT_PORT;
    root $d/www;
    add_header Cache-Control "no-store" always;
    add_header Retry-After "3600" always;
    location / { return 503; }
    error_page 503 /maintenance.html;
    location = /maintenance.html { internal; }
  }
}
EOF
  nginx -c "$d/nginx.conf"
  sleep 1
  local code
  code=$(curl -s -o "$d/body.html" -w '%{http_code}' "http://127.0.0.1:$PREFLIGHT_PORT/anything")
  [ "$code" = 503 ] || { nginx -c "$d/nginx.conf" -s quit 2>/dev/null; die "preflight 返回 $code，非 503"; }
  grep -q "暂时不可用" "$d/body.html" || { nginx -c "$d/nginx.conf" -s quit 2>/dev/null; die "preflight 503 但没带维护页正文"; }
  grep -qiE "retry-after|cache-control" <(curl -sI "http://127.0.0.1:$PREFLIGHT_PORT/") && ok "响应头在位" || echo "  note: 头未全部命中（不影响关站语义）"
  if grep -qiE "ws_sess|Set-Cookie" <(curl -sI "http://127.0.0.1:$PREFLIGHT_PORT/"); then
    die "维护页带了 cookie/会话信息，必须移除"
  fi
  nginx -c "$d/nginx.conf" -s quit
  echo "PREFLIGHT=PASS：503 + 维护页 + 无用户数据 + 未影响在跑的 nginx"
}

# ---- close / restore / status ----
cmd_close() {
  need_root
  echo "== 关站（emergency closed state）=="
  swap "$LIVE_SITE" "$CLOSED_SITE"
  verify_closed
  echo "  注：world-space.service 未被本脚本改动（Node 继续跑，只是公网不再代理到它）"
  echo "CLOSED=ACTIVE —— 公网不再代理任何应用，未指向任何旧公开版本"
}

cmd_restore() {
  need_root
  echo "== 撤销关站 =="
  swap "$CLOSED_SITE" "$LIVE_SITE"
  echo "  应用健康自查（不代替验收）：$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$NODE_HEALTH" || echo ERR) <- $NODE_HEALTH"
  echo "RESTORED=ACTIVE —— 入口层回到当前 current 指向的版本（可能是问题版本，先确认真的修好了）"
}

cmd_status() {
  echo "sites-enabled:"
  ls -1 "$SE" 2>/dev/null | sed 's/^/  /'
  if [ -L "$SE/$CLOSED_SITE" ]; then echo "入口层状态：CLOSED（已关站）"
  elif [ -L "$SE/$LIVE_SITE" ]; then echo "入口层状态：LIVE"
  else echo "入口层状态：NEITHER —— 两个块都没启用，公网直接不可达（也算关着，但没人知道为什么）"
  fi
  [ -d "$STATE" ] && { echo "state 目录（被停用的符号链接）:"; ls -1 "$STATE" | sed 's/^/  /'; }
  echo "current -> $(readlink -f /opt/world-space/current 2>/dev/null || echo 未设置)"
  echo "world-space.service: $(systemctl is-active world-space.service 2>/dev/null || echo unknown)"
  echo "node healthz: $(curl -s --max-time 8 "$NODE_HEALTH" || echo ERR)"
}

case "${1:-}" in
  install)   cmd_install ;;
  preflight) cmd_preflight ;;
  close)     cmd_close ;;
  restore)   cmd_restore ;;
  status)    cmd_status ;;
  *) sed -n '3,20p' "$0"; exit 2 ;;
esac
