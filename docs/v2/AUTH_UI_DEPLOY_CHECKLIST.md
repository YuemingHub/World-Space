# AUTH UI DEPLOY CHECKLIST — 运维部署清单（未执行）

> 2026-09-14，回滚语义 2026-09-15 修正。给运维的最小步骤。批准 SHA 与执行时机由 Founder 决定；本文不含任何真实秘密。
> 目标：让 ymai.fun 以"默认关闭、认证就绪"的状态上线 V0.1，并且**任何一步失败都落在关着门的状态**。

## 0. 本仓库真实部署坐标（照抄会跑空的地方）

线上实际布局与本文通用示例不同，以实际为准：

```text
发布根      /opt/world-space/releases/<SHA>/      切版本开关 = /opt/world-space/current 符号链接
共享 env    /opt/world-space/shared/env/world-space.env      600 root
账本        /opt/world-space/shared/data/budget.json         wsapp 可写
服务        world-space.service（用户 wsapp，enabled，Restart=always）
上游端口    127.0.0.1:3200（不是示例里的 8787）
入口        nginx sites-available/world-space（80 跳转 + 443 反代，proxy_read_timeout 180s）
仓库外私有文件按第 1 节放在 /opt/world-space/etc/（示例里的 /srv/world-space/etc 同理，二选一后全文一致即可）
```

⚠️ 端口与路径必须逐项对齐后再启动：`current` 换版本、服务读同一份 env、nginx 代理同一端口，
三者任一对不上都是"看起来上线了、其实在跑旧版本或 502"。

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
- 用户文件变更（加人/删人）即时生效，无需重启；删人后其会话立即失效。
- ~~轮换 Tavily 旧 key~~ → **这不是上线后的事**：已提到第 9 节，属于切流前 blocker，没做完不许开门。

## 8. 回滚：fail closed，宁可关站也不开门

**原则（2026-09-15 修正，原文"切回上一个批准 SHA 重启即可"容易被读成退回 85c7b91，作废）：**

```text
认证版本出问题 → 宁可关站 → 不能回到公开版
OLD PUBLIC VERSION ≠ SECURITY ROLLBACK
```

### 8.1 明确不是回滚目标的东西

| 候选 | 为什么不能用 |
|---|---|
| `85c7b91`（当前公网在跑的 Outcome Loop MVP） | **没有访问门**：不校验身份、不区分用户、无登录限流。退回它＝用一次故障换一次更大暴露 |
| `6e73725` 及更早中间提交 | 同样无门 |
| `main` 分支 / GitHub Pages 静态站 | 无门，且没有 V0 回路；重新启用那三条被 DISABLE 的 Pages A 记录＝主动把公开站指回来 |
| 任何"先改 DNS 指回旧站"的临时救火 | 本次发布 DNS 从来不是开关，改它只会掩盖问题并扩大暴露 |

**保留**（备份是取证与恢复用的，不是回滚目标）：`current` 符号链接、
`releases/` 下每一个 SHA 目录、`shared/env/world-space.env` 及其 `.bak-*`、
`shared/data/budget.json`、`world-space.service`（关站脚本刻意不 stop 它，日志要继续留）。
关站不删任何东西。

### 8.2 两级回滚梯度

```text
A. 新版本能用、只是某个功能坏了
   → 在【含访问门的本系列提交】之间回退 current 并重启
   → 门还在，只是行为回到旧版本
   → 若本系列内没有可回退的更早提交：不许退回无门版本，走 B

B. Node / 认证 / 入口出现核心故障，来不及判断
   → world-space-emergency.sh close
   → Nginx 临时对所有路径返回 503 + 维护页（"World Space 暂时不可用，请稍后再试。"）
   → 不代理旧公开 World Space，不代理任何 upstream，不切回 GitHub Pages
```

维护页不含任何用户数据、不带 cookie、`no-store` + `noindex`。

### 8.3 关站方案必须在切流前装好并验过

文件与步骤在 `docs/v2/release-c500f3d/`：
`EMERGENCY_CLOSED.md`（说明）+ `emergency-closed/`（可直接安装的 nginx 块、维护页、控制脚本）。

```bash
world-space-emergency.sh install      # 放置 sites-available/world-space-closed，nginx -t 必过（不启用）
world-space-emergency.sh preflight    # 独立 nginx 进程验证 503 + 维护页真的成立，不影响公网
world-space-emergency.sh status       # 留档：切流前入口层是 LIVE 还是 CLOSED
```

切流时正常块与关站块**不能同时 enabled**（字母序 `world-space` 在前会赢，等于没关站）；
脚本用移动符号链接的方式互斥切换，且 `nginx -t` 失败会自动回退，不留半开状态。
未装未验 = `EMERGENCY_CLOSED=MISSING`，不许切流。

## 9. 切流前 blocker：搜索凭据（原第 7 节遗留项，提前）

在任何公网切流之前，按顺序做完并只报三个状态值（**不得把任何 key 写进 Git / 日志 / 报告 / 聊天**）：

```text
1. 确认历史暴露过的那把 Tavily key 是哪把（本地开发 env 与服务器 env 的指纹必须不同）
2. 在 Tavily 控制台 revoke / disable 旧 key，并确认状态为已删除/已停用
3. 生成或取得新的生产 key，写入服务器仓库外私有 env（600，服务用户可读，Git 不可见）
4. localhost 用新 key 做一次真实搜索 smoke（拿到真实结果，日志与响应里不出现 key）
```

```text
OLD_TAVILY_KEY_REVOKED=yes
NEW_SEARCH_KEY_CONFIGURED=yes
SEARCH_SMOKE=PASS
```

任一项不是 yes / PASS：

```text
DEPLOY_BLOCKED_SEARCH_SECRET
```

停在这里，不切流。
