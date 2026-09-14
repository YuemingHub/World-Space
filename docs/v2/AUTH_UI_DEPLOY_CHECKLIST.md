# AUTH UI DEPLOY CHECKLIST — 运维部署清单（未执行）

> 2026-09-14。给运维的最小步骤。批准 SHA 与执行时机由 Founder 决定；本文不含任何真实秘密。
> 目标：让 ymai.fun 以"默认关闭、认证就绪"的状态上线 V0.1，并且**任何一步失败都落在关着门的状态**。

## 1. 准备两个仓库外私有文件（服务器上，不在 Git 里）

```bash
# 1a. session secret（≥32 字节随机串）
head -c 48 /dev/urandom | base64 > /srv/world-space/etc/session-secret.txt
chmod 600 /srv/world-space/etc/session-secret.txt

# 1b. 用户文件（先想好 user_id：小写字母数字，会出现在本机存储键名里）
node /srv/world-space/repos/World-Space/scripts/hash-password.mjs u-owner <owner 用户名> < /dev/stdin
#   ↑ 提示后手输一行密码（或从本地文件管道输入），把输出的一行 JSON 记下来
#   为第二个用户重复一次（如需要）
```

手写 `/srv/world-space/etc/users.json`：

```json
{ "users": [
  { "user_id": "u-owner", "username": "<owner 用户名>", "password_hash": "<上一步输出>" }
] }
```

```bash
chmod 600 /srv/world-space/etc/users.json
chown <服务运行用户> /srv/world-space/etc/users.json /srv/world-space/etc/session-secret.txt
```

校验：`user_id` 只能是 `[A-Za-z0-9][A-Za-z0-9_-]{0,31}`；hash 必须是 `scrypt$16384$8$1$…` 格式（服务端会拒绝明文密码文件——这是故意的）。

## 2. 配置 env（服务单元 / 启动脚本）

```bash
WS_PORT=8787                       # 或现有反代上游端口
WS_HOST=127.0.0.1                  # 只听本机，公网走 Nginx
WS_AUTH_USERS_FILE=/srv/world-space/etc/users.json
WS_SESSION_SECRET_FILE=/srv/world-space/etc/session-secret.txt
WS_SESSION_MAX_AGE=604800          # 7 天（可选，默认同值）
WS_COOKIE_SECURE=1                 # Nginx 终止 TLS 时显式开启（或确认 WS_TRUST_PROXY=1 + 转发 proto 头）
WS_TRUST_PROXY=1                   # Nginx → Node 单层受信代理（限流取真实 IP + proto 判断）
# 既有生产配置照旧：WS_PROVIDER / WS_LLM_* / WS_SEARCH* / WS_MONTHLY_CAP_RMB …
# 严禁在服务器上设置 WS_AUTH_ENABLED=0（那是"公开访问"的显式开关，只用于本地开发）
```

## 3. 启动前自检（fail closed 验证，必须做）

```bash
# 3a. 故意先只配 secret、不配用户文件启动一次：
#     启动日志应出现 auth=FAIL_CLOSED(users_not_configured)
#     curl -s localhost:8787/healthz   → "auth":"broken:users_not_configured"
#     curl -i localhost:8787/api/world -X POST → 503 auth_unavailable
#     curl -i localhost:8787/          → 302 /login
# 3b. 补上用户文件重启：
#     healthz → "auth":"ready"
```

如果 3a 时任何接口返回了 200 业务数据——**停下来，这是 P0，不要继续**。

## 4. 启动批准 SHA + 本机 smoke

```bash
cd /srv/world-space/repos/World-Space && git fetch origin && git checkout <批准的 SHA>
# 按既有方式启动（env 见第 2 节）
curl -s localhost:8787/healthz | grep '"auth":"ready"'
# 未登录 API 必须 401：
curl -i -X POST localhost:8787/api/world -H 'content-type: application/json' -d '{"intent":"smoke"}'   # → 401
# 登录 → 带 cookie 调用成功：
curl -i -c /tmp/ws.jar -X POST localhost:8787/api/auth/login -H 'content-type: application/json' \
  -d '{"username":"<用户名>","password":"<密码>"}'    # → 200 + set-cookie（HttpOnly; SameSite=Lax）
curl -s -b /tmp/ws.jar -X POST localhost:8787/api/world -H 'content-type: application/json' \
  -d '{"intent":"smoke 测试"}' | head -c 200          # → 200 契约
# 错误密码统一口径：
curl -s -X POST localhost:8787/api/auth/login -H 'content-type: application/json' \
  -d '{"username":"<用户名>","password":"wrong"}'     # → 401 "账号或密码不正确。"
rm -f /tmp/ws.jar
```

## 5. Nginx（已有站点上补两处）

- 反代到 `127.0.0.1:8787`，保持单层（Node 依赖"对端是受信代理"）：
  `proxy_set_header X-Forwarded-Proto $scheme;`（cookie Secure 自动判断依赖它）
- TLS 证书照旧（HTTPS 下浏览器才会收 Secure cookie）。

## 6. 公网 smoke（手机 + 电脑各一遍）

```text
https://ymai.fun          → 未登录自动到 /login
错误密码                   → "账号或密码不正确。"，连错 5 次 → "尝试次数太多…"
正确登录                   → 首页"你现在想做成什么？"
提交一句真实意图            → 得到行动（约 20-90 秒，诚实 loading）
刷新                       → 恢复上一轮
退出 → 后退                 → 不出现上一轮内容
退出后手打 https://ymai.fun/api/world 的 POST（可用 curl 无 cookie）→ 401
```

## 7. 上线后

- `/healthz` 盯 `auth:"ready"` 与 `month_cost_rmb`（月上限 20 元硬闸）。
- 轮换 Tavily 旧 key（上一轮遗留，部署前必须做）。
- 用户文件变更（加人/删人）即时生效，无需重启；删人后其会话立即失效。

## 8. 回滚

如需回滚：切回上一个批准 SHA 重启即可；`var/budget.json` 与用户文件、secret 不受影响。**不存在"回滚到无门版本"的选项**——旧版本（85c7b91 及更早）没有访问门，只应回滚到本系列更早的中间提交。
