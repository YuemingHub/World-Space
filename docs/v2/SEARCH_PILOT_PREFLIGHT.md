# SEARCH PILOT PREFLIGHT — 让第一次真实搜索成为干净实验

> 2026-09-12。本轮不接 UI、不部署、不跑真实搜索、不跑 Pilot 12、不填 Key。
> 唯一目标：把"评测数据污染被测系统"和几处会扭曲实验的漏洞修掉，
> 让真实 Search Pilot 面对的是一个**没有见过答案的 World Space**。

## 1. P0-1 · 彻底断开 Eval → Runtime

**删除的泄漏**：`server/evidence.mjs` 曾在启动时读取 `eval/reality_eval.json`，把其中
`official_entry` 的 14 个域名装进运行时 `VERIFIED_HOSTS`，直接授予 `official_primary`。
这些域名（含 `aistudio.baidu.com`、`xiaobaozhi.com`、`zsxq.com`、`www.12306.cn` 等）
进入生产授权的唯一理由是"评测需要它"——测试数据污染被测系统，即使没进提示词也不允许。

现在运行时不读任何评测或文档数据。评测集只剩一个身份：**裁判**。

## 2. Production Authority 现在如何产生

只保留**稳定、可独立解释的域名规则**：

| 规则 | 判定 |
|---|---|
| `*.gov.cn`（及 `gov.cn` 本身） | `official_primary` |
| `*.edu.cn` / `*.ac.cn` | `official_primary` |
| 五个权威媒体域名（people/xinhuanet/cinet/cnr/thepaper） | `trusted_secondary` |
| 其余一切，包括判断不了的 | `unverified` |

- 不建"互联网权威数据库"。`config/source_authority.json` 机制已定义但**本轮不创建**：
  将来确有需要才建，每项必须含 `host/authority/why/checked_at`，理由必须独立成立，
  "评测里需要这个网站"不是理由。
- `unverified` 完全合法：宁可少授予。原评测白名单里不受域名规则保护的域名
  （如 `zscx.osta.org.cn`）现在一律 unverified，等真实 pilot 看它是否够格再议。
- 已知边界，如实记录：官方域名 ≠ 页面里每个 claim 都是一手来源。这一层区别
  本轮靠人工审查暴露（见 §6），不开发 Claim Authority Engine。

## 3. P0-3 · 域名后缀漏洞

`trusted_secondary` 匹配原为 `h === t || h.endsWith('.' + t) || h.endsWith(t)`，
第三项让"假亲戚"域名蒙混过关。已删，只认整段匹配。

**负控（全部 `unverified`）**：`evilxinhuanet.com`、`fakepeople.com.cn`、
`not-thepaper.cn`、`xinhuanet.com.attacker.example`、`fakegov.cn`
**正控**：`xinhuanet.com` / `www.xinhuanet.com` / `people.com.cn` / `www.people.com.cn`
/ `www.thepaper.cn` → `trusted_secondary`；`gov.cn` / `www.gov.cn` / `jubao.mee.gov.cn`
/ `www.tsinghua.edu.cn` → `official_primary`
**残留检查**：原评测白名单域名 `zscx.osta.org.cn`、`www.12306.cn` → `unverified`
（证明旧通路已拆干净，不是给 pilot 种答案）。

以上固化为 `eval/authority-selftest.mjs`，违规即红。

## 4. P0-4 · 全局 12345 fallback 已删

`guard.mjs` 的默认 `fallback_if_refused` 与 `world.mjs` 429 预算兜底里预设的
"打 12345 问归口"已删除。12345 只适配政务/投诉类意图，对找工作、旅行、建站、
内容变现、普通学习是误导。默认兜底改为领域无关文本（guard 与 429 各一处）：

> 如果你不愿把内容交给 AI：把这件事改写成几个关键词，优先查对应的官方机构、实际服务提供方或真实平台；仍无法判断时，再找这个领域的人工客服、专业人员或现实中的人确认。

某个具体场景该用 12345，只能来自**本轮理解 + 本轮 Search/Evidence**（作为带证据的
资源出现），不得来自全局常量。`evidence.mjs` 高风险词表保留 `12345/110/12369/…`：
那是"热线类断言必须有证据"的**检测机制**，不是答案来源；桩场景数据里的 12345 也已清掉。
现在 `server/**` 里 12345 仅存在于高风险词表一处。

## 5. P0-5 / P0-6 · 搜索适配层收敛与权力分离

Tavily 最终请求形状（`eval/adapter-shape-selftest.mjs` 断言）：

- 认证只走 `Authorization: Bearer <key>`；**请求体不再携带 `api_key`**；
- body 只含 `{query, max_results: 8, search_depth: 'basic', include_answer: false, include_raw_content: false}`；
- `include_answer: false` / `include_raw_content: false` 保持——Tavily 只承担
  `query → candidate results`，禁止它的 answer 变成 World Space 的答案；
- key 只进 `var/.env.local`（已 gitignored）；错误信息只带状态码；日志只有计数。

权力分离不变：Search Provider 找网页 → 自有证据层签 `e1..eN` → Authority Guard
判"这是谁的网站" → 模型只能引用 id。**搜索商说 authoritative 不算数。**

## 6. Authority 本轮只回答"网站是谁"

`domain_authority_correct` 与 `claim_source_role_correct` 已写入
`SLICE1_RUNBOOK.md` §3.5 的人工审查清单，作为真实 Search Pilot 的两个独立字段：

- `domain_authority_correct`：系统有没有认对"这是谁的网站"；
- `claim_source_role_correct`：这个具体网页是否真有资格支撑这个具体 claim
  （政府网站转载新华社文章：domain=government 不自动等于一手政府结论）。

先靠 pilot 暴露问题，不提前施工。

## 7. 离线 Gate 结果（全绿）

| Gate | 结果 |
|---|---|
| `eval/runtime-isolation-selftest.mjs` | server/config/web → 评测数据引用数 **0**（该 Gate 首跑曾抓到 world.mjs 注释里的文档路径，已清） |
| `eval/authority-selftest.mjs` | 负控 5 ✓ 正控媒体 5 ✓ 正控政府/教育 4 ✓ 残留 2 ✓ 非法输入 ✓ 词表机制 ✓ |
| `eval/adapter-shape-selftest.mjs` | 三 provider 形状 ✓ Bearer-only ✓ body 无 key ✓ answer 关闭 ✓ 错误无 key ✓ |
| 护栏回归（桩 bad + fixture 搜索） | 问题截断 6→2 ✓ 模型自报来源作废 ✓ 不存在证据 e99 拒绝 ✓ 高风险无证据路径撤回 ✓ 110 动作保留并标注 ✓ 新兜底文本生效 ✓ |
| 证据绑定回归（桩 ok + fixture 搜索） | e1 → 解析回 `jubao.mee.gov.cn`（靠域名规则而非白名单）✓ 路径/资源保留 ✓ 护栏零动作 ✓ 契约校验通过 ✓ |
| 契约负向 | 残包 7 违规 ✓ confidence 枚举 ✓ questions 超限 ✓ |
| 预算 fail closed | 非法 JSON → 503 ✓ 目录 → 503 ✓ 日上限 3 → 200/429/429/429 ✓ |

全部 0 元、0 外网请求、0 真实 provider 调用。

## 8. 保留不回退

Evidence Binding（模型只见 id、自造 URL/无效 id 一律拒）、`safe_next_action`
语义（事实 claim 需证据，动作本身不天然需要）、预算 `50 次/天`、`20 元/月` 不变、
真实 provider 下状态不可读写即 fail closed。

## 9. PRE-DEPLOY BLOCKERS（只登记，本轮不施工）

见 `docs/v2/PRE_DEPLOY_BLOCKERS.md`：A. `usage` 为 process 级可变状态（并发前必须
request-local）；B. CORS `*`（公网前必须重做 origin 限制 / 滥用防护 / 暴露方式）。

## 10. 状态

**READY_FOR_TAVILY_KEY** —— 本轮到此为止。下一轮由 Founder 决定真实 Search smoke
（顺序见 `SLICE1_RUNBOOK.md` §3.5，先 smoke 后人工核对再 Pilot 12，顺序不可跳过）。
