# PRODUCT.md — World Space 产品契约

> 本文件是 World Space 的唯一产品定义。
> 最后更新：2026-09-06

---

## 1. WHY

一个普通人脑子里有一个想法，但这个想法永远停留在脑子里。

不是因为想法不好，而是因为从"想法"到"现实"之间有太多看不见的步骤。普通人不知道下一步该做什么，不知道什么工具能帮自己，不知道做出来的东西算不算"完成"。

World Space 存在的理由：**把"想法→现实"这条路径变成可见的、可走的、可完成的。**

---

## 2. WHO

一个普通人。

- 不是开发者
- 不是创业者
- 不是技术爱好者
- 是一个有真实想法、但不知道怎么把它做出来的人

可能是一个想给孩子做一本绘本的家长，一个想把经验整理成小书的退休者，一个想解决自己工作中某个小问题的人。

---

## 3. CORE JOB

**帮助一个普通人把一个真实想法带进现实。**

不是"教他学 AI"。
不是"给他推荐工具"。
不是"替他把事情做完"。

是陪他走完从想法到现实的全过程，让他知道：
- 我想要什么结果
- 我现在在哪一步
- 下一步做什么
- 用什么来做
- 做出来的东西放哪
- 这件事到底完成了没有

---

## 4. NON-GOALS

World Space **不是**：

- AI 工具导航站
- 教程网站
- Agent Marketplace
- 通用自动化平台
- 社区 / 社交平台
- workflow builder
- enterprise 产品
- credits / token 经济系统
- plugin marketplace
- complex multi-agent orchestration

这些方向无论看起来多有吸引力，在 V0.1 阶段一律不做。

---

## 5. CORE LOOP

```
真实意图
  → 定义现实结果
  → 建立 Project
  → 找到下一步
  → 使用合适 AI / Agent / Tool
  → 产生 Artifact
  → 在现实中执行
  → Evidence 确认结果
  → 继续迭代
```

这个闭环是 World Space 的核心。所有功能设计必须服务于这个闭环。

---

## 6. PROJECT MODEL

一个 Reality Project 的最小模型：

| 字段 | 说明 |
|---|---|
| `intent` | 用户的真实意图（一句话：你想让什么事情发生？） |
| `desired_outcome` | 期望的现实结果（做完了现实里会多出什么东西？） |
| `definition_of_done` | 什么算完成（可验证的完成标准） |
| `current_state` | 当前状态（草稿 / 进行中 / 已完成 / 已放弃） |
| `next_action` | 下一步做什么（一个具体的、可执行的动作） |
| `artifacts` | 产出的 Artifact 列表 |
| `actions` | 已执行的现实行动列表 |
| `tools_used` | 使用过的 AI / Agent / Tool 记录 |
| `evidence` | 现实证据（证明结果确实出现了） |
| `reflection` | 回顾与反思 |

---

## 7. ARTIFACT MODEL

Artifact 是 AI 协助产出的东西。它不是最终结果，是过程中的产物。

**关键区分：AI output != reality completion**

| 阶段 | 含义 | 例子 |
|---|---|---|
| AI 生成 | AI 产出了内容 | AI 写了一篇文案草稿 |
| Artifact 已形成 | 内容被整理为可用的 Artifact | 文案被保存为文档，有文件、有格式 |
| Action 已执行 | 人在现实中做了事 | 把文案发到了公众号上 |
| Reality Evidence 已出现 | 现实中出现了可验证的结果 | 公众号文章可以打开阅读 |

World Space 必须追踪这四个阶段的区分。一个 Project 的"完成"不是 AI 生成了内容，而是 Reality Evidence 已出现。

---

## 8. REALITY EVIDENCE

Reality Evidence 是证明"这件事在现实中真的发生了"的东西。

- 不是"AI 说完成了"
- 不是"我觉得做完了"
- 是可以在现实中被验证的证据

例子：
- 做一个网站 → 网站有一个可以访问的 URL
- 做一本小书 → 小书有一个可以阅读的文件（PDF / EPUB）
- 做一个小工具 → 工具有一个可以运行的入口

没有 Reality Evidence 的 Project 不能标记为"已完成"。

---

## 9. HUMAN AUTHORITY

人是决策者。

- 人定义意图和完成标准
- 人决定下一步做什么
- 人选择是否使用 AI 的建议
- 人执行现实中的行动
- 人确认结果是否达成

AI 可以建议、可以生成、可以辅助，但**不替人做决定**。

---

## 10. MODEL / AGENT AUTHORITY

AI 的角色是辅助，不是替代。

- AI 可以帮助把模糊意图转化为清晰定义
- AI 可以建议下一步行动
- AI 可以生成 Artifact 草稿
- AI 可以帮助检查完成标准

AI 不可以：
- 自行标记 Project 完成
- 自行执行现实行动
- 虚构 Reality Evidence
- 替人决定意图

---

## 11. RELATION WITH OTHER PRODUCTS

### Family Space（YuemingHub/Family-Space）

Family Space 关注"人与最重要关系中的真实共同生活"。
World Space 关注"把想法带进现实"。

关系：Family Space 中的共同生活可能产生想法，这些想法可以进入 World Space 被实现。但 World Space 不内嵌家庭关系管理。

### Self Space（YuemingHub/Return-to-oneself）

Self Space 关注"理解自己、形成真实意图"。
World Space 关注"把真实意图带进现实"。

关系：Self Space 产出的真实意图是 World Space 的输入。World Space 不做自我认知，假设进入的意图已经是真实的。

---

## 12. V0.1 SCOPE

V0.1 只验证三件事：

### A. 做一个网站

用户想做一个网站。World Space 帮助用户：
- 定义网站要达成什么
- 一步步做出网站的页面
- 最终得到一个可以访问的 URL
- 确认网站在现实中可以打开

### B. 做一本小书

用户想做一本小书。World Space 帮助用户：
- 定义小书的主题和完成标准
- 一步步写出内容
- 最终得到一个可以阅读的文件
- 确认小书在现实中可以阅读

### C. 做一个小工具

用户想做一个小工具。World Space 帮助用户：
- 定义工具要解决什么问题
- 一步步做出工具
- 最终得到一个可以运行的入口
- 确认工具在现实中可以运行

**不扩展范围。** 不做社区、不做 marketplace、不做复杂编排。V0.1 的目标是验证核心闭环在三种场景下成立。
