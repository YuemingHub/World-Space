#!/usr/bin/env bash
# 在服务器上生成访问门需要的两个仓库外私有文件：users.json + session-secret.txt
#
# 纪律：明文口令从头到尾不 print 到标准输出，只落进 600 的 first-login.txt，
#       由运维 scp 回自己电脑本机查看；日志、聊天记录、Git 里都不会出现口令。
# 口令生成在目标机上进行（24 bit/字符 × 16 位，约 80 bit），字符表刻意排除了
# 0/O、1/l/I 这类在手机上容易看错的形状。
set -euo pipefail

REL="${WS_REL:-/opt/world-space/releases/c500f3d76601abb263511cb622efd38379e8b959}"
PRIV="${WS_PRIV:-/opt/world-space/etc}"
SVC_USER="${WS_SVC_USER:-wsapp}"

[ -f "$REL/scripts/hash-password.mjs" ] || { echo "FAIL: 发布树里找不到 hash 工具：$REL" >&2; exit 1; }
install -d -m 750 -o root -g "$SVC_USER" "$PRIV"

genpw() { # 不能用 `tr … < /dev/urandom | head -c N`：pipefail 下 head 提前关管道会让 tr 收到
          # SIGPIPE，整条命令返回 141，脚本在第一个口令上就死（本轮实测踩过）。cut 会读完上游。
  head -c 512 /dev/urandom | tr -dc '23456789abcdefghjkmnpqrstuvwxyz' | cut -c1-16
}
PA=$(genpw)
PB=$(genpw)
[ "${#PA}" = 16 ] && [ "${#PB}" = 16 ] || { echo "FAIL: 口令生成长度不足 16，拒绝继续（不用弱口令）" >&2; exit 1; }

HA=$(printf %s "$PA" | node "$REL/scripts/hash-password.mjs" u-owner ymai)
HB=$(printf %s "$PB" | node "$REL/scripts/hash-password.mjs" u-guest test)

printf '{"users":[%s,%s]}\n' "$HA" "$HB" > "$PRIV/users.json.tmp"
node -e '
const fs = require("fs");
const f = process.argv[1];
const j = JSON.parse(fs.readFileSync(f, "utf8"));
if (!Array.isArray(j.users) || j.users.length !== 2) throw new Error("用户数不对");
for (const u of j.users) {
  if (!/^scrypt\$16384\$8\$1\$/.test(u.password_hash)) throw new Error("hash 格式不合规: " + u.user_id);
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$/.test(u.user_id)) throw new Error("user_id 非法: " + u.user_id);
}
if (j.users[0].user_id === j.users[1].user_id) throw new Error("user_id 重复（服务端会当坏文件 fail closed）");
fs.renameSync(f, f.replace(/\.tmp$/, ""));
console.log("users.json 合规：", j.users.map(u => u.user_id + "（用户名 " + u.username + "）").join("、"));
console.log("明文密码字段存在？", j.users.some(u => "password" in u) ? "有——不允许" : "无，只有 scrypt hash");
' "$PRIV/users.json.tmp"

[ -f "$PRIV/session-secret.txt" ] || head -c 48 /dev/urandom | base64 > "$PRIV/session-secret.txt"

cat > "$PRIV/first-login.txt" <<EOF
World Space V0.1 首次登录口令（生成于 $(date '+%F %T')）
本机专用：别转发、别截图、别贴进任何聊天窗口。

A 账号（你日常用）      用户名: ymai   密码: $PA
B 账号（隔离验证用）    用户名: test   密码: $PB

访问地址：https://ymai.fun/（切流批准后才是这个版本）
本系列没有"忘记密码/改密码"功能；换口令 = 重写 users.json 一行，随时找我。
这份文件看完就可以让我抹掉。
EOF

chmod 600 "$PRIV/users.json" "$PRIV/session-secret.txt" "$PRIV/first-login.txt"
chown "$SVC_USER":"$SVC_USER" "$PRIV/users.json" "$PRIV/session-secret.txt" "$PRIV/first-login.txt"

echo "--- 权限实核（服务用户必须读得到，Git 必须看不见）---"
ls -l "$PRIV"
sudo -u "$SVC_USER" test -r "$PRIV/users.json" && echo "  wsapp 可读 users.json: yes"
sudo -u "$SVC_USER" test -r "$PRIV/session-secret.txt" && echo "  wsapp 可读 session-secret: yes"
echo "  Git 是否跟踪这些文件: $(git -C "$REL" ls-files --error-unmatch "$PRIV/users.json" 2>/dev/null || echo '否（在仓库外，Git 不可能看见）')"
