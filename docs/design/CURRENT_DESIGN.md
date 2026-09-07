# 当前设计真源（Current Design Source）

> 本文件描述当前线上产品（`web/index.html`）实际生效的设计。
> 历史设计资产（叙事单页 v1/v2）保存在 `archive/design/`，仅供追溯，不再作为实施依据。
> 最后更新：2026-09-07

---

## 1. 产品形态

单页行动入口（纯静态，单文件 HTML）：

```
sticky topbar（品牌 + 总进度 x/9 + 进度条）
→ hero（「你想做什么事？」+ 8 个直达按钮）
   ├─ 4 个 AI 目标按钮 → deeplink 进入对应步骤（写点东西/做个网页/查明一件事/整理资料·处理 PDF）
   ├─ 3 个目标按钮 → 展开目标面板（做一张海报 / 整理手机照片 / 提取图片文字）：
   │    面板内按真实子目标二分/四分，每个子目标给一个默认能力 + 第一步 + 如实标注（水印/商用限制/iOS 版本/会员门槛/手写识别误差）
   │    海报：准确信息→稿定设计模板改字；个人用→豆包 AI 生图（含复制模板句）
   │    照片：去重（iPhone/安卓原生）、备份（自带云/一刻相册）、印刷相册（照片书小程序）、修图（醒图）
   │    OCR：微信长按提取文字、相册自带识别（iPhone 实况文本/安卓）、纸质用微信扫一扫
   └─ 兜底宽按钮「不知道从哪开始？跟着 4 步走」→ 进入完整路径
→ 4 阶段总览 pills（随完成亮起）
→ 4 个阶段卡（手风琴）：
    阶段引言（一段话，不占步骤）
    → 编号步骤（手风琴）：说明 + prompt 复制框 + 工具按钮 + "做完了 ✓"
    → 阶段检查点
→ 完成画面（做成的事清单 + 下一步建议 + 分享）
```

一次只展开一个阶段、一个步骤、一个目标面板；完成即自动折叠并展开下一步。目标面板独立于 4 步进度体系。

## 2. 设计 Token（与 `web/index.html` :root 一致）

| Token | 值 | 用途 |
|---|---|---|
| `--accent` | `#3B82F6` | 阶段徽章数字底、状态 pill 底色 |
| `--accent-strong` | `#2563EB` | 主操作/工具按钮背景、链接 |
| `--leaf` | `#16A34A` | 完成/生长、进度条、徽章 |
| `--sun` | `#D97706` | 第 4 阶段徽章 |
| `--bg` | `#FAF9F6` | 页面背景（暖纸白） |
| `--surface` | `#FFFFFF` | 卡片面 |
| `--fg` | `#111827` | 主文本 |
| `--fg-muted` | `#6B7280` | 次文本 |
| `--border` | `#E7E5E0` | 描边 |

半径：12px（卡片）/ 6px（小件）。阶段点缀色：s1 `--leaf`、s2 `--accent`、s3 `#8B5CF6`、s4 `--sun`（仅徽章/底色；前景文字用深化变体 #166534 / #1D4ED8 / #6D28D9 / #92400E 以满足 WCAG AA）。主按钮与工具按钮背景用 `--accent-strong`（白字 5.17:1），完成类按钮与复制成功态用 `#15803D`（白字 5.02:1），徽章数字 19px bold（大文本 3:1 档）。

## 3. 字体与排版

- 系统字体栈：`-apple-system, 'PingFang SC', 'Microsoft YaHei', 'Noto Sans SC', sans-serif`，0 外部字体请求
- 正文 17px / 行高 1.8；h1 `clamp(24px, 5vw, 34px)`；步骤标题 16px；辅助文字 14–15px
- 内容列最大宽 680px

## 4. 交互与无障碍

- 手风琴聚焦：当前阶段/步骤展开，其余折叠；完成自动折叠 + 滚动到下一步
- `prefers-reduced-motion` 停用全部动画
- 移动端（≤480px）触控目标 ≥44px：复制按钮与检查点按钮 `min-height: 44px`，工具按钮 14px×28px padding
- 标题语义：阶段标题 h2、步骤标题 h3、完成画面 h2
- 复制：`navigator.clipboard` → `execCommand` fallback（微信内置浏览器等）
- 外链一律 `target="_blank" rel="noopener"`

## 5. 性能约束

单文件 HTML（CSS/JS 全内联），0 外部请求（无字体/图标/JS/CSS 依赖），无构建步骤。 emoji 作为轻量图标语言，不引入图标库。

---

## 6. 历史资产索引

| 资产 | 路径 | 说明 |
|---|---|---|
| v1 设计简报 | `archive/design/v1/brief.md` | ymai.fun 单页叙事官网简报 |
| v1 设计令牌 | `archive/design/v1/DESIGN.md` | Storytelling 模板原始 token |
| v1 平台约束 | `archive/design/v1/platform.md` | 静态站点架构决策 |
| v1 视觉基础 | `archive/design/v1/visual-foundations.md` | CSS token + 排版 + 色彩 + 无障碍 |
| v1 原型 | `archive/design/v1/prototype.html` | 单文件 HTML 原型（40KB） |
| v1 质量报告 | `archive/design/v1/quality-report.md` | 89/100，7 宽度无溢出 |
| v1 评审记录 | `archive/design/v1/critique/summary.md` | R1 7.55 → R2 8.00 |
| v2 评估 | `archive/design/v2/assessment.md` | 信息架构重构：看见→学会→陪跑 |
| v2 方向决定 | `archive/design/v2/SELECTED-DIRECTION.md` | 延续 Storytelling |
