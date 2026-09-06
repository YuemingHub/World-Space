# OUR_WORLD_FACT_MAP

> 生成时间：2026-09-06
> 扫描方式：只读 Git 命令 + 文件系统遍历 + 内容读取
> 仓库：YuemingHub/World-Space
> 分支：foundation/our-world-v0（基于 main 9ed67c0）

---

## 1. Git 元数据

| 项目 | 值 | 证据 |
|---|---|---|
| HEAD commit | `9ed67c064561c6022ea56484d83a64eb3bf12e74` | `git rev-parse HEAD` |
| 当前分支 | `foundation/our-world-v0`（从 `main` 创建） | `git branch --show-current` |
| 远程 | `origin → https://github.com/YuemingHub/World-Space.git` | `git remote -v` |
| 全部分支 | `main`, `remotes/origin/main` | `git branch -a` |
| 提交历史 | 1 commit: "Initial commit: project design files" | `git log --oneline --all` |
| 工作区状态 | clean（扫描时无未提交变更） | `git status --short` |

---

## 2. Tracked Files 清单（44 files，git ls-files）

```
.gitignore
design/v1/DESIGN.md
design/v1/brief.md
design/v1/capture/frame-dfull.html
design/v1/capture/frame-dhero.html
design/v1/capture/frame-full.html
design/v1/capture/frame-hero.html
design/v1/capture/frame-m320.html
design/v1/capture/frame-m414.html
design/v1/capture/frame-mfull.html
design/v1/capture/frame-mhero.html
design/v1/capture/probe.html
design/v1/critique/.submit.lock
design/v1/critique/events.jsonl
design/v1/critique/round-1.json
design/v1/critique/round-2.json
design/v1/critique/run.json
design/v1/critique/summary.md
design/v1/fonts/abril.woff2
design/v1/platform.md
design/v1/prototype.html
design/v1/quality-report.md
design/v1/screenshots/desktop-full.png
design/v1/screenshots/desktop-hero.png
design/v1/screenshots/desktop-zoom125.png
design/v1/screenshots/desktop-zoom75.png
design/v1/screenshots/mobile-320-full-raw.png
design/v1/screenshots/mobile-320-full.png
design/v1/screenshots/mobile-414-full-raw.png
design/v1/screenshots/mobile-414-full.png
design/v1/screenshots/mobile-full-raw.png
design/v1/screenshots/mobile-full.png
design/v1/screenshots/mobile-hero-raw.png
design/v1/screenshots/mobile-hero.png
design/v1/screenshots/tablet-768-full.png
design/v1/template-previews/creative.png
design/v1/template-previews/educational-platform.png
design/v1/template-previews/storytelling.png
design/v1/visual-foundations.md
design/v2/SELECTED-DIRECTION.md
design/v2/assessment.md
design/v2/template-previews/editorial.png
design/v2/template-previews/educational-platform.png
design/v2/template-previews/storytelling.png
```

---

## 3. design/v1 — 内容与性质

### 3.1 定位

ymai.fun 单页叙事官网原型设计资产。非产品工程代码，是设计流程产物。

### 3.2 关键文件

| 文件 | 性质 | 核心内容 |
|---|---|---|
| `brief.md` | 设计简报 | 单页沉浸式叙事官网，受众=普通人/孩子/家长，部署目标 ymai.fun，纯静态 HTML/CSS/JS |
| `DESIGN.md` | 设计令牌真源 | Storytelling 模板，色彩(#3B82F6/#8B5CF6/#16A34A/#D97706/#DC2626)，字体(Abril Fatface/Inter/JetBrains Mono)，间距 4/8/12/16/24/32 |
| `platform.md` | 平台约束 | 纯静态站点(index.html+styles.css+script.js)，桌面优先，无构建步骤无框架，断点 ≥1024/768-1023/≤767/375 |
| `visual-foundations.md` | 视觉基础规范 | CSS :root token 定义，排版规则(中文适配)，色彩纪律(anti-ai-slop)，交互状态(WCAG 2.2 AA) |
| `prototype.html` | 原型实现 | 单文件 HTML(~40KB)，内联 CSS/JS，内嵌 Abril Fatface woff2(base64)，结构：hero→信念对比→引言带→故事卡×4→四步方法→CTA→页脚 |
| `quality-report.md` | 渲染质量报告 | 7 宽度(320-1920)无横向溢出 PASS，总分 89/100(≥80 通过)，无阻断项 |
| `critique/summary.md` | 设计评审记录 | Round 1: 7.55/10(未过)→ Round 2: 8.00/10(通过)，5 角色评审(Designer/Critic/Brand/Accessibility/Copy) |
| `critique/*.json` | 评审结构化数据 | round-1.json, round-2.json, run.json, events.jsonl |
| `fonts/abril.woff2` | 字体文件 | Abril Fatface Latin 子集 |
| `screenshots/*.png` | 渲染截图 | 桌面/平板/移动多视口多尺寸 |
| `capture/frame-*.html` | 截图采集脚本 | iframe 定宽包装测量脚本 |
| `template-previews/*.png` | 模板预览图 | creative/educational-platform/storytelling |

### 3.3 信息架构（v1 原型）

```
hero（主张+CTA）
→ 信念对比区（过去 vs 现在）
→ 引言带（孩子的话）
→ 故事卡 ×4（示例：10岁孩子做绘本/宝妈开小店/退休教师出回忆录/乡村学生学编程）
→ 四步方法（想法→与AI对话→做出第一版→发布与迭代）
→ 尾部 CTA
→ 页脚
```

---

## 4. design/v2 — 内容与性质

### 4.1 定位

v2 不是新原型，是对 v1 的信息架构重构评估。

### 4.2 关键文件

| 文件 | 核心内容 |
|---|---|
| `assessment.md` | 信息架构从"故事→方法"升级为"看见→学会→陪跑"三幕。保留 v1 视觉方向，新增细致教程区和陪跑转化区。 |
| `SELECTED-DIRECTION.md` | 延续 v1 Storytelling 模板方向，依据：用户在 v1 已选中、通过 R2 评审(8.0)、通过渲染质量门(89/100)。 |

### 4.3 v2 变更意图

- 保留：视觉方向、tokens、字体、色彩、既有故事区
- 修改：信息架构 → 看见→学会→陪跑
- 新增：细致教程区、陪跑转化区
- 声明：不虚构价格、效果承诺、学员数据

---

## 5. 是否已有 Web Runtime

**否。**

- `prototype.html` 是设计原型，非可运行的产品 Web 应用。
- 无 `index.html`（产品入口）。
- 无前端框架（React/Vue/Svelte/Next.js 等）。
- 无构建工具配置（webpack/vite/rollup 等）。
- 证据：`Get-ChildItem -Recurse -Filter "package.json"` 返回空；无 `*.ts`/`*.tsx`/`*.js`/`*.jsx` 文件（prototype.html 内联 JS 不计）。

---

## 6. 是否已有 Package / Runtime Config

**否。**

- 无 `package.json`、`tsconfig.json`、`pyproject.toml`、`requirements.txt`、`Cargo.toml`、`go.mod`。
- 证据：逐项 `Get-ChildItem -Recurse -Filter` 全部返回空。

---

## 7. 是否已有 Deploy Config

**否。**

- 无 `Dockerfile`、`docker-compose.yml`、`vercel.json`、`netlify.toml`、`.github/workflows/`。
- `platform.md` 提到部署目标为 ymai.fun 静态托管，但无实际部署配置文件。

---

## 8. 是否已有 Backend

**否。**

- 无服务端代码（无 `*.py`、无 `server.*`、无 `api/` 目录）。
- `platform.md` 明确："无表单、无后端数据，因此无 loading/error 数据状态需求"。

---

## 9. 是否已有 Tests

**否。**

- 无测试文件、无测试框架配置、无 `tests/` 目录。
- `quality-report.md` 是设计渲染质量审计，非软件测试。

---

## 10. 是否已有 CI

**否。**

- 无 `.github/` 目录。
- 证据：`Get-ChildItem -Path ".github" -Recurse` 返回空。

---

## 11. 是否存在 Secret / Credential 风险

**否。**

- 对全部 `.md`/`.json`/`.jsonl`/`.html`/`.css`/`.js` 文件执行 regex 扫描：
  `(?i)(api[_-]?key|secret|password|token|credential|private[_-]?key|BEGIN RSA|BEGIN PRIVATE|AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,})`
- 结果：0 matches。
- 无 `.env` 文件。
- `prototype.html` 内嵌的 base64 数据为字体子集，非凭据。

---

## 12. 总结

| 维度 | 状态 |
|---|---|
| 仓库性质 | 设计资产集合，非产品工程仓库 |
| Web Runtime | 不存在 |
| Package/Build | 不存在 |
| Deploy Config | 不存在 |
| Backend | 不存在 |
| Tests | 不存在 |
| CI | 不存在 |
| Secret 风险 | 无 |
| 设计资产完整度 | v1 完整（简报→规范→原型→评审→质量报告→截图），v2 为评估记录 |
| 产品工程就绪度 | 0% |
