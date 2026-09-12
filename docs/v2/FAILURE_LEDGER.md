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
