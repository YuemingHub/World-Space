# AGENTS.md

> 本文件定义 World Space 仓库的工作规则。
> 最后更新：2026-09-06

## 产品方向

World Space 是：**一个帮助普通人找到并使用世界现有优秀能力，把一个想法真正开始做起来的行动入口。**

World Space 不是：AI 基础设施公司、Agent Framework、Workflow Builder、Coding Agent、Research Agent、Browser Agent、MCP Host 重造、SaaS 大平台、AI 工具大全、教程网站、社区。

## 复用优先级

引入任何能力必须按此顺序决策：

```
1. 直接引用现有产品 / 项目
2. 使用官方现成配置 / Template
3. 使用 API / SDK / MCP
4. 做非常薄的适配层
5. 必要时轻度 Fork
6. 自己开发（最后选项，必须回答六个问题才能启动）
```

## 核心约束

1. **不造轮子**
   现阶段不自己开发 Agent Runtime、Workflow Engine、Browser Agent、Coding Agent、Sandbox、MCP 平台、Tool Marketplace、复杂 Reality Project 系统。已废止的方向见 PRODUCT.md §6。

2. **推荐而非堆工具**
   承担判断责任：如果你是普通人，建议你先从这个开始。最多给一个分叉（最省事 vs 想自己部署），不摆 8 个工具让用户自己选。

3. **内容诚信**
   不虚构用户、成果、收入、数据、资源能力、门槛、价格、维护状态。所有推荐必须基于真实核查。项目以前很火不代表现在值得推荐。

4. **可以直接跳出去**
   如果最好的工具就在外面，直接带用户过去。成功指标是"用户 5 分钟后知道该去哪并已经开始动手"，不是"用户在 World Space 停留 40 分钟"。

5. **设计资产保护**
   `archive/design/` 中的历史资产不得修改或删除。当前设计真源为 `docs/design/CURRENT_DESIGN.md`。

6. **提交规范**
   commit message 描述产品变更和理由，不提及工具/流程名称。

7. **每轮推送 GitHub（硬性要求）**
   每一轮工作结束前，必须将本轮所有变更 commit 并 push 到 `origin`（GitHub: YuemingHub/World-Space）。
   不允许出现"只在本地汇报、未推送"的轮次；即使本轮无变更，也要说明"本轮无变更、无需推送"。
   推送后确认本地分支与对应远程分支同步（`git status` 显示 up to date / working tree clean）。
   这是为了让主 agent 能直接从 GitHub 读取每一轮的进展，而不依赖会话内汇报。

## 仓库结构规则

- 只有有真实内容时才创建目录，不创建空目录
- 资源目录放 `catalog/`
- 行动路径放 `paths/`
- 文档放 `docs/`
- 历史资产放 `archive/`
