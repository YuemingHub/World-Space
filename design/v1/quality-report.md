# ymai.fun 原型渲染质量报告（prototype-quality-gate）

审计对象：.ohmyagent/design/v1/prototype.html（Jury R2 通过版 + 容器 80rem 修正）
审计轮次：第 1 次正式门审计（此前 jury R1 未过→修复→R2 通过，非门审计失败）
采集方式：经典 headless Chrome（--allow-file-access-from-files + iframe 定宽包装，读数嵌入截图；direct 捕获用于 ≥768 视口）。浏览器缩放以 CSS 视口宽度模拟（经典 headless 的 dsf 不重排，元数据如实记录）。

## 证据清单（路径 · 尺寸 · 视口元数据）
| 文件 | 画布 | CSS 视口 | DPR/缩放 | 读数 |
|---|---|---|---|---|
| screenshots/desktop-hero.png | 1440x910 | 1440 | 1 / 100% | FRAME INNER sw=1425 cw=1425 NO-OVERFLOW |
| screenshots/desktop-full.png | 1440x3910 | 1440 全页 | 1 / 100% | sw=1440 cw=1440 NO-OVERFLOW |
| screenshots/desktop-zoom75.png | 1920x950 | 1920（≈75% 缩放视口） | 1 | probe sw=cw=1904, sh=3802 |
| screenshots/desktop-zoom125.png | 1152x950 | 1152（≈125% 缩放视口） | 1 | probe sw=cw=1136, sh=3722 |
| screenshots/tablet-768-full.png | 768x4290 | 768 全页 | 1 / 100% | probe sw=cw=752, sh=4220 |
| screenshots/mobile-hero.png | 375x812 | 375（iframe 真实布局） | 1 / 100% | sw=360 cw=360 NO-OVERFLOW |
| screenshots/mobile-full.png | 375x4850 | 375 全页 | 1 | sw=375 cw=375 NO-OVERFLOW |
| screenshots/mobile-320-full.png | 320x5450 | 320 全页（窄代表帧） | 1 | sw=cw NO-OVERFLOW |
| screenshots/mobile-414-full.png | 414x4648 | 414 全页（宽代表帧） | 1 | sw=cw NO-OVERFLOW |
原始未裁剪帧保留为 *-raw.png（500px 宽外框，移动帧自左裁剪）。

## 硬门槛逐项
- 横向溢出：PASS——7 个宽度（320/375/414/768/1152/1440/1920）实测 scrollWidth≤clientWidth。
- 主内容裁切/遮挡/不可达：PASS——mobile-hero 目视无裁切（R2 Designer 像素级右缘检测佐证）；粘性头有 scroll-padding-top 保护。
- 意外固定宽度塌陷：PASS——sh 随宽度正确变化（3722@1152→4220@768→4423@500），网格按断点重排。
- 内容宽度利用率：PASS——修正容器 72rem→80rem 后，1920 视口内容列 1232px = 64.2%（≥60）；1440 时 85.6%。
- 左右外留白不对称 >15%：PASS——容器居中，不对称 0%。
- 必需状态缺失：PASS——hover/active/focus-visible/reduced-motion/移动导航开合均在位；无表单/数据态需求；示例内容标注完整。

## 评分
| 类别 | 满分 | 得分 | 依据 |
|---|---|---|---|
| 布局/层级/比例 | 25 | 22 | 叙事分节清晰、栅格稳定；引言带未做全宽、插画未落地（遗留 should_fix） |
| 响应与缩放稳定性 | 20 | 18 | 7 宽度无溢出、重排正常；375 下 h1 balance 拆「想/法」微瑕 |
| 排版/间距/色彩 | 20 | 18 | 字距/行长/行高合规、字体已内嵌生效；accent/sun 自设密度超标（遗留） |
| 内容密度与留白 | 15 | 13 | 密度交替成立；首屏字号 5 级略超自设 ≤3 级锚点 |
| 无障碍与交互 | 10 | 9 | AA 色对全过、键盘/焦点完整；缺 skip link、Safari 列表语义 |
| 必需状态与内容完整性 | 10 | 9 | 状态覆盖满足范围；noscript 下移动菜单不可用（有 .js 门控兜底） |
| **总分** | **100** | **89** | ≥80 通过；每类均 ≥60% |

阻断项：无。
