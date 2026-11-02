# World Space

> 你想做什么事？选一件事，马上开始。每件事都替你选好了工具和第一步，照着做就行。

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
PRODUCT.md              产品定义（Resource First）
CURRENT_STATE.md        当前状态（2026-11-02 起描述线上现实）
AGENTS.md               仓库规则（含线上与发布）
docs/v2/NORTH_STAR.md   V2 产品内核（认知链、五原则、隐私决定、通过标准）

server/                 V2 应用服务（/api/world 认知链、/api/auth、/healthz）
web/v2/                 登录后应用（index/app/style/login）
web/v2/public/          未登录公开门面（当前线上为 c953aab 版）
contracts/world.schema.json   认知链输出契约（证据纪律）
catalog/resources.json  资源目录（7 条，已核验）
paths/                  V1 三步兜底的镜像（3 个文件，非行动路径库）
eval/                   测试装置（20 个）
docs/v2/release-c500f3d/      发布工具（cutover / verifier / 身份 / 应急回退）
docs/M0-PRODUCT-RECON-20261102.md  M0 产品真源核查（真源/资产/冲突/差距）
docs/design/CURRENT_DESIGN.md     V1 设计真源（已冻结，线上以 V2 为准）

archive/                历史资产（不得修改）
index.html              历史跳转页（GitHub Pages 时代，线上不服务）
web/index.html          V1 静态页（历史资产，线上不服务）
```

> 线上部署结构、版本与回退方式见 `CURRENT_STATE.md` 与 `WORLD-SPACE-FINAL-RELEASE-RUNBOOK.md`。
