# FAILURE LEDGER — 真实失败账本

> 只记真实失败，不记通过。每条含：输入/输出（artifact 路径）、等级、类型、根因、最小修复、回归、剩余边界。
> 等级定义：P0 错误带入现实 / P1 产品核心失真 / P2 体验摩擦 / P3 视觉细节 / OPS 运维与密钥。

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
