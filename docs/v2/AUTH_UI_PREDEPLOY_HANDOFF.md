# AUTH UI PREDEPLOY HANDOFF — World Space V0.1

> 2026-09-14。这一轮把产品从"能工作的 Outcome Loop MVP"推进到**有访问门、可以交给首批用户、界面像成品的 V0.1**。
> 本文是 GPT 独立审核与 Founder 验收的入口。原始证据在本机 `eval/out/iter3/`（已 gitignore）。

## 1. Git

- branch：`v2`（main 未动，未部署，未动 ymai.fun / DNS / Nginx）
- base：`85c7b91`（Outcome Loop MVP 待审态）
- 本轮机制提交：
  - `f1050d2` 访问门骨架（登录/会话/退出/接口保护/fail closed/登录限流）
  - `74ca657` 行动回路按人隔离 + 退出接线 + 过期诚实送回
  - `3ade0a2` 登录页 UI（视觉基调变量建立）
  - `8f71c2a` 首页 UI（一个问题即整个页面）
  - `586de82` 结果页重排（唯一主行动 + done_when + 回执贴身 + progressive disclosure）
  - `94771ff` 交棒复制按钮拆分（复制任务书 ≠ 复制行动话术）
  - `8122ec0` 攻击探针记录 + Auth 自测 fixture 假红修复
  - `a9e8f0b` 结果页"换个新目标"出口
- final SHA：本文件所在提交（`git log -1`），已 push `origin/v2`，working tree clean

## 2. Auth 实际实现（server/auth.mjs + world.mjs 接线）

```text
访问 ymai.fun → 未登录 → /login（极简门）
→ POST /api/auth/login（scrypt 验证 + 每 IP 连续失败锁定）
→ 签名 HttpOnly session cookie（ws_sess）
→ / 产品页（你现在想做成什么？）
→ POST /api/world 需要有效会话；未登录 401，配置坏了 503
→ 退出：服务端吊销 + 清 cookie + 页面清空回登录
```

- **缺省开启，显式才关**：`WS_AUTH_ENABLED` 不设置 = 开启；`=0` 才关闭（本地离线开发/回归用），启动日志大声声明 `auth=OFF(公开访问，只用于本地离线开发)`。忘记配变量 ≠ 全网公开。
- **Fail closed**：开启但用户文件/secret 缺失、读不到、hash 格式坏、账号重复 → `auth=broken:<reason>`；业务 API 一律 503 `auth_unavailable`，页面弹到登录页（登录页如实说"服务没有配置好"）。运行中删配置立即生效（每次请求重读用户文件与 secret）。绝不退化成公开访问。
- **密码**：`scrypt$16384$8$1$salt64$hash128`（crypto.scrypt，16B 随机盐，64B key）；验证恒时比较（`timingSafeEqual`）；账号不存在也烧一次等价 scrypt（decoy），"没这个账号"与"密码错"响应逐字节一致、计时不可区分。参数闸：N/r/p 超界视为坏 hash（防登录时内存 DoS）。
- **Session**：`base64url({uid,iat,exp,v:1}) + "." + HMAC-SHA256(secret)`；负载无密码/无用户名/无用户正文；验证顺序 = 恒时验签 → 未过期 → 用户仍存在 → 未被登出吊销。Cookie：`HttpOnly; SameSite=Lax; Path=/; Max-Age=7天（默认，可配）`；`Secure` 由 `WS_COOKIE_SECURE=1` 或（受信反代 + `X-Forwarded-Proto: https`）自动开启。登出吊销表为内存 Set（token 哈希），重启即清——**单实例语义，与预算准入同一立场**。
- **登录限流**：每 IP 连续失败 ≥5 次（默认）锁定 10 分钟（默认），锁定期间正确密码也 429；成功清零；与 `/api/world` 的每分钟限流相互独立。不做验证码。
- **接口**：`POST /api/auth/login`、`GET /api/auth/me`、`POST /api/auth/logout`、`POST /api/world`（保护）、`GET /`（保护，302 /login）、`GET /login`（公开，已登录 302 /）、`/healthz`（公开，只报 `auth: ready|broken:<reason>|off`，不回显任何秘密）。
- **缓存纪律**：HTML 页面 `cache-control: no-store`——退出/换账号后浏览器后退不显示上一个人的内容。
- **日志纪律**：登录只记匿名事件（`auth login ok|fail|locked ip=…`），自测断言日志不含密码、不含用户名、不含 token。

## 3. 生产 secrets 如何提供（仓库里没有任何真实凭据）

```text
WS_AUTH_USERS_FILE     仓库外服务器私有 JSON：{"users":[{"user_id","username","password_hash"}]}
WS_SESSION_SECRET_FILE 仓库外私有文件，≥32 字节随机串
WS_SESSION_MAX_AGE     秒（默认 604800 = 7 天；钳位 10 分钟~90 天）
WS_AUTH_ENABLED        缺省开启；=0 才关闭（只应出现在本地开发）
WS_COOKIE_SECURE       =1 强制 Secure；缺省由受信反代 proto 自动判断
WS_LOGIN_MAX_ATTEMPTS  默认 5；WS_LOGIN_LOCK_MS 默认 600000
```

- hash 生成：`node scripts/hash-password.mjs <user_id> <username>`（密码从 stdin 读，不进 shell 历史/参数）。user_id 限 `[A-Za-z0-9][A-Za-z0-9_-]{0,31}`（它要进 localStorage 键名）。
- 模板见 `docs/v2/AUTH_UI_DEPLOY_CHECKLIST.md`；仓库与 Git 里只有工具、校验和测试 fixture（测试口令仅存在于自测文件，对应 hash 只在本机 `var/`）。

## 4. 用户隔离（Outcome Loop 的隐私边界）

- 身份唯一来源：`GET /api/auth/me`（服务端验签后的 user_id），浏览器自报不采信；client 侧再做一次字符白名单消毒。
- 回路键：`ws.loop.v1:<user_id>`。A 登录只读写 A；B 登录只见 B；A 回来恢复 A。退出保留本人本机数据（§15 允许），换账号绝对不可见。
- 迁移：登录功能加入前的旧单键 `ws.loop.v1` 在首次登录时迁入当前用户名下（Founder 单机连续性；迁移后旧键删除）。

## 5. UI 实际变化

- **登录页**：340px 居中窄列，World Space / 进入你的空间 / 账号 / 密码 / 进入，别无他物。48px 输入与按钮、label 关联、`autocomplete=username/current-password`、焦点环、错误一屏内可见（统一"账号或密码不正确。"）；配置坏时如实说服务未开放；`?expired=1` 显示"登录已过期"。已登录访问 /login 弹回 /。
- **首页**：问题垂直居中成为唯一主角（移动 28px / 桌面 32px），输入 120px 高，主按钮全宽在拇指位；顶栏只有品牌名 + 退出。
- **结果页**（信息架构按 §23 重排）：
  ```text
  你要做成（模型复述，弱化卡片）
  → 现在只做这一步（唯一 .action 块，18px，含"怎么算做完"虚线隔开）
  → 去做，然后把结果带回来（回执三按钮紧贴行动下方，不再沉到页尾）
  → 折叠第二层：有 n 个情况弄清后更准 / 为什么是这一步 / 世界上已经有什么（n） / 还有什么没有确定（n）
  → 换个新目标（常驻出口）
  ```
- **Progressive disclosure**：`<details>` 收起；**§27 例外**——不确定性折叠摘要行直接露出第一条（截断 44 字），重要风险不进幽灵折叠。
- **Handoff UI**：任务书块（复制→粘贴到目标→发送）+「复制任务书」+ 白名单「打开 DeepSeek ↗」；无技术字段；目标名匹配不上白名单就不给链接并明说。
- **三种模式语义**：human="这一步要你本人进入现实世界"（无任何交棒字样）；internal="在这一页就能完成"；handoff 显示任务书。回执按钮保持人话：做成了 ✓ / 卡住了 / 把结果带回来。
- **真实模型首次主动派发 handoff**（s4 押金微信）：目标名给的是模糊清单"任意通用 AI 对话工具（ChatGPT / DeepSeek / 豆包 / Kimi）"，前端白名单子串匹配到 DeepSeek → 官方入口唯一且来自前端代码——模糊目标名下的安全边界真实成立（上轮 L19"零主动 handoff"的观察在本轮 10 场景中被打破，如实记录）。

## 6. 真实浏览器旅程（受控 IAB；合成点击在 IAB 失效处用程序化 click 走真实处理器，见 §9 环境缺陷）

- **登录**：未登录 GET / → 302 /login；错误密码统一口径不进；正确账号 → / 首页；已登录 /login → 302 /
- **A/B 隔离**（stub 回路）：ming 提交意图 → 存 `ws.loop.v1:u-ming` → 刷新恢复（横幅+行动）→ 退出（DOM 清空回 /login）→ guest 登录看到全新提问页（零泄露，guest 的页面文本不含 ming 意图）→ guest 建立自己回路（`ws.loop.v1:u-guest`）→ 退出 → ming 回来只恢复 ming（页面不含"血压计"，数据核验两键各持其主）
- **真实 Outcome Loop**（真实 provider，deepseek-flash + Tavily）：
  - 第一轮（浏览器）：输入"我们小区里面的路灯坏两个星期了" → 诚实 loading（52 秒）→ human 模式行动（打物业要工单号）+ 可验证 done_when + 6 条不确定性（第一条露出）→ 刷新恢复
  - 回执"卡住了：物业说不归他们管，没给工单" → 第二轮：行动改为"打 12345 要受理编号"（换责任方，未重答原始意图，`receipt_ingested=true`）→ 第二轮契约在浏览器渲染 + 两次刷新恢复
  - 第二轮真实往返的请求期间 IAB 第三次崩溃，页面未接住响应；改由 HTTP 驱动取证（同 cookie 同语义），契约字节是真实 provider 输出，浏览器完成渲染与恢复验证
- **三种模式浏览器验证**（fixture 桩，如实区分于真实）：handoff 桩 → 任务书+唯一官方链接；空手交棒桩 → 降级 internal（无任务书字样、无外链）；回执桩 → human 模式（无交棒字样）。真实模型的 handoff 由 s4 单独佐证（见 §5）
- **篡改 localStorage**：坏 JSON → 安全回落提问页；对抗契约（`"><img onerror>`）→ 纯文本显示、脚本不执行
- **移动端**（DOM 几何审计，IAB 截图缺陷同上轮）：320/390/414/1280 四档，登录页与首页无横向溢出、主按钮 46-48px、触控目标达标；结果页 390 宽下唯一行动块与"做成了"第一屏可见

## 7. 本轮找到并处理的所有失败

| 编号 | 内容 | 类型 | 处理 |
|---|---|---|---|
| L22 | Auth 自测预算 fixture 跨运行累计 → 撞日上限假红 | 测试设施（P2） | spawn 前清状态文件 + 测试日上限 500；两连跑全绿 |
| — | `/login` 干净路径 404（serveStatic 不认无扩展名） | 产品缺陷（阶段1即修） | 静态映射 `/login → /login.html` |
| — | 登录锁定时长下限 30s 夹死测试配置 1.5s | 自测不可行（阶段1即修） | 下限改 1s（默认仍 600s） |
| — | 交棒与行动两个复制按钮同文案无法区分 | 体验摩擦 | 拆成「复制任务书」/「复制这句话」 |
| — | 一轮做完被困在当前目标（无换目标出口） | 体验摩擦 | 结果页常驻「换个新目标」 |
| ENV | IAB 三次在 48-73 秒长请求期间崩溃重置（about:blank + cookie 丢失）、截图 capture 失败、合成点击/键盘事件不落地 | 受控浏览器环境缺陷（同上轮 ENV，非产品） | 长往返改 HTTP 驱动取证；UI 验证用程序化 click 走真实处理器；几何审计替代截图 |
| L20 复发 | 深夜网关 502 一次（回执第二轮），重试即成功 | 外部依赖 | 诚实失败 + 再试一次，产品行为符合设计 |

## 8. 全部 Gate（13 项）

```text
runtime-isolation / authority / adapter-shape / admission / retry / liveness /
xss-boundary（标签白名单扩展 details/summary）/ budget-cap / date /
outcome-loop（回执差分/交棒契约/唯一主行动推导）/ frontend-e2e / runtime-selftest
+ 新增 auth-selftest（42+ 项断言：登录成败口径统一、篡改/过期/吊销 cookie 无效、
  配置缺失与坏 hash fail closed、运行中删用户文件 503、暴力尝试锁定、
  cookie 旗标与负载、no-store、日志纪律、Secure 旗标、锁定恢复）
```

最终 SHA 上全量复跑结果见本文所在提交的交付说明（全绿后推送）。

## 9. 真实 provider 用量与成本纪律

- 本轮真实调用（deepseek-flash + Tavily）：浏览器旅程 2 轮（含 1 次 502 重试与 1 次页面未接住的 200）+ 压力场景 10 条，LLM+搜索合计约 33 次调用，花费约 1.0 元（月累计 5.34/20 元，`/healthz` 可查）；日上限 50 次硬闸两次真实生效（第一批 5 条后主动停止，跨本地午夜重置后再跑第二批，顺带二次现场验证日滚动）
- 其余全部验证走 stub/fixture/mock（0 外网请求）

## 10. 已知限制

1. 登出吊销表在内存（重启失效）+ 多实例不共享——单实例部署语义（与预算准入一致）。
2. 登录锁定按 IP 记忆：NAT 出口后多人共享会互相牵连（第一版接受；无验证码是决定，不是遗漏）。
3. 会话无静默续期：7 天后需重新登录；正在使用时过期的体验 = 下一请求 401 → 诚实送回门口（`?expired=1`）。
4. localStorage 行动回路仍只在本机：换设备/清缓存即断（V0.1 有意不上云，§16）。
5. IAB 环境缺陷使截图级视觉证据与部分合成输入无法在受控浏览器内完成；移动端"拇指体验"的人工判断需 Founder 真机复核一次。
6. 降级 internal（模型宣称交棒却无任务书）时行动文本保留模型原话，可能仍提及外部工具名——桩构造的对抗边界，真实模型待观察。
7. 深夜网关抖动仍会产生 502（诚实失败+可重试），无多路由（明确不做）。
8. Tavily 旧 key 轮换、方舟 key 修复仍待 Founder（非本轮范围）。

## 11. 故意没有做的

- 注册/找回密码/邮箱验证/OAuth/多用户管理后台/头像昵称/角色权限（门就是门）
- 数据库/云同步/历史列表/多设备（§16：没有真实证据前不做）
- CSRF token（SameSite=Lax + JSON content-type + 来源白名单已覆盖 V0.1 威胁面）
- 验证码/Redis/多实例会话共享（单实例 + 内存限流，明确不做）
- 前端框架迁移（vanilla JS 保持；§39）
- 部署 / merge main / DNS / ymai.fun / Nginx / 证书（§59）

## 12. 部署时需要运维提供什么

见 `docs/v2/AUTH_UI_DEPLOY_CHECKLIST.md`（只含运维步骤，未执行）。核心：两个仓库外私有文件（用户文件 + session secret）、env 配置、fail closed 验证、批准 SHA 启动、本机与公网 smoke。

## 13. 状态

```text
READY_FOR_AUTH_UI_PREDEPLOY_REVIEW
```
