# 当前设计真源（Current Design Source）

> 本文件是 World Space 仓库唯一的当前设计真源。
> 历史设计资产保存在 `archive/design/v1/` 和 `archive/design/v2/`，仅供追溯，不再作为实施依据。

---

## 1. 视觉方向

**Storytelling（叙事极简）** — 由用户在 v1 选卡中明确选中，通过 R2 评审（8.0/10）和渲染质量门（89/100）。

### 设计 Token

| Token | 值 | 用途 |
|---|---|---|
| `--accent` | `#3B82F6` | 唯一强调色：CTA、链接、焦点环 |
| `--accent-strong` | `#2563EB` | 文字级 accent、hover |
| `--accent-press` | `#1D4ED8` | active |
| `--sun` | `#D97706` | 暖色点缀（每节 ≤1 处） |
| `--leaf` | `#16A34A` | 成功/生长隐喻 |
| `--bg` | `#FAF9F6` | 页面背景：暖纸白 |
| `--surface` | `#FFFFFF` | 卡片面 |
| `--fg` | `#111827` | 主文本 |
| `--fg-muted` | `#4B5563` | 次文本 |
| `--border` | `#E7E5E0` | 暖灰描边 |

### 字体

- Display: Abril Fatface → Songti SC / STSong / SimSun（中文回退）
- Body: Inter → PingFang SC / Microsoft YaHei / Noto Sans SC
- Mono: JetBrains Mono → SFMono-Regular / Consolas

### 间距

4 / 8 / 12 / 16 / 24 / 32 px

### 圆角

sm: 4px / md: 8px（编辑感，不用气泡大圆角）

---

## 2. 色彩纪律

- 每屏 `--accent` 可见使用 ≤ 2 处
- `--sun` 每节 ≤ 1 处
- 禁止紫→蓝渐变 hero
- 禁止 emoji 图标（用 1.7px 单线 SVG）
- 背景主体为暖纸白 70-90% 面积

---

## 3. 排版规则

- 层级：display/H1 仅一处 → H2 分节 → H3 卡片 → 正文 17px
- 中文回退必须显式声明
- 字重三档：400 阅读 / 500 强调 / 600 宣告
- 行长：中文正文 `max-width: 40em`（约 38-42 字/行）
- 行高：正文 1.75 / 标题 1.15

---

## 4. 无障碍底线（WCAG 2.2 AA）

- 正文对 `--bg` ≥ 4.5:1
- 非文本 UI ≥ 3:1
- 触控目标 ≥ 24×24（主按钮 44px 高）
- `prefers-reduced-motion` 停用动画
- `<html lang="zh-CN">`

---

## 5. 历史资产索引

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
