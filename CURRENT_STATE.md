# CURRENT_STATE

> 最后更新：2026-09-06
> 分支：foundation/our-world-v0
> 方向：Resource First — 发现、筛选、带着普通人使用世界已有优秀能力

---

## 1. 仓库层面

| 项目 | 值 |
|---|---|
| 当前分支 | `foundation/our-world-v0`（从 `main` 创建） |
| 当前 HEAD | 见 `git log --oneline -1` |
| Commits ahead main | 4 |
| PR #1 | OPEN, head=`foundation/our-world-v0`, base=`main` |
| Runtime | 无后端；前端为纯静态 HTML（web/index.html） |
| Build system | 无需 build（纯静态） |
| Tests | 手动验收 |
| CI | 无 |
| Deployment | 待部署（ymai.fun DNS 已指向 GitHub Pages，待启用） |
| AI Provider | 无 |

## 2. 资源目录

| 项目 | 值 |
|---|---|
| 资源总数 | 14 |
| default（普通用户首选） | 6 |
| alternative（特定需求才推荐） | 4 |
| advanced（需要技术能力） | 4 |
| 行动路径 | 5（4 普通 + 1 进阶） |

### 资源分级

| 等级 | 资源 |
|---|---|
| default | v0, Notion, Excalidraw, DeepSeek, Stirling PDF, n8n |
| alternative | Bolt.new, Replit, Gamma, Perplexity |
| advanced | Cursor, GPT-Academic, Browser Use, Open Interpreter |

## 3. Web 状态

- 首页一级入口：4 个（做一个东西 / 表达想法 / 搞明白一件事 / 少做重复工作）
- 进阶入口：底部轻链接（不作为一级入口）
- 技术：纯静态 HTML + CSS + 极少 JS
- 无后端、无数据库、无构建系统、无 AI runtime

## 4. 产品真源

| 文件 | 角色 |
|---|---|
| PRODUCT.md | 唯一产品定义 |
| AGENTS.md | 仓库工作规则 |
| CURRENT_STATE.md | 当前状态（本文件） |
| catalog/resources.json | 资源目录（机器可读） |
| paths/*.md | 行动路径（5 条） |
| web/index.html | 公开行动入口 |
| docs/design/CURRENT_DESIGN.md | 唯一设计真源 |

## 5. 已归档（历史，不再当前）

| 路径 | 内容 |
|---|---|
| archive/design/v1/ | 历史设计资产 v1 |
| archive/design/v2/ | 历史设计资产 v2 |
| archive/product-direction-pre-resource-first/ | 旧方向文档（Reality Project 等），已标记 SUPERSEDED |

## 6. 当前明确没有的能力

- 无 web 服务器（纯静态 HTML）
- 无后端
- 无数据库
- 无 AI runtime
- 无账号系统
- 无 CI/CD
- 无构建系统
