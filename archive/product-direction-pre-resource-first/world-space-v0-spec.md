> **SUPERSEDED — historical only（已废止，仅供历史追溯）**
> 本文描述的是已废止的旧方向：自建 Reality Project 产品闭环。
> 当前唯一产品方向是 Resource First，见 [PRODUCT.md](../../PRODUCT.md)。
> 本文内容不再构成任何当前承诺或计划。

# World Space V0 产品规格

> PHASE 4 产出。Implementation-ready product spec。
> 本轮只做设计规格，不做大规模编码。

---

## 1. 最小首页

一个问题：

**"你想让什么事情发生？"**

用户输入一个真实意图后，创建 Reality Project。

---

## 2. Reality Project 最小模型

```typescript
interface RealityProject {
  id: string;
  intent: string;                // 用户的真实意图
  desired_outcome: string;       // 期望的现实结果
  definition_of_done: string;    // 什么算完成
  current_state: ProjectState;   // draft | in_progress | completed | abandoned
  next_action: string;           // 下一步做什么
  artifacts: Artifact[];         // 产出的 Artifact
  actions: Action[];             // 已执行的现实行动
  tools_used: ToolUsage[];       // 使用过的 AI/Agent/Tool
  evidence: Evidence[];          // 现实证据
  reflection: string;            // 回顾与反思
  created_at: string;
  updated_at: string;
}

type ProjectState = 'draft' | 'in_progress' | 'completed' | 'abandoned';

interface Artifact {
  id: string;
  type: string;          // document | image | code | file | ...
  title: string;
  content_ref: string;   // 内容引用（文件路径 / URL）
  stage: ArtifactStage;  // ai_generated | formed | ... 
  created_at: string;
}

type ArtifactStage = 'ai_generated' | 'formed';

interface Action {
  id: string;
  description: string;   // 做了什么
  executed: boolean;     // 是否已执行
  executed_at: string | null;
}

interface ToolUsage {
  tool: string;          // 工具名称
  purpose: string;       // 用于做什么
  used_at: string;
}

interface Evidence {
  id: string;
  description: string;   // 证据描述
  type: string;          // url | file | screenshot | ...
  ref: string;           // 证据引用
  verified: boolean;     // 是否已验证
  verified_at: string | null;
}
```

---

## 3. 最小用户路径

```
Step 1: 输入意图
  用户在首页输入框写下："我想做____"
  → 创建 Reality Project（state: draft）

Step 2: 定义结果
  系统引导用户回答："做完了，现实里会多出什么东西？"
  → 填写 desired_outcome

Step 3: 定义完成标准
  系统引导用户回答："什么算做完了？"
  → 填写 definition_of_done
  → state: in_progress

Step 4: 找到下一步
  系统基于当前 Project 状态，建议一个具体的 next_action
  用户可以接受、修改、或自己写

Step 5: 执行下一步
  用户使用合适的 AI / Agent / Tool 产出 Artifact
  → Artifact 记录到 artifacts[]
  → Tool 记录到 tools_used[]

Step 6: 在现实中执行
  用户在现实中做了事（发布、导出、部署...）
  → Action 记录到 actions[]，executed: true

Step 7: 确认结果
  用户提供 Reality Evidence
  → Evidence 记录到 evidence[]
  → 系统检查是否满足 definition_of_done
  → 满足则 state: completed

Step 8: 反思与迭代
  用户填写 reflection
  可以继续迭代（回到 Step 4）或开始新 Project
```

---

## 4. 状态机

```
         ┌──────────┐
         │  draft   │ ← 刚创建，未定义完成标准
         └────┬─────┘
              │ 定义完成标准后
         ┌────▼─────────┐
         │ in_progress  │ ← 正在做
         └────┬────┬────┘
              │    │ 用户放弃
              │    ▼
              │  abandoned
              │
              │ Evidence 确认满足 definition_of_done
         ┌────▼─────┐
         │ completed │
         └──────────┘
```

---

## 5. AI 的角色边界

| AI 可以做 | AI 不可以做 |
|---|---|
| 帮助把模糊意图转化为清晰定义 | 自行标记 Project 完成 |
| 建议下一步行动 | 自行执行现实行动 |
| 生成 Artifact 草稿 | 虚构 Reality Evidence |
| 帮助检查完成标准 | 替人决定意图 |
| 建议合适的工具 | 自行选择工具并执行 |

---

## 6. V0.1 三种验证场景

### A. 做一个网站

| 字段 | 示例 |
|---|---|
| intent | 我想给我的小店做一个网站 |
| desired_outcome | 一个可以打开的网页，展示我的产品 |
| definition_of_done | 有一个 URL，手机和电脑都能打开，能看到产品信息 |
| evidence | URL 可访问，页面内容正确 |

### B. 做一本小书

| 字段 | 示例 |
|---|---|
| intent | 我想把我的烹饪经验整理成一本小书 |
| desired_outcome | 一个可以阅读的 PDF 文件 |
| definition_of_done | PDF 可以打开，有目录，有内容，有封面 |
| evidence | PDF 文件存在且可正常阅读 |

### C. 做一个小工具

| 字段 | 示例 |
|---|---|
| intent | 我想做一个提醒我浇花的小工具 |
| desired_outcome | 一个可以运行的程序 |
| definition_of_done | 程序可以运行，到时间会提醒 |
| evidence | 程序运行截图或运行入口可访问 |

---

## 7. 明确不做

- Agent marketplace
- 社区
- workflow builder
- enterprise 功能
- credits / token 系统
- plugin marketplace
- complex multi-agent orchestration
