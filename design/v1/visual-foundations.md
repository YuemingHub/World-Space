# ymai.fun 视觉基础（Visual Foundations）

来源权威：用户选定模板 Storytelling → RUN_DIRECTORY/DESIGN.md 为唯一 tokens 真源。
产品语境：中文单页叙事官网，温暖明亮略带童趣，受众为普通人/孩子/家长。

## 1. 设计 Token（:root，语义命名）

```css
:root {
  /* 品牌（DESIGN.md 真源） */
  --accent: #3B82F6;          /* 唯一强调色：CTA、链接、焦点环 */
  --accent-strong: #2563EB;   /* 文字级 accent（≥4.5:1）、hover */
  --accent-press: #1D4ED8;    /* active */
  --sun: #D97706;             /* 暖色插画 accent（来自模板 warning），每屏≤1处 */
  --leaf: #16A34A;            /* 成功/生长隐喻，仅插画与打勾 */

  /* 中性（DESIGN.md surface/text 派生；bg 依色彩规则取非纯白暖纸色） */
  --bg: #FAF9F6;              /* 页面背景：暖纸白 */
  --surface: #FFFFFF;         /* 卡片面 */
  --fg: #111827;              /* 主文本 */
  --fg-muted: #4B5563;        /* 次文本（对 --bg 7.0:1） */
  --fg-soft: #6B7280;         /* 弱化文本，仅 ≥14px 粗体或非关键信息 */
  --border: #E7E5E0;          /* 暖灰描边 */

  /* 字体 */
  --font-display: "Abril Fatface", "Songti SC", "STSong", "SimSun", serif;
  --font-body: "Inter", "PingFang SC", "Microsoft YaHei", "Noto Sans SC", sans-serif;
  --font-mono: "JetBrains Mono", "SFMono-Regular", Consolas, monospace;

  /* 字号（1.25 倍率，clamp 流式） */
  --text-display: clamp(2.75rem, 6vw + 1rem, 4.5rem);
  --text-h2: clamp(1.75rem, 3vw + 0.5rem, 2.25rem);
  --text-h3: 1.375rem;
  --text-body: 1.0625rem;
  --text-small: 0.875rem;
  --text-caption: 0.75rem;

  /* 间距（DESIGN.md 4/8/12/16/24/32，扩展段落节奏） */
  --space-1..6: 4/8/12/16/24/32px; --space-section: 96px; --space-section-tight: 64px;

  /* 圆角（DESIGN.md）：--radius-sm:4px; --radius-md:8px（编辑感，不用气泡大圆角） */
  /* 阴影 */ --shadow-rest: 0 1px 2px rgba(17,24,39,.06), 0 4px 12px rgba(17,24,39,.06);
  --shadow-lift: 0 2px 4px rgba(17,24,39,.08), 0 8px 24px rgba(17,24,39,.10);
}
```

## 2. 排版规则（中文适配为关键约束）

- 层级：display/H1 仅一处；H2 分节标题；H3 卡片标题；正文 17px。
- 中文回退必须显式声明（Abril Fatface/Inter 均无 CJK 字形）：display 中文走系统宋体栈，正文走苹方/雅黑栈。
- 字重三档制：400 阅读 / 500 强调 / 600 宣告；中文 display 禁用 700+（避免合成粗体发糊）。
- 字距：全大写 eyebrow `letter-spacing:.08em`；display(≥32px) `-0.015em`（仅作用于拉丁）；中文标题 `0`（禁负字距）；正文 `0`。
- 行长：中文正文 `max-width: 40em`（约 38–42 字/行）；行高 正文 1.75 / 标题 1.15。
- 英文术语（AI、ymai.fun）在 display 中由 Abril Fatface 承载，形成中西文对比的"故事书"气质。

## 3. 色彩纪律（anti-ai-slop 合规）

- 每屏 `--accent` 可见使用 ≤2 处：主 CTA + 一处 eyebrow/链接。
- `--sun`(#D97706) 为温度来源：仅用于手绘下划线、示例标签、插画太阳等，每节 ≤1 处；禁止紫→蓝渐变 hero。
- `--leaf`(#16A34A) 仅出现在"打勾/生长"语义；`#8B5CF6`(secondary) 仅保留 token，不进入首屏视觉。
- 背景主体为 --bg 暖纸白 70–90% 面积；hero 为平色+类型驱动，不做渐变装饰。
- 图标：1.7px 单线 SVG、`currentColor`，禁止 emoji 图标。

## 4. 版式与叙事节奏

- 桌面 12 栏、容器 max-width 72rem、左右 padding 24px；移动单栏 16px。
- 分节密度交替：信念区（紧凑、高密度对比）→ 故事区（呼吸、大图卡）→ 方法区（紧凑步骤）→ 尾部 CTA（留白）。
- 一个非常规分节替代 AI 模板骨架：全宽"引言带"（一句孩子的话作为超大引文，衬线、非居中、左缩进）。
- 每节稳定标识 `data-section-id`（hero/belief/stories/method/cta/footer）。

## 5. 图像方向

- 无真实人像（不得虚构真实人物）：故事配图为扁平暖色插画（纸感底、sun/leaf/蓝三色、粗轮廓），由文生图生成，alt 文本必填。
- 禁止外链占位图 CDN；所有资源本地化。
- 示例内容统一挂"示例"标签（mono 小标签、--border 描边、手贴纸感微旋转 -1deg）。

## 6. 交互状态与无障碍底线（WCAG 2.2 AA）

- 按钮：hover --accent-strong / active --accent-press + 下压 1px；focus-visible 2px 外描边 outline（3:1），永不 `outline:none` 裸删。
- 正文对 --bg ≥4.5:1（--fg 15.1:1，--fg-muted 7.0:1）；非文本 UI ≥3:1。
- 触控目标 ≥24×24（主按钮 44px 高）；键盘可达：语义 landmark + 单 h1 + 无跳级标题 + 原生 button/a。
- `prefers-reduced-motion` 时停用滚动动画与位移，仅保留透明度。
- 语言：`<html lang="zh-CN">`；图片 alt 必填；纯装饰 alt=""。

## 7. 灵魂（20% 独特选择）

- 大胆一笔：display 标题中"现实"二字下压一根手绘感 amber 描边 SVG。
- 声音：CTA 文案"开始你的第一个创作"（拒绝"了解更多"）。
- 微交互：故事卡 hover 上浮 2px + 影升；页首细"故事进度线"随滚动生长。
- 产品细节：每张示例卡右下角"由 AI 完成 · 示例"角标，像创作印章。

## 8. 验收锚点

- 首屏可见字号 ≤3 级；token 外裸 hex ≤6；无 emoji 图标；无外链占位图。
- 桌面/375px 移动无横向滚动；全键盘可走通；对比度全过 AA。
