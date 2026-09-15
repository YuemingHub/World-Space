# PRE-CUTOVER EVIDENCE — V0.1 @ c500f3d（2026-09-15 本轮实际做过的事）

> 候选：`v2` @ `c500f3d76601abb263511cb622efd38379e8b959`。
> **公网未被改动**：`ymai.fun` 仍由 `85c7b91` 提供、`current` 未换、`world-space.service` 未重启、
> nginx 入口未动、DNS 未动、共享生产 env 未改一字。本文不含任何真实密钥值或口令。

## 1. 候选锁死（§1）— 本地与服务器都已核

```text
本地 v2      = c500f3d76601abb263511cb622efd38379e8b959
origin/v2    = c500f3d76601abb263511cb622efd38379e8b959     working tree clean
发布准备物在分支 release/v01-c500f3d（v2 一个提交都不加，否则"HEAD = 批准 SHA"是假话）

服务器 /opt/world-space/releases/c500f3d…/
GIT=PASS  发布树 117 个文件逐内容与 c500f3d 相同，无缺失、无多余（只读比对）
树清单留档 cf00876a50199d0e80505beb66ef66ed5aa6636757e3ad33b2e7b650b61ec82f
current -> releases/85c7b91…（未动）
```

取树方式：服务器自己在机内 `git fetch` GitHub 的 `v2`，先断言 `v2 == 批准 SHA` 才展开，
不一致直接 `PREDEPLOY_ABORT_GIT_DRIFT`。展开用 `git archive`（发布树里不留 `.git`，
避免"目录里有个仓库"被误当成可随意改的工作区）。

## 2. Gate 全量（§11）— 服务器真实发布树 13/13 绿

```text
在 /opt/world-space/releases/c500f3d…/ 内、用生产运行时 Node v20.20.2 跑：
runtime-isolation authority adapter-shape admission retry liveness xss-boundary
budget-cap date outcome-loop frontend-e2e runtime auth  → ALL_GATES=PASS
```

开发机（Node v24）另有一次同 SHA 全绿（`2026-09-15T10:52Z`），只作为交叉印证；
判定以服务器那一遍为准，因为它跑的是真实发布树 + 真实运行时。全部离线桩，0 外网 0 花费。

## 3. 访问门的生产配置与 fail closed（§2 §3）

仓库外私有文件（全部 600、属 `wsapp`、位于 Git 不可能看见的路径）：

```text
/opt/world-space/etc/users.json          两个账号，只有 user_id/username/scrypt hash
/opt/world-space/etc/session-secret.txt  48B 随机串，值从未出现在屏幕/日志/聊天
/opt/world-space/etc/first-login.txt     明文口令唯一落点（600），等运维 scp 回本机查看
/opt/world-space/etc 目录 750 root:wsapp —— 写成 700 会让 wsapp 进不去目录，直接把门自己关死
```

hash 用仓库自带的 `scripts/hash-password.mjs`（口令走标准输入，不进命令行参数）。
明文口令由脚本在目标机上生成，字符表排除 0/O、1/l/I 这类手机上易混的形状。

fail closed 实机验证（故意把 users.json 移开、只留 secret 后启动）：

```text
healthz          auth=broken:users_unreadable_or_bad_json
GET /            302 → /login
POST /api/world  503 {"error":"auth_unavailable","reason":"users_unreadable_or_bad_json",…}
业务接口没有一次 200 → AUTH_FAIL_CLOSED=PASS（没有 PREDEPLOY_REJECTED_AUTH_FAIL_OPEN）
```

## 4. 关站回滚（§10）— 已装、已预演、未启用

```text
/etc/nginx/sites-available/world-space-closed  就位，nginx -t 通过，未 enable
PREFLIGHT=PASS：503 + 维护页 + 无用户数据 + 未影响在跑的 nginx
入口层状态：LIVE（公网照旧 200，本轮从未 close）
```

预演用的是**独立 nginx 进程**绑 127.0.0.1:8088，因此没有对公网做 reload、没有拿线上演练。
正常块 `server_name ymai.fun`（实测无 www）；证书路径与线上一致
`/etc/letsencrypt/live/ymai.fun/fullchain.pem`。回滚语义与"哪些版本不是安全退路"见
`EMERGENCY_CLOSED.md` 与部署清单第 8 节。

## 5. 运行边界（§6 §7 §8 §9）

本机验证实例由生产 env 派生的 `world-space.v01-smoke.env`（600）启动，逐项回读：

```text
WS_AUTH_ENABLED   未设置 = 访问门开着（生产禁止 =0）
WS_COOKIE_SECURE  1        WS_TRUST_PROXY 1      WS_TRUSTED_PROXIES 127.0.0.1
WS_HOST           127.0.0.1  WS_PORT 3210        单实例（无 cluster/worker）
WS_ALLOWED_ORIGINS https://ymai.fun（唯一正式来源）
WS_DAILY_CAP      50       WS_MONTHLY_CAP_RMB 20    budget fail_closed=true
```

CORS 代码里不存在 `*`：只回显被允许的那个 Origin，且不下发 `allow-credentials`；
陌生来源实测 403 `origin_not_allowed`（见 §12 那一轮输出）。
Cookie 三旗标 `HttpOnly / Secure / SameSite=Lax` 实测都在，且不含口令字样。

⚠️ 一处刻意的偏差：本机实例用**独立账本** `budget-smoke.json`。
让第二个实例与公网实例并发读写同一份账本有覆盖风险（预算是钱），
代价是"真实月度花费 = 生产账本 + 本机账本"，两份数字都已在报告里给出，不做合并粉饰。

## 6. §12 正式模式 smoke — 权威一轮：PASS=22 FAIL=4

第一遍 `PASS=12 FAIL=12` 里有 7 个红是**判定器条件反了**造成的假红，而真正该红的
"第一轮 502"被记成了绿（L24）。修好并加上"判定器自检"后重跑，这一轮的数字可信：

已经拿到硬证据（与搜索 key 无关的部分，全部实测）：

```text
auth=ready（正式配置，非桩）
未登录 GET / → 302 → /login          未登录 POST /api/world → 401
错误口令 → 401「账号或密码不正确。」   「没这个账号」与「密码错」逐字节一致（无枚举信号）
A 登录成功 → /api/auth/me 认到 u-owner → 首页出现「你现在想做成什么？」
Set-Cookie: HttpOnly + Secure + SameSite=Lax + Path=/   （WS_COOKIE_SECURE=1 真的生效）
cookie 内不含口令字样
logout 后旧 cookie → /api/world 401、首页弹回 /login     页面响应 cache-control: no-store
篡改签名的 cookie 一律不认
陌生 Origin → 403；正式 Origin 才回显 allow-origin；响应里不存在 '*'；不下发 allow-credentials
前端回路键 ws.loop.v1:' + USER（按人分主）
```

四条真红（**都不是认证问题，两条同因**）：

```text
✗ 第一轮拿到真实行动 / ✗ 第一轮 search_calls>0 / ✗ 第二轮 receipt_ingested
   → 第三次的实际返回是 {"code":"search_http_401"}：搜索 key 被 Tavily 拒
   → 前两次的 llm_http_429 是模型网关限流，第 3 次已穿过（说明 429 是会自己好的短时窗口）
✗ B 认到 u-guest
   → 我的提取 bug（L26：贪婪 sed 把 Max-Age 的值当成了令牌），不是产品问题；已修，待复跑
```

花费实账（两份账本相加才是真数）：

```text
本机验证实例  today=15  month_cost=¥0.211396   cap 50/day、¥20/month、fail_closed=true
公网实例      today=16  month_cost=¥1.288846   （85c7b91，auth 字段不存在——它是无门版本）
→ 本月真实累计 ¥1.50，与本轮事前预估（¥0.2～0.4）一致
```

## 7. 搜索凭据（§4）— 决定性发现：服务器上那把 key 已经死了

```text
第三次尝试穿过模型网关后，返回 search_http_401 → Tavily 拒这把 key
本机实例的 WS_SEARCH_KEY 是从共享生产 env 原样继承的
→ 推论（高置信）：公网 85c7b91 现在的每一次真实请求，搜索阶段都在拿 401
  —— 线上搜索早就是坏的，且 /healthz 的 search_configured 只表示"变量非空"，永远看不出这点
服务器 env 这把的指纹 32b9a395ef8f（值未出现）
```

所以 §4 的三个状态值现在只能这样报：

```text
OLD_TAVILY_KEY_REVOKED   部分有据：env 里这把确实已不可用（401）；
                         但"当年暴露的那把是不是它"仍需 Founder 在控制台按显示名核对
NEW_SEARCH_KEY_CONFIGURED = no  —— 桌面 ws-key.txt 里那把还没灌进服务器：
                         两次尝试"读桌面文件→经隧道写入服务器→只输出 SAME/DIFF"都被安全层拦下
                         （拦点＝读取工作区外凭据文件），按纪律不绕路，已停手
SEARCH_SMOKE              = 未过（当前配置下必然 401；新 key 装上后在同一轮里验）
```

→ 按 §4 定义：**DEPLOY_BLOCKED_SEARCH_SECRET**，不切流。

另需 Founder 本人在 Tavily 控制台处理：本轮贴进会话窗口的 `tvly-dev-` key 与 anysearch key
**按已暴露对待**，删除或停用；生产 key 必须是没在聊天里出现过的那一把。

## 8. 明确没做（超范围，不是遗漏）

```text
抓 tavily.com/agent-setup/SKILL.md 执行 / 下载 anysearch skill 接第二个搜索源
→ 属"新增能力"，与本轮简报开头"禁止开发产品、修改 UI、调整模型逻辑"冲突；
  从第三方 URL 拉代码直接跑另需一次授权。要做请单开一轮。
方舟（Ark）key：按 §5 不碰。
公网切流：按 §14 不做。
```

## 9. 本机留下的运行物

三个本地桩实例（127.0.0.1:8791 / 8792 / 8793，provider=stub、search=fixture，
不联网不花钱）停止命令被安全层拦下，仍在运行；服务器上的 3210 验证实例已停（实测无监听）。
