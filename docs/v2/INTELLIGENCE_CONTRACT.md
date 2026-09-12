# INTELLIGENCE CONTRACT — V2 智能层输出契约（MISSION 2）

> 先定契约，再定 UI。机器可读版本：`contracts/world.schema.json`。
> 服务端实现：`server/world.mjs`。最后更新：2026-09-12。

## 1. 这个契约解决什么

Prototype 0 的失败是"看起来理解了"：输入原样回显，资源是写死的。
契约的作用是把"真的走完了认知链"变成**可检查的结构**——尤其是让"我不知道"成为合法输出。

## 2. 输出结构

| 字段 | 含义 | 硬性要求 |
|---|---|---|
| `understanding` | 用大白话说出这个人真正要做成什么（不是复述原话） | 必填 |
| `needs_clarification` | 是否还缺会改变行动的关键事实 | 必填 |
| `questions[]` | `ask` + `why`（为什么这个答案会改变下一步） | **最多 2 条**；超出由服务端截断 |
| `safe_next_action` | 安全、低成本、不会误导的立即动作 | 可为 null；与追问**可同时存在** |
| `recommended_path` | `summary` / `why` / `first_action` | **可为 null——这是合法成功输出** |
| `resources[]` | 世界里的资源（见 §3） | 最多 3 条，先给默认那一个 |
| `uncertainties[]` | 查不到、不确定、要用户自己确认的 | 必填数组（可为空） |
| `reality_feedback_prompt` | 去做之后该带回来的那个问题 | 必填（闭环最后一拍） |
| `fallback_if_refused` | 用户不愿把内容交给 AI 时的手工路径 | 必须存在 |
| `meta` | `searched` / `search_skipped_reason` / `dropped_claims` / `llm_calls` / `search_calls` / `est_cost_rmb` | 服务端填，用于成本与诚实展示 |

## 3. 资源即证据（Evidence Discipline）

每条资源必须带：`claim`、`source_url`、`source_title`、`source_type`、`confidence`，
可取得时带 `checked_at` / `published_at`；服务端自动打 `high_risk` 标记。

`source_type`：`official_primary` / `trusted_secondary` / `third_party` / `unverified`。

**资源类型 ≠ 软件**：`government` `institution` `company` `service` `place` `person` `community`
`document` `dataset` `open_source` `software` `ai_tool` `product` `other`。
压测里如果三条资源全是 `ai_tool`/`software`，直接记 P1（`Resource ≠ AI Tool` 未通过）。

## 4. 服务端强制的三条纪律

1. **高风险缺来源 → 删除该结论**，并把删除理由写入 `meta.dropped_claims` 与 `uncertainties`（不静默）。
   高风险判定：文本命中 `法/条例/政策/规定/医保/保险/报销/补贴/资格/证书/职业标准/备案/许可/价格/收费/部门/热线/医院/护理/药品/名单/官方/定点` 等词。
   高风险 + `third_party`/`unverified`/无 URL ⇒ 删除。
2. **问题超过 2 条 → 截断**，并记一条 `dropped_claims`（防问卷化）。
3. **既不追问、又不给动作 → 判为失败输出**，`uncertainties` 里明说"这一轮是失败输出，请走人工搜索"。

搜索侧另有一条：**搜索结果只是候选证据**。有 URL 不等于可信，域名可信不等于内容可信。

## 5. 什么不算失败

- `recommended_path = null` + `uncertainties` 里有原因 → **合法成功**；
- `resources` 为空但 `safe_next_action` 给了 → 合法（有些意图第一步就是"记录/打电话问"）；
- `needs_clarification = true` 且同时给了 `safe_next_action` → 这是期望形态，不是犹豫。

## 6. 什么算 P0（任一即整条不通过）

编造不存在的资源 / 已失效政策当现行 / 没有来源却给确定事实 / 关键事实不足却自行补全 / 高风险场景误指路。
其中"疑似编造官方来源"由压测器自动判：`source_type=official_primary` 的域名不在
`eval/reality_eval.json` 已核实入口集合与白名单内 → 直接 P0 待人工确认。
