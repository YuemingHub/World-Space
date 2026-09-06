# ymai.fun 平台约束（Platform Constraints）

## 架构决策
- 纯静态站点：`index.html` + `styles.css` + `script.js`（原生，无构建步骤、无框架、无依赖）。
- 理由：单页叙事官网无数据状态；零构建可直接部署到任意静态托管（Cloudflare Pages / Vercel / GitHub Pages / 国内 OSS+CND），用户自行发布到 ymai.fun。
- 不适用 web-component-design（无组件库/框架组合需求）。

## 文件结构
```
ymai.fun/
  index.html          # 单页全部结构，语义化 landmark
  styles.css          # 全部样式，token 集中在 :root
  script.js           # 故事进度线、滚动入场(IntersectionObserver)、移动导航开合
  assets/             # 生成的插画 SVG/PNG、favicon、字体
  fonts/              # Abril Fatface latin 子集 woff2（自托管，font-display:swap）
```

## 响应式与设备
- 桌面优先（模板 sourceScale=desktop-first），断点：≥1024 全量 / 768–1023 双栏网格 / ≤767 单栏 / 375 最小验证宽。
- ≤767：导航折叠为按钮+面板（button + aria-expanded，原生 focus 管理不放弹层）；网格降为单列；display 字号由 clamp 收缩。
- 禁止横向滚动：图片 max-width:100%；长词 overflow-wrap:anywhere。

## 交互约束
- 导航：锚点滚动（scroll-behavior:smooth，reduced-motion 时改 auto）；滚动进度线为纯视觉元素 aria-hidden。
- 入场动画：IntersectionObserver 添加 .is-visible，位移 12px+透明度，prefers-reduced-motion 全停。
- 状态覆盖（适用项）：hover/active/focus-visible（全部交互元素）、disabled（CTA 占位无外链时不适用）、移动导航开/关、图片加载失败兜底（插画为本地 SVG，无网络态）。
- 无表单、无后端 → 无 loading/error 数据态；CTA 指向 #method 锚点或占位 href="#"（交付说明中标注待替换真实链接）。

## 语义与 SEO
- `<html lang="zh-CN">`；唯一 h1；header/nav/main/section/footer landmark；每节 data-section-id。
- meta description、Open Graph、favicon；页面标题「ymai.fun · 普通人与孩子的AI创造故事」。

## 性能
- 仅自托管 1 个 Latin 显示字体子集（swap）；正文走系统 CJK 栈零请求；SVG 内联；图片 loading="lazy" decoding="async"；无 JS 框架运行时。
