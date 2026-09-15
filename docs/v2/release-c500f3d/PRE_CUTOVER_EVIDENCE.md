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

## 7. 搜索凭据（§4）— 已定位到最后一格，只差 Founder 一次控制台操作

实测事实（全部只输出指纹与状态码，明文没出现过）：

```text
服务器共享生产 env 在用的那把   指纹 32b9a395ef8f → Tavily 401，已死
桌面 ws-key.txt：三行非空，其中两行各含一把 tvly- 开头、长 58 位的 key
  第 1 行里的 key 指纹 74f41d0013af → Tavily 200，真实返回 1 条结果  ★ 能用
  第 4 行里的 key 指纹 4002d0bdf8d6 → Tavily 200，真实返回 1 条结果  ★ 能用
两把都在用 tvly-dev- 前缀（开发计划），且都与 env 里那把不同
```

中间踩到自己一个探针错误（记 L27）：那两行是「标签: key」格式，我第一遍把**整行**
当 Bearer 发出去，于是两把都"401"——差点把她的可用 key 判成废的。抽 token 重测才是真结果。

**为什么还不能定生产 key**：本轮会话窗口里出现过一把 `tvly-dev-` 开头的 key（同一形状、同一长度）。
文件里这两把中**必有一把就是它**，而我不肯为了区分再抄一次明文（那等于第二次扩散）。
所以按 §4 的定义：

```text
OLD_TAVILY_KEY_REVOKED      = 未定（env 那把已死是事实；"当年暴露的那把是哪一把"待 Founder 按控制台列表认）
NEW_SEARCH_KEY_CONFIGURED   = no （还没写进任何 env）
SEARCH_SMOKE                = 未跑（新 key 一到位就连同 §12 那四条红一起收）
```

→ **DEPLOY_BLOCKED_SEARCH_SECRET**，不切流。

下一步（Founder 在 Tavily 控制台做一次，之后我一轮收尾）：

```text
1. 把两把"能用但来路说不清"的 key 都删掉/停用，新建一把只属于生产的 key；
   或者：直接告我"文件里第 1 行那把是新写的、聊天里那把是第 4 行"（只回行号，不贴值）
2. 我随后做三件事：把干净那把写进 smoke env 与生产 env（改文件不重启服务，公网行为不变）；
   拿服务器已有的那三个旧指纹各发一次请求，看是否全部变 401 ——
   这才是 OLD_TAVILY_KEY_REVOKED=yes 的物证，不靠口头；
   最后跑那一轮权威 smoke（约 ¥0.1–0.2），一次收齐 OUTCOME_LOOP / SEARCH_SMOKE / B 隔离
```

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

## 9. 本轮留下的运行物与文件（如实清点）

```text
本机（开发机）：三个桩实例 127.0.0.1:8791/8792/8793 仍在跑
  （provider=stub、search=fixture，不联网不花钱；停止命令被安全层拦下，未绕路）

Founder 桌面 ws-login.txt（512B，含两个账号的明文口令，值未经过聊天）
  ACL 实核：YMAI\User + NT AUTHORITY\SYSTEM + BUILTIN\Administrators 之外，
  还有 **YMAI\CodexSandboxUsers 可读** —— 不是 Everyone，但意味着本机沙箱类工具也读得到。
  → 建议：她读完就让我把这份和服务器上的同源副本一起抹掉（删除前会单独问她）

服务器：
  /opt/world-space/etc/users.json / session-secret.txt / first-login.txt   600 wsapp
  /opt/world-space/etc/tavily-key.new   600 wsapp —— 她文件里的两把可用 key 原文在此，
    **尚未写入任何 env**；等 Founder 认定哪一把来路干净后再决定去向（含之后要不要抹掉这份）
  /etc/nginx/sites-available/world-space-closed —— 已装未启用
  /opt/world-space/shared/env/world-space.v01-smoke.env + data/budget-smoke.json —— 验证专用
  /opt/world-space/releases/c500f3d…/ —— 发布树，current 未指向它
  3210 验证实例已停（实测无监听）；公网 3200 与 nginx 全程未动
```
