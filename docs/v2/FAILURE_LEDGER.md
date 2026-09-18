# FAILURE LEDGER — 真实失败账本

> 只记真实失败，不记通过。每条含：输入/输出（artifact 路径）、等级、类型、根因、最小修复、回归、剩余边界。
> 等级定义：P0 错误带入现实 / P1 产品核心失真 / P2 体验摩擦 / P3 视觉细节 / OPS 运维与密钥。

> **⚠️ 2026-09-19 证据分级（只加导航，逐条记录一字未改）**：标题里的"真实"指**真调用、真故障**，
> 不是真人参与者——本账本所有 P0/P1/P2 条目都来自 `eval/` 那批拟出意图与本机桩实例，**0 个真人**。
> 文中"真实用户旅程"一处指运维者按用户动线手工走一遍。这些失败**不能**引用为
> `docs/CAPABILITY_REACH_LAB.md` 的 H1 / H2 证据（无论正反方向）。

---

## L1 · 评测数据污染运行时授权（2026-09-12）

- 输入/输出：preflight 审查发现，无单条输入
- 等级：P0（架构性）｜类型：authority failure
- 现实危害：`server/evidence.mjs` 启动时读 `eval/reality_eval.json`，把评测官方入口（含 aistudio.baidu.com、xiaobaozhi.com 等 14 域名）直接授予 `official_primary`——测试数据污染被测系统
- 根因：白名单来源是"评测需要"而非独立成立的理由
- 最小修复：删除该通路；授权只来自可独立解释的域名规则（gov.cn/edu/ac.cn + 5 权威媒体），判不了一律 unverified
- 回归：`eval/authority-selftest.mjs`（含残留检查：原白名单域名现判 unverified）；隔离 Gate
- 剩余边界：官方域名 ≠ 一手 claim（靠人工 claim_source_role_correct 兜底）
- commit：`9e9619b`

## L2 · 域名后缀匹配漏洞（2026-09-12）

- 等级：P0｜类型：authority failure
- 危害：`h.endsWith(t)` 让 evilxinhuanet.com、fakepeople.com.cn、xinhuanet.com.attacker.example 蒙混成权威媒体
- 根因：第三条匹配分支过宽
- 最小修复：只认整段匹配（h===t 或 h 以 '.'+t 结尾）
- 回归：authority-selftest 负控 5 条
- commit：`9e9619b`

## L3 · 全局 12345 兜底（2026-09-12）

- 等级：P1｜类型：world-resource failure（对找工作/旅行/建站等场景误导）
- 根因：把政务场景的正确答案写成了全局常量
- 最小修复：默认兜底改为领域无关文本；具体渠道只能来自本轮证据
- 回归：admission-selftest 边界用例；全文 12345 仅存于高风险词表（检测机制）
- commit：`9e9619b`

## L4 · 医疗高风险词表漏判（2026-09-12，真实搜索试点 S2-d）

- 输入/输出：`eval/out/pilot12-search.md` §S2-d
- 等级：P0｜类型：evidence/authority failure
- 危害：三条 unverified 来源的具体医疗建议（体检 1-2 个月时机、血氧 85% 阈值、肺水肿 12-24h 预警）以 high_risk:false 进入答案——词表（药品/医院/护理）抓不住
- 根因：keyword-only 风险判定追不上生成模型
- 最小修复：F1 admission——claimRisk 三级（冻结词表基座 + 健康域语素×量化断言⇒high_risk、量化⇒important）；high_risk+unverified 删、important+unverified 降级、normal+unverified 放行
- 回归：`eval/admission-selftest.mjs`（S2-d 三类真实样本复放）
- 剩余边界：无量词的裸医疗警告语（"咳粉红色泡沫痰是危险信号"）仍以 normal 过准入，靠人工两字段兜底
- commit：`9194bb1`

## L5 · 路径 backing 不看授权级（2026-09-12，S2-d）

- 等级：P0｜类型：authority failure
- 危害：高风险医疗路径引用 e5/e7（unverified）仅因"id 存在"而存活
- 最小修复：F2——路径 backing 须含非 unverified 证据，否则撤回；important 路径降级标注
- 回归：admission-selftest S2-d 复放
- commit：`9194bb1`

## L6 · 坏 JSON 单点失败（2026-09-12–13，真实率 ~6-20%）

- 输出：S2/S2-e 502（llm_bad_json）
- 等级：P1（可用性）｜类型：runtime failure
- 最小修复：F4——每 LLM 阶段一次 schema-only 重试，逐次计费，meta.llm_retry_count，两次失败 fail closed
- 回归：`eval/retry-selftest.mjs`（坏→好→200 / 坏→坏→502 / 计数如实）
- 真实重放：2026-09-13 两批共救回 3 次，重试率 17-20%
- commit：`9194bb1`

## L7 · UTC 日期（2026-09-13，发布 preflight 发现）

- 等级：P0｜类型：factual failure + runtime failure
- 危害：模型每天 8 小时拿到"昨天"的日期（政策时效题风险）；日额度本地早 8 点才重置
- 根因：`new Date().toISOString()` 取 UTC
- 最小修复：today() 改本地日期
- 回归：发布 smoke（healthz 当日计数正确翻新）
- commit：`5bda2bc`

## L8 · 证据时效缺失（2026-09-13，Pilot replay S5-e）

- 输入/输出：`eval/out/pilot12-replay.md` §S5-e——2019 年卫健委网站媒体转载（延续护理入口）以 official_primary 当现行入口
- 等级：P0｜类型：evidence failure（stale as current）
- 最小修复：高风险资源证据年份（字段/URL 提取）>3 年或未知 → 强制时效标注
- 回归：admission-selftest（2019 标注 / 2025 不标 / 无年份标注）
- 真实重放：S7-e 引 2018 教育部文件被自动标注 ✓
- commit：`5bda2bc`

## L9 · 组合层零资源保守（2026-09-13，Pilot replay S1）

- 输出：8 条证据在手，答案零资源纯自省
- 等级：P1｜类型：world-resource failure（"该给世界却不给"）
- 最小修复：compose 指令补"真正相关的证据应做成 resources（≤3）"——非风险掩盖，是产品主线正向表达
- 真实重放：S7 批次 4/4 搜索条目产出资源
- commit：`5bda2bc`

## L10 · 并发丢计数竞态（2026-09-13，反方攻击发现）

- 等级：P0（部署前）｜类型：runtime/accounting failure
- 危害：真实模式下两条并发请求跨 await 各持过期副本回写，后写覆盖先写，日上限可被突破
- 根因：request 副本跨 await 失效
- 最小修复：countCall 每次磁盘重读再累加
- 回归：retry-selftest 场景 C（延迟网关 4 并发，总账恰好 4）
- commit：`d6ced01`

## L11 · 评测集外死链与链接存活（2026-09-12–13）

- 输出：两条新浪转载一小时内失活（302→文章不存在）；Pilot replay S6 又一条死链
- 等级：P1｜类型：evidence failure（索引有、点开无）
- 最小修复：F3 最小存活保护——候选证据 HEAD 检查（≤6 条、2.5s 超时、404/410 剔除、其余保守保留）
- 回归：`eval/liveness-selftest.mjs`；真实命中：S6 死链被实时剔除 ✓
- commit：`1fcbb92`

## L12 · 火山方舟 key 无效（2026-09-13，OPS）

- 输入：`C:\Users\User\Desktop\key\ark-key.txt.txt`（baseurl + 三模型 deepseek-v4-flash / glm-5.3-flash / doubao-seed-2.0-lite + key）
- 等级：OPS｜类型：credential failure
- 现象：该 key 与 `var/providers.local.json` 中同源副本，对 `ark.cn-beijing.volces.com` 的 /api/plan/v3 与 /api/v3 均 401 "The API key doesn't exist"（8 种 key/端点组合穷举）
- 根因：未知——需 Founder 在方舟控制台核对（key 可能已被重新生成、账号/地域不符、或 plan 端点需额外开通）
- 临时处置：回滚到已验证可用的 rhythm 网关（deepseek-flash），迭代不受阻
- 剩余边界：三模型能力对比未能执行；主模型切换待 key 修复
- commit：本轮

## L13 · 压测器漏传限制烧穿日预算（2026-09-12，OPS）

- 等级：OPS｜类型：test-infra failure
- 危害：全集 37 条误发，撞满 50 次/日，试点只完成 6/12
- 根因：调用漏 `--limit`；runner 无数量安全门
- 最小修复：runner 硬门（--max / pilot 12 上限 / --dry-run），超限发请求前拒绝（PILOT_CASE_LIMIT_EXCEEDED）
- 回归：dry-run 三情形
- commit：`9194bb1`

## L14 · 属性逃逸与危险 scheme 可成点击链接（2026-09-13，GPT Review R1）

- 输入/输出：GPT 独立审核 R1 指出；`eval/xss-boundary-selftest.mjs` 全套对抗样本
- 等级：P0｜类型：frontend security failure
- 危害：`esc()` 按 text→innerHTML 设计不转义引号，`data-copy="${esc(...)}"`、`href="${esc(...)}"` 中一个 `"` 即逃出属性注入 `onerror`/`onfocus` 等新属性；服务端证据表对 `javascript:`/`data:` URL 不设防，可经搜索结果变成可点击链接
- 根因：把文本节点转义默认当成 attribute encoder；"可点击 URL 必须是 http(s)"没有形成不变量
- 最小修复：①渲染纯函数拆到 `web/v2/render.mjs`：esc 同时转义 `& < > " '`（文本/属性两用）；复制文本不进 HTML——渲染只留槽位序号，原文经 dataset（DOM property）赋值，点击读原文，废除手工反转义链；②`httpUrl()` 白名单：只放行 http(s)，其余一律不给 `<a>`（前端最后一道 + 服务端证据表入口同规则双保险，非 http(s) 的"搜索结果"从源头不签发证据 id）；③新增 xss 桩用例供回归与浏览器旅程
- 回归：`eval/xss-boundary-selftest.mjs`（`"`、`"><img src=x onerror=…>`、`" autofocus onfocus=…`、`javascript:`、`data:text/html`、含 `& < > ' "` 的正常中文动作；标签/属性白名单审计 + href 全 http(s) + 复制原文往返 + 全链路 HTTP）；真实 DOM：xss 桩旅程零脚本执行、零注入标签、零事件属性、零链接
- 剩余边界：富文本场景不存在（全部纯文本渲染）；若未来引入 markdown/HTML 内容需另立消毒层
- commit：本轮

## L15 · 日/月上限可被临界并发穿透（2026-09-13，GPT Review R2）

- 输入/输出：GPT 独立审核 R2 指出；`eval/budget-cap-selftest.mjs` D1/D2
- 等级：P0（部署前）｜类型：runtime/accounting failure
- 危害：已证明的"4 并发 → 账本 4"只说明计数准确，不说明上限硬。账本 49/50 时 4 条并发各自通过"事后"检查再调用，付费调用可达 53 次；月预算同理
- 根因：countCall 是"调完记账"，检查与调用之间存在并发窗口；准入语义缺失
- 最小修复：预留式准入 admit/settle——检查+预占+落盘是同步一段代码（无 await，事件循环保证原子），调用前先占名额与最坏成本（LLM 按 max_tokens+1 万输入 token 估算，搜索按次实价）；返回后按实际用量多退少补，provider 失败全额退预留；被拒请求 429 budget_exceeded（daily_calls/monthly_budget）带人工降级
- 回归：budget-cap-selftest D1（49/50 六并发：恰好 1 条 200、5 条 429、网关只收到 1 个请求、账本=50）+ D2（月预算临界四并发：1 条 200、3 条 monthly_budget、结算后 ≤ 上限）；retry-selftest C（4 并发计数不丢）与 runtime-selftest 16 路并发（48 次总账）不回归
- 剩余边界：单实例语义（多进程部署需共享锁/集中配额，当前架构明确不做）；实际用量超出预留估算的极端情况由 max_tokens 与输入上限兜住
- commit：本轮

## L16 · 仓库里有两个"今天"（2026-09-13，GPT Review R3）

- 输入/输出：GPT 独立审核 R3 指出；`eval/date-selftest.mjs`
- 等级：P0｜类型：factual failure + runtime failure
- 危害：L7 修了运行时预算的 UTC 日期，但 `server/guard.mjs` 的 checked_at 仍用 `toISOString().slice(0,10)`——同一份资源卡片上"核实于"与预算日切分叉；上海时区 00:30–08:00 之间证据核实日期是"昨天"
- 根因：修 L7 时只改了 world.mjs 一处，日期逻辑没有单一真源
- 最小修复：新建 `server/date.mjs`（localDate/localMonth）为唯一业务日期真源，world.mjs 与 guard.mjs 一律从它取；业务日界 = 主机时区日界，单一语义
- 回归：date-selftest（TZ=Asia/Shanghai 注入 00:30/07:59:59/08:00:01/23:59:59 四个边界时刻，业务日期均为当天，UTC 负控证明非恒等断言；TZ=UTC 主机语义一致；guard checked_at 与 localDate 同源；server/** 静态残留=0）
- 剩余边界：部署在非目标用户时区的主机时，"今天"跟主机走（部署约定，不是代码问题）
- commit：本轮

## L17 · 反代后面全员同 IP，限流形同虚设（2026-09-13，GPT Review R4）

- 输入/输出：GPT 独立审核 R4 指出；`eval/runtime-selftest.mjs` 实例 3/4
- 等级：P1（pre-deploy）｜类型：runtime/abuse failure
- 危害：limiter 只读 `req.socket.remoteAddress`——Nginx → Node 部署后所有访问者都是 127.0.0.1，共享一个桶，一个重度用户可对所有人触发 429；反过来若无条件信任 X-Forwarded-For，任何客户端换个假头就能绕开限流
- 根因：限流键没有代理边界语义
- 最小修复：默认只认 socket 对端地址（互联网客户端伪造的 XFF 完全不起作用）；显式 `WS_TRUST_PROXY=1` 且对端在受信代理名单（默认 127.0.0.1/::1）时才读 X-Forwarded-For，取最右一个合法 IP（受信代理把"它看见的地址"追加在最右，客户端伪造头被顶掉）；无/坏 XFF 回落对端地址；只支持单层受信代理；Node 继续默认只监听 loopback
- 回归：runtime-selftest 实例 3（未开信任：每条换伪造 XFF 仍同桶，第 4 条起 429）+ 实例 4（开信任：同 XFF 第 4 条 429、不同 XFF 独立桶、无/坏 XFF 回落对端桶；healthz 如实报告 trusted_proxy）
- 剩余边界：多级代理链（CDN→Nginx→Node）需按真实拓扑配置 trustedProxies，当前只声明单层
- commit：本轮

## L18 · 行动回路"刷新就断"：持久化函数定义了却没接线（2026-09-14，Outcome Loop MVP）

- 输入/输出：受控浏览器真实旅程（"我想在小区里组织一个周末羽毛球局"）；刷新页面后回路丢失
- 等级：P1｜类型：product loop failure（回归发现了它，不是它先报错）
- 危害：承诺"接着上次继续"的能力实际不存在——`saveLoop/loadLoop` 都写了、启动时也读了，但 `render()` 里从没调用 `saveLoop`；用户刷新一次就回到空白首页，之前那句意图和上一份契约全丢
- 根因：只测了"代码里有 localStorage 字样"（e2e 门查的是字符串包含），没有断言"渲染路径真的写入"——接线缺失这类错误在字符串检查下不可见
- 最小修复：`render()` 非恢复分支调用 `saveLoop(lastIntent, j)`；e2e 门加"调用点与定义同时存在"断言（`function saveLoop(` 与 `saveLoop(lastIntent, j)`）
- 回归：浏览器真实旅程两个场景复核——① 旅程后 `ws.loop.v1` 含意图与主行动文本；② 新文档加载 → 恢复横幅 + 上一份结果 + 主行动 + "换个新目标"按钮；`eval/frontend-e2e.mjs` 新增接线断言
- 剩余边界：受控浏览器 guest 对 `127.0.0.1` 源禁用 localStorage（SecurityError，主世界与隔离世界均如此），持久化只能在 `localhost` 源端到端验证；真实浏览器（Founder）待复核一次
- commit：本轮

## L19 · 真实模型六次探测都没选 handoff（2026-09-14，Outcome Loop MVP，观察项）

- 输入/输出：T1（AI 工作）、T3（拳馆）、T4（路灯）、T5（AI 工作+失败回执）、T6（自我盘点）、T7（押金谈判准备）六次真实运行
- 等级：观察项（不是失败）｜类型：model selection boundary
- 现象：六次全部合理选择了 human（打电话/扫市场/现场记录）或 internal（本页完成的结构化动作），一次 handoff 都没有自然触发。T7 的"押金谈判准备"连开场白都直接产出了——本页模型自己就是外部模型，"借脑子"已经在发生
- 判断：这与产品定位一致——handoff 留给"用户要离开页面持续使用外部工具"的开放生成/对话型步骤，而不是把能一页做完的事推出去。交棒契约（任务书必填、空手交棒降级）、前端复制/白名单跳转、离线差分门都已覆盖；"外部 AI 的结果带回来"这条回路由 T1 真实走通（回执文本就是 DeepSeek 给的三个方向）
- 后续观察：真实用户旅程里若出现"用户自己在外部 AI 干完活回来"（T1 即此类），系统已能正确接住；产品主动派发 handoff 的时机需要真实用户证据再调，不靠改提示词硬造
- commit：本轮

## L20 · 深夜网关抖动：真实运行下的诚实失败与两次现场验证（2026-09-14）

- 输入/输出：北京时间 00:00-00:10 三次 POST 502（`llm_http_504`，网关 504）；同一时段本地午夜边界预算滚动与跨日 `checked_at` 现场发生
- 等级：外部依赖（非产品缺陷）｜类型：dependency flakiness
- 现象与产品行为：网关在深夜维护窗口连续 504 → 商品返回 502，页面如实显示"这一轮没有得出可靠结果（服务或网络波动）…别按不完整的答案行动"并提供"再试一次"；两次重试后成功，旅程照常完成
- 现场验证（R3 修复的真实边界）：跨过本地午夜后，预算日计数正确从 158 滚到新的一天（月成本继续累计不清零）；资源卡片的"核实于"从 2026-09-13 变成 2026-09-14，与业务日同源——两处日期在真实午夜边界上未分叉
- 剩余边界：网关可用性不由本仓库控制；真实部署需要上游有重试/多路由（当前明确不做）
- commit：本轮

## L21 · 离线门悄悄连到了真实服务：端口占用被静默掩盖（2026-09-14，Outcome Loop MVP）

- 输入/输出：全量 Gate 复跑时 `retry-selftest` A 场景失败，meta 里出现 `model: deepseek-flash` 与真实计费成本
- 等级：P1（测试设施）｜类型：test integrity failure
- 危害：该测试硬编码 worldPort=8890（与真实本机服务同端口）。真实服务在跑时，子进程绑定失败被 `stdio: 'ignore'` 掩盖，`worldUp()` 轮询到的其实是**别人的服务**——"0 外网请求的离线 mock 门"变成了真实 provider 调用，且结论不可信（这次是恰好失败才暴露；若真实服务恰好返回相似结构，门会假绿）
- 根因：测试端口与他人/生产本机运行共用；启动探测只检查 `/healthz` 是否 200，不校验服务身份
- 最小修复：三个场景换到专用端口 8910/8912/8914；`worldUp()` 增加身份校验——healthz 的 `model` 必须是 `mock`，否则立即失败并说明"端口上是别的服务"，杜绝静默串台
- 回归：真实服务仍占用 8890 的条件下 `retry-selftest` 全绿（修复在原始冲突条件下验证）；其余 11 项门全绿
- 剩余边界：其他门（xss 8889 / outcome-loop 8895-8905 / frontend-e2e 8875）目前端口独立，未做统一端口黑板；扩大并行压测时需统一约定
- commit：本轮

## L22 · 访问门自测的预算 fixture 跨运行累计：累计到日上限后门假红（2026-09-14，Access Gate）

- 输入/输出：`auth-selftest` 第 4 次运行时"已登录 POST /api/world → 正常契约"失败，HTTP 429 `budget_exceeded`；`var/auth-8951.json` 显示 `calls: 50`
- 等级：P2（测试设施）｜类型：test fixture debt
- 危害：与 L21 相反方向的失真——不是假绿而是**假红**。stub 桩每轮消耗 2 次计数（triage+compose），自测没有清理状态文件，四次运行累计正好撞上默认日上限 50；访问门逻辑本身没有任何问题
- 根因：新写的自测漏了其他门都有的"spawn 前清 fixture"步骤；日上限用的是产品默认值 50 而不是测试值
- 最小修复：`start()` 里 `rmSync` 掉各实例的预算文件；显式 `WS_DAILY_CAP: '500'`（本门测的是门，不是预算——预算有专门的并发门）
- 回归：清理后连续两次运行全绿
- 剩余边界：各门各自管理自己的 fixture 生命周期，没有统一的"门启动前清理"约定；门数量再增时值得抽公共 helper
- commit：本轮

## L23 · 访问门攻击面全量探针：统一口径与 fail closed 在对抗下成立（2026-09-14，Access Gate，通过记录）

- 输入/输出：一次性实例（stub + 测试用户文件）17 类探针，全部落 `var/gate-auth.log` 与会话记录
- 等级：通过记录（非失败）｜类型：security regression
- 覆盖：XSS 载荷当用户名（401 统一口径、响应零反射）；超长用户名/密码（400）；坏 JSON/数组体（400）；五种垃圾 cookie 形态与伪造签名 token（一律 401）；静态路径穿越编码/明文（404 无文件泄露）；GET login / PUT world（404）；大小写变体用户名与不存在账号响应逐字节一致（无枚举信号）；无 cookie logout（200 幂等不 500）
- 剩余边界：登录锁定按 IP 记忆（NAT 后多人共用出口会互相牵连，第一版接受）；无验证码（明确不做）
- commit：本轮

## L24 · 冒烟判定器条件反了：真失败被记成 ✓（2026-09-15，V0.1 发布前收口，P1 测试设施）

- 输入/输出：`smoke-formal.sh` 首轮 `PASS=12 FAIL=12`；其中 7 个 ✗ 是假的（`auth=ready`、Cookie 三旗标、`/api/auth/me` 认到 u-owner、`no-store`、302 到 /login 全部实测正确），而**第一轮 HTTP 502 被记成 ✓**
- 等级：P1（测试设施）｜类型：false green
- 根因：`ck <名> <1=通过>` 与 shell 的"0=成功"两套约定混用，`ck "x" $?` 把成功当失败、把失败当成功
- 危害：报告只会带走绿色的那部分——假绿会直接变成 Founder 眼里的"已验证"，比假红危险一个量级
- 最小修复：拆成 `ck`（1=通过）与 `ckz`（吃命令退出码）两个入口，凡 `$?` 处一律 `ckz`；
  并在脚本开头**自检判定器本身**（真通过须记 ✓、真失败须记 ✗、退出码非 0 绝不可记 ✓），
  三项不符整轮作废 `exit 9`；自测计数不计入汇总
- 回归：修后同轮 `PASS=22 FAIL=4`，剩下的红字全是真障碍（3 条搜索 key + 1 条 L26）
- 剩余边界：判定器自检只能防"条件反了"，防不了"断言写得太松"；断言是否真的能失败，仍要靠偶尔故意喂坏数据验证

## L25 · 服务器在用的 Tavily key 实测 401：公网搜索早就坏着（2026-09-15，V0.1 发布前收口）

- 输入/输出：本机实例第三次尝试终于穿过模型网关的 429，返回
  `{"error":"intelligence_unavailable","code":"search_http_401"}`；此后每轮稳定 401
- 等级：P1（配置漂移）｜类型：secret/配置失效
- 关键推论：本机验证实例的 `WS_SEARCH_KEY` 是从**共享生产 env 原样继承**的，
  因此公网 `85c7b91` 现在每一次真实请求的搜索阶段都拿 401 → **线上搜索已经是坏的**，
  不是本轮引入的问题（`/healthz` 只看"配没配"，永远看不出这把 key 已被拒）
- 与旧账的关系：09-14 那条"旧 Tavily key 只有口头确认，agent 无法独立验证"到此有了物证——
  env 里这把已不可用；但"哪一把是当年暴露的那一把"仍需 Founder 在控制台按显示名核对
- 最小修复：把新 key 写入服务器仓库外私有 env（600），**改文件不重启服务**——
  运行中的进程仍用内存里的旧环境，公网行为不变；切流那次重启才生效
- 回归：`SEARCH_SMOKE` 必须在装好新 key 后那一轮里真的拿到 `meta.search_calls>0` 才算过
- 剩余边界：`/healthz` 的 `search_configured` 只表示"环境变量非空"，不表示"这把 key 还活着"；
  值得在未来某个版本让它做一次轻量校验（本轮不做，属产品改动）

## L26 · B 会话令牌被贪婪 sed 提错：一条假红带出一条假绿（2026-09-15，V0.1 发布前收口）

- 输入/输出：`B 的身份: {"error":"auth_required"}` → "B 认到 u-guest" 假红；
  紧挨着的"A 与 B 是两个不同令牌"却**假绿**
- 根因：`sed 's/.*=\([^;]*\);/\1/'` 的 `.*=` 贪婪匹配到整行最后一个等号，而 Set-Cookie 行里有
  `Max-Age=604800` → 取到的"令牌"其实是 `604800`
- 教训：同一个 bug 一次造出一红一绿，绿色那条最骗人；提取头字段必须用**非贪婪、按 name=value 成对**的表达式（与 A 侧统一）
- 最小修复：A/B 用同一个提取式；令牌为空时显式打一行提示而不是静默往下走
- 回归：待装新 key 后那一轮完整复跑（B 隔离、真实两回路、搜索 smoke 一起收）

## L27 · 把"标签: key"整行当令牌发出去：可用 key 被判成废的（2026-09-15，V0.1 发布前收口）

- 输入/输出：桌面 `ws-key.txt` 第一遍逐行直连 Tavily，两行都回
  `401 Unauthorized: missing or invalid API key`；我因此几乎写下"Founder 存的 key 不能用"
- 等级：P2（我自己的探针写法）｜类型：false red / 输入形状未先验
- 根因：文件行格式是「Tavily API Key: tvly-…」，我把**整行**（含中文标签和冒号）当 Bearer 发出去；
  而更早一次还把三行 `tr -d '\r\n'` 拼成一坨，等于发了个必然无效的串
- 修复：先用 `grep -oE "tvly-[A-Za-z0-9_-]{20,}"` 抽出 token 再发；并给每把打印 sha256 前 12 位
  做身份区分（明文不进输出）
- 结果：抽 token 重测 → 两把都 `HTTP 200` 且各返回 1 条真实结果。**她的 key 是好的，错的是我的探针**
- 教训（与 L24 同族）：外部东西"失败"的第一解释应该是"我送出去的形状对不对"，
  尤其是凭据类——误判会让 Founder 去做一次完全没必要的重建，还会让她怀疑自己的操作
- commit：本轮

## L28 · 空洞通过：第一轮失败时，"第二轮没重答第一轮"照样得绿（2026-09-16，V0.1 切流）

- 输入/输出：新候选树那一轮 `PASS=24 FAIL=2`，两条红都是第一轮撞上游限流（`next_action` 为空）；
  但紧挨着的"✓ 第二轮 receipt_ingested=true 且行动真的改变"**是绿的**——
  它实际比较的是 `""` 与第二轮那段真行动，必然"不同"
- 等级：P1（测试设施）｜类型：vacuous pass（假绿的第三种形态）
- 根因：断言只写了"两轮文本不同"，没写"两轮都得是真实行动"。前提不成立时，结论自动成立
- 与 L24 的区别：L24 是条件反了（机械错误），这条是**断言写得太松**（语义错误）——
  判定器自检防不了它，因为尺子本身没坏，是刻度画错了
- 最小修复：判定改成 `!!t1 && !!t2 && t1!==t2`，并把两轮行动长度一起打进证据行，
  空串出现时当场可见；`--rejudge` 路径本就有"两轮都得有 next_action"这道闸，此处对齐
- 回归：公网那一轮（两轮都真 200、长度 55 / 75）在同一判定下得绿，属实质通过
- 剩余边界：断言能否失败，只能靠偶尔**故意喂坏数据**来验证；本轮已经开始留这种记录
- commit：本轮

## L29 · 错误信息把"我根本没试"说成"试了不对"（2026-09-16，改登录口令）

- 输入/输出：`set-password.sh` 报 `FAIL: 1 种读法没有一个能登录，已原样退回旧口令`，
  但屏幕上**连一行"候选 1：指纹…"都没有**——循环体其实一次都没执行
- 根因：`while IFS= read -r cand` 在最后一行**没有换行符**时不会进入循环体，
  而我生成候选列表用的是 `out.join("\n")`（无尾换行）；于是"恰好只有 1 个候选"这种
  最常见的情况被整体吞掉。之前那次 3 候选能跑，是因为前 2 行有换行、只有最后一行被丢
- 危害：错误信息把原因指向了 Founder 的口令文件（"请确认文件里就是你要设的口令"），
  而真实原因在我自己的读取写法上——她会照着去改文件，白折腾一轮
- 最小修复：两处一起加固——生成时 `join("\n") + "\n"`；读取用 `while ... || [ -n "$cand" ]`
- 通用教训：**失败信息必须能区分"没执行"和"执行了但不通过"**；做不到区分的报错，
  就是把排查成本转嫁给不懂技术的那个人
- 回归：修后同一条命令 → 候选 1 指纹可见、真实登录 200、口令生效
- commit：本轮
