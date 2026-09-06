# PRODUCT.md — World Space 产品契约

> 本文件是 World Space 的唯一产品定义。
> 最后更新：2026-09-06
> 方向修正：从"自建 Reality Project 产品闭环"转向"Resource First——发现、筛选、带着普通人使用世界已有优秀能力"

---

## 0. 最高原则

> **我们不制造能力，我们寻找世界上已经存在的最好能力，然后帮助普通人知道：我想做这件事，该从哪里进去、怎么开始、怎么把它做出来。**

> **让一个原本不知道该怎么办的人，真正开始做，并且少走很多弯路。**

> **不要造轮子。Founder 本身不是开发出身，也不应该靠一个人重新开发世界上已经成熟的 AI 基础设施。**

World Space 的价值不是"我们有多少 AI 功能"，而是：

**世界已经有这么多能力，普通人怎样真正用起来。**

---

## 1. WHAT IS WORLD SPACE

World Space 是：

**一个帮助普通人找到并使用世界现有优秀能力，把一个想法真正开始做起来的行动入口。**

World Space 做三件事：

### 找
找到当前世界上真正优秀、仍在维护、值得普通人使用的现成能力。

### 选
不是做"AI 工具大全"。而是替普通人筛选：这件事，现在最值得从哪里开始。

### 带着开始
不是只扔一个 GitHub 链接。而是告诉普通人：它能帮你干什么、为什么推荐它、第一步点哪里、第一段话怎么说、做到什么程度算已经开始、卡住以后怎么办。

核心不是"收藏"，核心是：**行动。**

---

## 2. WHAT WORLD SPACE IS NOT

World Space 不是：

- AI 基础设施公司
- Agent Framework
- AI Operating System 的重新实现
- Workflow Builder
- Coding Agent
- Research Agent
- Browser Agent
- MCP Host 重造
- SaaS 大平台
- AI 工具大全
- GitHub 项目排行榜
- 教程网站
- Agent Marketplace
- 社区 / 社交平台
- enterprise 产品
- credits / token 经济系统

---

## 3. WHY

一个普通人脑子里有一个想法，但这个想法永远停留在脑子里。

不是因为想法不好，而是因为从"想法"到"行动"之间有太多看不见的步骤。世界已经有这么多能力，但普通人不知道该从哪个进去、怎么开始、怎么把它做出来。

World Space 存在的理由：**让一个原本不知道该怎么办的人，真正开始做，并且少走很多弯路。**

---

## 4. WHO

一个普通人。

- 不是开发者
- 不是创业者
- 不是技术爱好者
- 是一个有真实想法、但不知道怎么把它做出来的人

可能是一个想做网站的家长，一个想把经验整理成小书的退休者，一个想解决自己工作中某个小问题的人。

---

## 5. 复用优先级

以后 World Space 引入任何能力，必须按下面顺序决策：

```
1. 直接引用现有产品 / 项目
        ↓
2. 使用官方现成配置 / Template
        ↓
3. 使用 API / SDK / MCP
        ↓
4. 做非常薄的适配层
        ↓
5. 必要时轻度 Fork
        ↓
6. 自己开发
```

第 6 项必须永远是最后选项。

任何"自己开发"都必须先回答：

1. GitHub / 市场上是否已经有成熟方案？
2. 为什么不能直接复用？
3. 为什么 API / SDK 不够？
4. 为什么 Fork 不够？
5. 自己维护它未来会付出什么成本？
6. 这个能力真的是 World Space 的核心资产吗？

回答不成立：**禁止开发。**

---

## 6. 废止的旧方向

以下方向已废止，不再推进：

- 自研 Agent Runtime
- 自研 Workflow Engine
- 自研 Browser Agent
- 自研 Coding Agent
- 自研 Research Agent
- 自研 Sandbox
- 自研 MCP 平台
- 自研 Tool Marketplace
- 自研复杂 Reality Project 系统
- 自研统一执行平台
- 自维护大量第三方 Integration

不是说这些概念永远错误，而是：**现阶段 World Space 没有理由自己开发它们。**

---

## 7. 产品边界

### 可以直接跳出去

World Space 不需要为了"用户留存"强迫用户留在自己网站。如果最好的工具就在外面，直接带用户过去。

第一阶段成功指标：**用户进入 World Space，5 分钟后知道自己该去哪并已经开始动手。**

### 可以引用，不必集成

如果链接足够：就链接。如果官方 Template 足够：就使用 Template。如果官方 hosted service 已经很好：就带用户过去。不要为了"看起来像自己的产品"就做 API 集成。

### Thin Layer Only

只有真实使用证明大量用户反复在某一步卡住，才考虑做轻集成（deeplink / prefilled prompt / template link / official SDK / MCP / API）。禁止因此开始重写对方产品。

---

## 8. 内容诚信约束

不得虚构：
- 用户、成果、收入、数据、学员、转化率
- 资源的能力、门槛、价格、维护状态

所有推荐必须基于真实核查。项目以前很火，不代表现在值得推荐。

---

## 9. RELATION WITH OTHER PRODUCTS

### Family Space（YuemingHub/Family-Space）

Family Space 关注"人与最重要关系中的真实共同生活"。World Space 关注"把想法变成行动"。两者独立。

### Self Space（YuemingHub/Return-to-oneself）

Self Space 关注"理解自己、形成真实意图"。World Space 关注"带着行动开始"。两者独立。World Space 不假设进入的用户已经完成自我探索，但也不做自我探索。

---

## 10. V0.1 SCOPE

V0.1 只做：

1. **产品定义纠偏** — 从自建方向纠正为 Resource First
2. **Resource Discovery** — 调研并筛选第一批值得推荐的优秀能力（10–20 个）
3. **资源目录** — `catalog/resources.json`，机器可读
4. **行动路径** — `paths/`，普通人能跟着开始的路径（4–6 条）
5. **极简 Web** — 一个非常好的公开行动入口，不是复杂应用
6. **验收** — 从普通人角度测试

不扩展范围。不做社区、不做 marketplace、不做复杂编排、不做账号系统。

---

## 11. 仓库结构

```
README.md
PRODUCT.md
CURRENT_STATE.md
AGENTS.md
WORLD_SPACE_FACT_MAP.md

catalog/
  resources.json        资源目录（机器可读）
paths/                  普通人行动路径（Markdown）
docs/                   设计与规格文档
  design/
    CURRENT_DESIGN.md   唯一当前设计真源
archive/                历史设计资产，仅供追溯
  design/
    v1/
    v2/
```
