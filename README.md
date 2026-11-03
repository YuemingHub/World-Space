# World Space

> 你想做什么事？选一件事，马上开始。每件事都替你选好了工具和第一步，照着做就行。打开工具只是第一步，真正动手，看看现实里发生了什么。

**公开入口：https://ymai.fun**

---

## 怎么用

打开首页，按你想做的事直达：

| 你想做的事 | 会发生什么 |
|---|---|
| ✍️ 写点东西 / 🛠️ 做个网页 / 🔍 查明一件事 / 🗂️ 整理资料·处理 PDF | 按需展开面板：一个默认工具 + 可复制的第一步 + 如实限制（做网页的进阶选项：v0 发布上线） |
| 🖼️ 做一张海报 | 按需展开：要放准确信息→稿定设计模板改字；个人用→豆包 AI 直接画 |
| 📷 整理手机照片 | 去重（手机自带）、备份、印刷相册、修图，每件一个默认做法 |
| 🔤 提取图片文字 | 微信长按、手机相册自带识别、纸质用微信扫一扫 |
| 🌱 不知道从哪开始 | 跟着三步走，每步做成一件真事： |

三步兜底（第一次用 AI 的最小上手回路，约 10 分钟）：

| 步 | 做什么 | 用什么 |
|---|---|---|
| 1 | 让 AI 帮你做一件小事（写一段自己的话） | 豆包 |
| 2 | 让它改成你满意的样子（学会提要求） | 豆包 |
| 3 | 查一件你真想知道的事，并核实来源 | DeepSeek |

全部免费开始、国内直接打开、手机可用、不用 API Key。
走完三步，回首页选一件你真正想做的事——每个目标按钮都替你备好了第一步。

---

## 仓库结构

```
PRODUCT.md              产品定义
CURRENT_STATE.md        当前状态
AGENTS.md               仓库规则

catalog/resources.json  资源目录
paths/                  兜底路径（3 步，与网页一致）
web/index.html          公开入口
index.html              根跳转页
docs/design/CURRENT_DESIGN.md  当前设计真源
docs/goal-coverage.md  目标覆盖判断（为什么是这 7 个）
docs/reality-return.md         行动-现实回路：8 入口审计 + 3 个验收例（打开工具 ≠ 现实改变）

web/ai/                 AI 从零开始（零基础入门候选；与主入口并存，未改变主入口行为）
  index.html            首屏：三件可点的小事
  limits.html           AI 会出错的 4 个判断动作
  tools.html            工具入口与年龄边界（含复核日期）
  safety.html           不要告诉 AI 什么 / 求助渠道 / 隐私
  paths/                三条入门路径（做一件小事 / 做一张图 / 查清一件真事）
docs/ai-beginner/PRODUCT.md    这条线的产品合同（含不做什么、儿童权利边界、验收判据）
docs/ai-beginner/CONTENT.md    内容索引与事实纪律
docs/ai-beginner/CHECKER.md    独立复验说明
eval/ai-beginner-selftest.mjs  内容契约自测（零依赖）
eval/ai-beginner-journey.mjs   真实浏览器旅程（本机 Chrome，不下载任何东西）
scripts/preview.mjs            本地预览（零依赖，两种静态根同时暴露）

archive/                历史资产
```

## AI 从零开始（零基础入门线）

给完全不懂 AI 的人（孩子与青少年是重点体验群体，成人初学者同样服务）的第一条路：先看懂 AI 能做什么、
会在哪里出错，再从三件小事里选一件，真正做出来。产品合同见 `docs/ai-beginner/PRODUCT.md`。

```powershell
node scripts/preview.mjs
# http://127.0.0.1:4173/ai/       ← 静态根 = web/ 的形态
# http://127.0.0.1:4173/web/ai/   ← 静态根 = 仓库根的形态
```