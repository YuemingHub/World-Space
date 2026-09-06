# AGENTS.md

> 本文件定义 World Space 仓库的工作规则。

## 产品边界

World Space 不是：
- AI 工具导航站
- 教程网站
- Agent Marketplace
- 通用自动化平台
- 社区
- workflow builder
- enterprise 产品
- credits/token 系统
- plugin marketplace
- complex multi-agent orchestration

World Space 是：
帮助一个普通人把一个真实想法带进现实的产品。

## 核心约束

1. **AI output != reality completion**
   必须区分：AI 生成 → Artifact 已形成 → Action 已执行 → Reality Evidence 已出现

2. **不得虚构**
   不虚构用户、成果、收入、数据、学员、转化率。

3. **V0.1 范围锁定**
   只做：一个网站、一本小书、一个小工具。不扩展。

4. **设计资产保护**
   `archive/design/` 中的历史资产不得修改或删除。当前设计真源为 `docs/design/CURRENT_DESIGN.md`。

5. **提交规范**
   commit message 描述产品变更和理由，不提及工具/流程名称。

## 仓库结构规则

- 只有有真实内容时才创建目录，不创建空目录
- 产品代码放 `app/`，公开网站放 `web/`
- 核心模型放 `core/`
- 历史资产放 `archive/`
