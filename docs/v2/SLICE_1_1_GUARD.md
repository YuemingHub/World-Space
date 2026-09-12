# SLICE 1.1 — GUARD BEFORE INTELLIGENCE（护栏修复记录）

> 2026-09-12。Founder 验收 `a4ecbcf` 为 **Scaffold Accepted / Intelligence NOT Accepted**。
> 本轮只修护栏，不接 UI、不部署、不 merge main、不跑 37 条、不调高预算上限。
> 全部验证均在**离线桩 + fixture 搜索**下完成，真实 provider 调用 0 次、0 元。

## 1. 五个 P0 的修法与实测证据

### P0-1 · 证据不能只保护 `resources[]`
`recommended_path` 新增 `evidence_ids`；护栏对**所有会改变行动的字段**做高风险判定
（`recommended_path.summary/why/first_action`、`safe_next_action`、`resources[].claim/why`）。
高风险判断没有有效证据 ⇒ **撤回确定路径**（`recommended_path = null`）、
立即动作降级为不含任何事实断言的通用动作。

实测（桩给出"这种情况直接拨打 110 即可处理，警方会立刻解决"+"本市已列入噪声重点整治名单"）：
```
guard_actions: path_revoked_no_evidence | safe_action_neutralized
recommended_path: null（已撤回）
safe_next_action: 今天先把这件事的三个要素写下来：发生时间、地点或对象、你已经做过什么。
```

### P0-2 · 模型不能自己创造证据 URL（Search Evidence Binding）
流程改为：搜索 → **服务端给结果编号签发 `e1…eN`** → 模型只看到
`{id,title,snippet,published_at}`（**提示词里不给它 URL，也不给它复制来源的机会**）→
模型只能引用 id → 服务端把 id 解析回真实 `source_url/source_title/checked_at`。
引用不存在的 id：该条结论删除并进 `uncertainties`。

实测：
```
resources[0] = { evidence_id: e1, source_url: https://jubao.mee.gov.cn/..., source_type: official_primary, checked_at: 2026-09-12 }   ← id 有效，服务端解析
某投诉代理：引用了本轮不存在的证据 e99，已删除
市噪声整治办：模型自报的来源不作数，已作废
```

### P0-3 · `source_type` 由系统授予（Source Authority Guard）
`server/evidence.mjs`：`Reality Eval 已人工核实的官方入口` → `official_primary`；
`*.gov.cn` / `*.edu.cn` / `*.ac.cn` 域名规则 → `official_primary`；
一小撮权威媒体域名 → `trusted_secondary`；**其余一律 `unverified`**（只降级，不升级）。
模型自报的 `source_url/source_title/source_type` 在护栏里**先删后算**。
`unverified` 且高风险 ⇒ 删除。授权表**绝不写进提示词**，Reality Eval 只做裁判不做答案库。

### P0-4 · 契约必须真的执行
`server/validate.mjs`（手写最小子集：type / required / enum / maxItems / items / properties，
不为一个 schema 引重依赖）+ `contracts/world.schema.json` 收紧：
`resources[].evidence_id`、`recommended_path.evidence_ids`、
资源必填 `name/type/claim/source_type/confidence`。
返回前必须过校验，**不过就 502 `intelligence_contract_failure` + 降级路径，不给"差不多能用"的 200**。

单元实测：3 条问题 → `$.questions: 条数 3 超过上限 2`；缺 `source_type` → 必填违规；
`confidence:"bogus"` → 枚举违规；合规样本 0 违规；只给 `{understanding}` 的残包 → 7 条违规。

### P0-5 · 预算护栏 fail closed
真实 provider 模式下（`fail_closed` 默认 = 非桩）：状态读不出或写不进 ⇒ **不产生任何付费调用**，
返回 `503 budget_guard_unavailable` + 手工降级路径。桩/fixture 模式成本为 0，允许内存兜底以便回归。

实测：
```
状态文件写成非法 JSON → HTTP 503 {"error":"budget_guard_unavailable","reason":"...not valid JSON"}
状态路径是个目录(写不进) → HTTP 503 {"error":"budget_guard_unavailable","reason":"EISDIR..."}
每日上限=3（1 条消耗 2 次 LLM + 1 次搜索 = 3 次）→ 200 429 429 429 429
```

## 2. 三处测量错误（P1）

1. **先记录原始问题数再截断**：`meta.guard_actions` 里出现 `questions_truncated:6->2`（修之前永远看不到超限）。
2. **成本拆开**：`meta.request_cost_rmb`（本次）与 `meta.month_cost_rmb`（月累计）；
   压测器只累加 `request_cost_rmb`。之前 `est_cost_rmb` 混的是累计值，逐条相加会重复计。
3. **调用次数如实**：`llm_calls` / `search_calls` 由请求内计数器产生
   （桩 2+1、不搜索 1+0、compose 未发生不计），不再是写死的数字。
   另外 guard 行为不再都塞进 `dropped_claims`：`meta.guard_actions` 记动作，`meta.dropped_claims` 只记被删的结论。

## 3. 隐私：搜索词最小化

triage → search 之间过 `minimizeQuery()`：手机号 / 18 位证件号 / 8 位以上长号码替换后再进搜索，
提示词第 8 条同时约束。实测：
```
模型给出的搜索意图："李某某 13800001111 小区 噪音 投诉"
实际进入搜索的查询："李某某 [已隐去手机号] 小区 噪音 投诉"
```
（意图原文仍按已拍板的决定发给模型，但页面必须显示那句隐私说明——属于 MISSION 5 的 UI 活，本轮没做。）

## 4. 现在这一层的真实数据流

模块分工（提交 `7230ef0` 起）：`server/world.mjs` 流程与预算（264 行）、
`server/guard.mjs` 护栏（86 行）、`server/evidence.mjs` 证据表与授权（79 行）、
`server/validate.mjs` 契约校验（39 行）。护栏单独成模块，是为了能脱离流程被单独评审。

```
浏览器（持有回路状态） ──POST /api/world {intent, answers[]}──▶
  1. 预算护栏 fail closed（读不到/写不进 → 503；到上限 → 429 + 手工降级）
  2. LLM #1 triage：理解 + 关键缺口 + 是否需要查现实 + 一条搜索意图
  3. minimizeQuery 最小化 → Search（最多一次）→ 服务端签发 e1..eN
  4. LLM #2 compose：只能引用 id
  5. guard：证据绑定 / 授权判定 / 高风险无证据撤回 / 截断留痕 / 中性兜底动作
  6. validate(契约) → 不过则 502，通过才 200
◀── 契约 JSON（含 meta：真实调用次数、本次成本、月累计、护栏动作）
```
无数据库、无会话、无用户系统、无队列、无缓存；日志只有状态码/耗时/计数，**不含用户正文**。

## 5. 还没解决的（诚实清单）

1. **高风险判定靠中文词表**，能被绕过去：本轮就发现"国家噪声重点整治城市"没命中词表
   （幸好它同时没有证据，被 P0-2 的规则拦住了）。词表不是语义判定，**不能当成 P0 的最后一道闸**。
2. **授权域名表是刻意小的**：不在表里的官方站点会被降成 `unverified`，真实 pilot 里可能误伤正确来源。
3. **没有证据的资源一律不进答案**（包括"手机录音"这种不涉外部事实的建议）→ 有**过度保守**风险，
   需要真实 pilot 用 P1「为安全而过度拒答」来量。
4. 桩和 fixture 只证明**护栏会咬人**，完全不证明智能。
5. 真实 LLM/搜索 provider 的响应形状、超时、限流还没碰过（`WS_TIMEOUT_MS` 20s、单次失败即 502）。

## 6. Reality Pilot 12

`eval/pilot12.json`：6 个场景各 2 条、每场景至少 1 条高风险或 trap、含预判最差的
S1-d / S2-d / S3-e / S4-a / S5-e，另含 4 条低风险普通场景（S2-e / S4-c / S5-a / S6-e）防止系统不敢说话。

预算核算：**12 × 最多 3 次 = 36 次 ≤ 每日 50**，未调高任何上限（`WS_DAILY_CAP` 保持默认 50）。
搜索按 12 元/千次口径 ≈ 12×0.012 = **0.144 元**，模型走免费额度 ≈ 0 元。

**状态：`READY_FOR_REAL_PILOT`** —— 缺 LLM Key 与 Search Key（详见 `SLICE1_RUNBOOK.md` §2）。
没有 Key 就不跑：不用爬虫、不用网页抓取顶替、不伪造搜索结果。
