# MING_LANGUAGE_WORLD · World Space 的骨骼对齐记录

> 本轮：把 `web/index.html`（公开门面页）重写为四站共享骨骼 v1.0 的 World 主题实现。
> 最后更新：2026-09-19 · 分支 `design/ming-language-20260919`

## 0. 指针（谁是真源）

| 角色 | 位置 |
|---|---|
| 跨站设计规范 | `MingOS-web/MING_VISUAL_LANGUAGE.md` v1.0 |
| 共享 CSS 骨骼 | `design-web/MING_SKELETON.css`（整段照抄，只换 `:root` 主题） |
| 度量/组件真源（逐字节核验的线上页） | `Family-Space/website/index.html` = https://ymai.love （SHA256 `2b94e656…afdd`） |
| 本站实现 | `web/index.html`（单文件、内联 CSS/JS/SVG/字体、零外部请求、零构建步骤） |
| 本站局部件 + 删掉的声明台账 | 本文件 §3 §4 |

本站**不引入** `web/ming-skeleton.css`：骨骼整段内联在 `web/index.html` 的 `<style>` 里，
与基线同一形态，保住"零外部请求 + 零构建"这两条硬约束。

---

## 1. 主题覆盖（规范 §1.4 允许的唯一一块）

```css
--bg:#0E1211   --bg-1:#111614   --bg-2:#151B19   --bg-deep:#0A0E0C
--life:#9DB8A5              /* 门外天光——是出路，不是屋里的灯 */
--life-soft:rgba(157,184,165,.07)
--life-line:rgba(157,184,165,.30)
--hairline-rgb:224,231,224
```

母题：**工作台、门、和一条走出去的路。** 首屏画面 = 左边一张工作台，右边一扇敞开的门，
门外是天光、一条地平线和一条收出去的路。工作台的白天，不是暖房里的一盏灯。

**度量、字体分层、动效时长、`--beat-gap` 一律未改。** 家族识别度靠骨骼（ink 底 + hairline 结构 +
留白比例 + 行式列表 + 时间账），区分度靠底色温度、天光色，和"这一站的重点是离开这一页"。

### 1.1 骨骼里三处硬编码了 Family 的墨色字面量 → 换成本站同义色值

`MING_SKELETON.css` 的这几条规则把基线（Family）的底色写成了字面 `rgba()`，不是 token。
按规范"每站只允许覆盖颜色"，这里替换的是**颜色本身**，不是度量：

| 规则 | 基线字面量 | 本站（= `--bg` #0E1211 / `--bg-deep` #0A0E0C 的 rgba） |
|---|---|---|
| `.head.is-stuck` | `rgba(14,12,9,.94)` / `.78` | `rgba(14,18,17,.94)` / `.78` |
| `.hero-scrim` | `rgba(18,16,12,…)` | `rgba(14,18,17,…)`（含 900px 断点那条） |
| `.scrim`（抽屉遮罩） | `rgba(8,6,4,.68)` | `rgba(8,10,9,.68)` |

`::selection` 与 `.progress` 渐变走 `--life-line` / `--dawn` token，不需要替换。
（这三处应当在下一次骨骼修订时改造成 token，避免每站手抄。已记入 §6 未决。）

---

## 2. 页面结构（规范 §2 的 ymai.fun 叙事骨架：门 → 缺失 → 一件事 → 入口 → 工具的位置 → 出门）

| Beat | 类 | 内容 |
|---|---|---|
| 01 | `.hero` | kicker `World Space` + `out the door`；H1 两行；`.note` 副线；`.entry` → `#entrances`；`.entry--quiet` 开抽屉 |
| 02 | `.lead` ×2 + `.note` | 缺的不是下一个工具 |
| 03 | `.h2life` + `.day` | 「我想做一个自己的网页。」六步时间账，`time` 槽放步骤名（mono），末条 `.day--after` |
| 04 | `.h2life` + `.rows` + `.stamp` | 八个入口，一行一件事 |
| 05 | `.lead` + `.note` + `.notlist` | 工具不是主角 |
| 06 | `.mrow` ×3 + `.note` + `.stamp` | Reality Marker |
| 07 | `.lead` + `.entry` | 先做出来 |
| footer | `.constellation` + `.foot-links` + `.sibs` + `.foot-bottom` | World Space 实心放大 + `YOU ARE HERE` |

**Beat 04 的关键改动**：原来的 `.intents`（2 列 emoji 卡片网格 + `.goal-panel`）整体换成骨骼的
`.rows` 行式列表——大号衬线标题 + 细线 + 留白，一屏 8 行文字，没有色块、没有 emoji 墙。
唯一的字形记号是行尾一个等宽按钮（`展开` / `收起`）。emoji 全部撤下（原页面 20 处）。

---

## 3. 本站局部件（骨骼词汇表之外，只加两个）

`.rows > li` 保持骨骼声明原样（`display:flex; align-items:baseline; flex-wrap:wrap`），
详情块靠 `flex:0 0 100%` 落到自己一行，不改父规则。

| 类 | 用途 | 无 JS 行为 |
|---|---|---|
| `.row-btn` `.goal` `.blk` `.k` `.v` `.limit` | 入口行的展开结构与"默认/为什么/第一步/限制"四件套 | `.goal` 默认可见；只有 `.js .goal{display:none}`，展开态 `.js .row.is-open .goal{display:block}` → **关 JS 时八个入口的全部文字都在页面上读得到** |
| `.prompt-box` `.copy-btn` | 可复制的第一句话（原来就有，换成本站视觉） | 无 JS 时复制按钮隐藏（`.js-only`），长按/选中手动复制即可，`<noscript>` 里明说了 |
| `.steps` `.checkpoint` | 三步兜底路径的编号列表与检查点 | 同上，全静态可见 |

行为层照抄基线 FS:670-790 的三件事（逐行浮现 + `.head.is-stuck`/`.progress` + 抽屉），
外加本站原有的两件事：入口行折叠（替代 `.goal-panel` 的 `toggleGoal`）与一键复制
（`navigator.clipboard` → `execCommand` → 失败时如实说"没复制上"，不谎报）。
`prefers-reduced-motion` 全量归零；SVG 环境动画周期 16/19/23/27/31s，全部 ≥9s；
`@media (max-aspect-ratio:27/20)` 换竖构图；深链 `#write #web #find #organize #photo #poster #ocr #start` 保留。

---

## 4. 删掉的外部声明台账（BLOCKING INTEGRITY）

规则来源：`AGENTS.md` §3「内容诚信」+ `PRODUCT.md` §8「不得虚构资源的…价格、维护状态」。
处理方式：**页面上直接把价格／免费断言删掉**，在面板原有的"限制"槽里换成一句诚实的限制说明；
不复述成一条新的未核实断言；工具推荐本身保留（那是真实产品能力）。
无法核实的按钮／菜单名字一律改写成**动作描述**。

### 4.1 规范点名的四条

| # | 原始断言 | 证据位置 | 页面原发布位置（`HEAD:web/index.html`） | 现在 |
|---|---|---|---|---|
| 1 | 稿定「免费模板够用」 | `catalog/resources.json:136`（`cost_category`）· `:147`（`why_selected`） | `:205`「挑一张**免费**模板」· `:206`「如实说：**免费模板够用**；…」 | 「挑一张模板 → 换字换图 → 下载」；Limits 改为「哪些模板能用、要不要付费，以对方页面为准，我们不替它保证。」+ 保留「部分模板导出带水印，商用先看它的授权说明」 |
| 2 | 豆包 无限定「免费」 | `catalog/resources.json:19`（`cost_category`）· `:34`（`why_selected`） | `:332`「✅ 国内直接打开 ✅ 全中文界面 ✅ **免费**」 | 删掉「免费」，Limits 改为「额度与价格会变，进去先看它自己首页的说明。我们不替它保证。」（写点东西 + 三步兜底两处） |
| 3 | 醒图「免费修图」 | `catalog/resources.json:181`（`one_line`）· `:191`（`cost_category`）· `:202`（`why_selected`） | `:232`「装「醒图」，**免费**够用：滤镜、调色、消除路人」 | 「**醒图**（字节出品，中文，手机端门槛最低）：滤镜、调色、消除路人」；免费断言并入统一 Limits「谁的额度多大、哪些功能要会员、起价多少，以对方页面为准」 |
| 4 | DeepSeek 旧按钮名「深度思考」/「联网搜索」 | `paths/step-3-find-answers.md:11` | `:273`（查明一件事面板）· `:368`（第三步） | 改成动作描述：「先在输入框附近找有没有能打开「联网找资料」和「想得更深」的开关——**名字可能会变**，找不到就直接把问题发出去，也可以。」 |

### 4.2 同一规则顺带清掉的价格／免费断言（同源风险，非规范点名的四条）

| 断言 | 原页面位置 | 现在 |
|---|---|---|
| OCR「微信和手机自带就能做，**免费**」 | `:185` | 改为「不用装任何新 App」——这是真实能力，不是价格 |
| 照片「手机自带的就够，**还免费**」 | `:219` | 同上 |
| 「iPhone **免费**只有 5GB」 | `:225` | 删。备份那条只说「先用手机自带的云相册」 |
| 一刻相册「宣传**免费**无限空间」 | `:226` | 只保留可核实的出品方与能力：「百度网盘团队出品，带相似图清理」；风险句改为「重要照片存两个地方。网上有备份丢照片的投诉」 |
| v0「**免费**能开始，用量大了要付费」 | `:261` | 删价格分句，并入「用量与价格以对方页面为准」 |
| 「PDF 文件用**免费**软件处理，都不用花钱」 | `:286` | 「PDF 文件用桌面工具处理，文件不上网」 |
| Stirling PDF「**免费**桌面软件」 | `:292` | 「桌面版在自己电脑里跑，文件不用上传」（这是选它的理由，不涉及价格） |
| 照片书「十几元**起**」／Photobook China「157 元**起**」 | `:229` | 两个价格数字删掉，工具与「要更好的纸质和装帧可以再搜 Photobook China」保留 |
| DeepSeek「✅ **免费** ✅ 全中文 ✅ 国内直接打开」 | `:367` | 与 #2 同一处理：删免费，Limits 加「额度与价格会变，进去先看它自己首页的说明。」 |

**未改动**：`catalog/resources.json` 与 `paths/` 是本轮 scope 之外（不许动），所以上面的
file:line 是"这些陈旧断言的出处"，不是"我改过的地方"。目录本身仍是真源，`last_reviewed_at`
记着最后一次逐条复核时间。下一次单独一轮应当把 `cost_category`／`why_selected` 里
「够用」「免费」的无限定表述一并修掉，否则陈旧断言会随目录回流到页面。

---

## 5. Reality Marker 取证（Beat 06）

页面上写的三条 `.mrow`，每条的出处：

| 断言 | 出处 |
|---|---|
| 「公开的是一页静态 HTML（GitHub Pages + 自己的域名）· 无账号、无后端、无数据库」→ `Testing` | `CURRENT_STATE.md:11-16`（Runtime=纯静态 HTML、无后端；Deployment=GitHub Pages，CNAME=`ymai.fun`）· `CURRENT_STATE.md:52`「无后端、无数据库、无 AI runtime、无账号系统、无 CI/CD、无构建系统」· 本分支 `git ls-files` 只有 `web/index.html` 一个页面文件，无 `server/`、无 `web/v2/` |
| 「八个入口的默认工具、第一步、限制，都写在页面上，不替你执行任何一步」→ `Exists` | `web/index.html` 本文件 §2；`PRODUCT.md §0`「我们不制造能力」+ `§7`「可以引用，不必集成」 |
| 「不存你做的东西、不托管你的网站、不代你调用任何模型」→ `None` | `CURRENT_STATE.md:52`（无后端无数据库）+ `web/index.html` 的 CSP `default-src 'none'; connect-src 'none'` |
| 「最后一次逐条复核是 2026-09-06 到 2026-09-11 之间」 | `catalog/resources.json:3`（`last_reviewed_at: 2026-09-07`）· 各条 `pricing_checked_at` `2026-09-06/07` · `:63` `:120` `:148` `:175` `:203` 的 `last_reviewed_at` 最晚 `2026-09-11` · `CURRENT_STATE.md:3`「最后更新：2026-09-11」 |
| 「目录里写着这些工具『国内可直接打开』，但仓库里没有留下从境内网络实测的记录」 | `catalog/resources.json` 每条 `"china_accessibility": "direct"`（如 `:23` `:55` `:82`）；本仓库无一条实测记录（`grep` 无境内网络/拨测证据，`CURRENT_STATE.md` 亦无） |

`.stamp`：`Reality as of · 2026-09 · static v1 · last supply check 2026-09-06 — 2026-09-11`。

**本轮核查修正了两条交下来的前提**（写在这里，免得下轮又照抄）：
1. `README.md` 只有 50 行，没有 88–91 行；`docs/CAPABILITY_SUPPLY_BASELINE_20260919.md`、
   `CONSTITUTION.md` 在本仓库不存在（`find` 全仓无匹配）。诚信约束的可引用出处是
   `AGENTS.md` §3 与 `PRODUCT.md` §8，四条陈旧断言的 file:line 已逐条复核成立。
2. 「8–12 天保质期」这条政策在本仓库没有文字记录。页面因此**不写政策**，只写可核实的
   复核日期区间。

### 5.1 ICP 备案：**不渲染**

全仓（排除 `archive/` 与 untracked `eval/`、`var/`）grep `ICP|beian|备案`：
唯一命中是 untracked `eval/out/pilot12-replay.md:980` 把 `https://beian.miit.gov.cn` 当成
"官方查询入口"举例，**不是本站域名的备案号**；且同文件 `:1007` 明确记着
「ICP 备案（面向中国大陆提供服务的网站前置要求）：高风险结论的证据未获授权，按 admission 规则删除」。
备案号后缀是按域名发的，写错比不写更糟 → **footer 不放备案号**，本条为决策记录。
（对照：`Family-Space/website/index.html:641` 有 `陕ICP备2026014869号-1`，那是 ymai.love 的后缀，
不可复用。ymai.fun 走 GitHub Pages + `CNAME`，托管在境外，是否适用备案本身也没有核实过。）

---

## 6. 字体：`web/build-font.py`（本轮走的是"联网重新子集"主路径）

- 移植自 `MingOS-web/tools/build-font.py`：Google Fonts 分片 → 按 `unicode-range` 取片 →
  逐片 `fontTools.subset` → `fontTools.merge` → 整体再子集 → 规整 `name` 表与 `usWeightClass`。
  逻辑未改，只换输入为单文件 HTML，并加「内联回写 + 缺字审计」两步。
- 读 `web/index.html`，从 `<body>` 起、剥掉 `<script>`/`<style>`/标签，取 `ord(c) > 127` 的字符。
- 结果整块写回 `/* MING-FONT:BEGIN */ … /* MING-FONT:END */` 之间 → 字体是**内联 base64**，
  页面仍然是零外部请求、零构建步骤（脚本是离线一次性工具，不进发布路径）。
- `web/FONT-LICENSE.txt` = SIL OFL 1.1 全文（照 `Family-Space/website/FONT-LICENSE.txt` 拷贝），
  随字体同行。家族保留名 **"MingOS Serif" 未改**。

本轮真实输出（改完文案后重跑的最终一次）：

```
页面需要 582 个非 ASCII 字符
共 101 个分片，需要其中 20 个
最终字体: 99248 B  字形 583
页面非 ASCII 字符 582 个，字体覆盖 582 个
MISSING GLYPHS (0)：无缺字
已内联回 index.html（+132530 B base64）
```

**没有走兜底路径**（`--fallback` 抽 Family-Space 内联子集）。兜底已实现并实测，其审计是
`MISSING GLYPHS (373)`——那份子集不是按本页文案切的，覆盖率只有 208/582。留着是为了以后
拿不到网络时仍能出可用页面并强制打印缺字清单。

---

## 7. 未决

1. `MING_SKELETON.css` 的 `.head.is-stuck` / `.hero-scrim` / `.scrim` 把基线墨色写成字面量，
   每站得手抄替换（§1.1）。建议下一轮骨骼修订改成 token。
2. `catalog/resources.json` / `paths/` 里那四条陈旧断言仍在原地（本轮不许动）。目录是"真源"，
   不改就意味着下次照抄会回流。需要单独一轮。
3. `docs/goal-coverage.md` 与 `CURRENT_STATE.md` 仍按「7 个目标 + 1 个兜底」计数描述首页，
   本页把兜底算作第 8 行入口。语义一致（8 行 = 7 目标 + 1 兜底），但字面表述建议下一轮对齐。
4. `AGENTS.md` §7 要求每轮 commit 并 push；本轮由编排方统一提交，工作树留在本地未推送。
5. 四宽度（375/390/768/1440）真机截图对比未做：本地无 headless 浏览器，
   起站后的可视化验收留给编排方。已做的静态核验见 §8。

---

## 8. 本轮核验记录（全部实际执行）

```
$ python -m http.server 8090 --directory .        # 仓库根
$ curl -s -o /dev/null -w "%{http_code} %{size_download}" http://localhost:8090/web/index.html
200 203962
（server 访问日志只有这三条：GET /web/index.html、GET /index.html、GET /web/index.html，无第三方请求）

$ ls eval/*-selftest.mjs
ls: cannot access 'eval/*-selftest.mjs': No such file or directory
$ ls eval/*.mjs
ls: cannot access 'eval/*.mjs': No such file or directory
→ 本分支（origin/main 同名树）不含任何 selftest / eval/frontend-e2e.mjs：
  eval/ 与 var/ 是上一分支遗留的 untracked 日志目录（只有 *.log/*.md/*.json），
  按要求完全未动。可跑的离线自检：0 个。需要网络／API Key／真实模型调用的：0 个（不存在）。

$ grep -c 每条禁令字符串 web/index.html
[免费模板够用] 0  [免费够用] 0  [免费修图] 0  [深度思考] 0  [联网搜索] 0
[免费无限空间] 0  [还免费] 0  [都不用花钱] 0  [免费桌面软件] 0
[永远免费] 2   ← 两处都是否定句「不假装某个工具永远够用、永远免费」，正是 §05 notlist 要求写的

$ grep -n 免费 web/index.html                       # 全文剩余三处，均为否定／诚实句
879:      <li>不假装某个工具永远够用、永远免费。</li>
912:      没核实过的：… 价格、免费额度、按钮名字是变得最快的部分——所以我们把它们从页面上删掉了…
1009:    <li>不假装某个工具永远够用、永远免费。价格与按钮名字以对方页面为准。</li>

零外部资源加载
$ grep -o "url([^)]*" web/index.html | cut -c1-42 | sort | uniq -c
      1 url(data:font/woff2;base64,d09GMgABAAAAAYO   ← 内联字体
      1 url(#fadeOutL  1 url(#doorGlowS  1 url(#doorGlowL
      1 url(#dayOutS   1 url(#dayOutL               ← SVG 同文档渐变
$ grep -c "script src\|@import" web/index.html
0
$ grep -n "<link" web/index.html
19:<link rel="icon" href="data:image/svg+xml,…>     ← data: 内联，非网络请求
$ grep -noE ".{0,26}https?://[^\"' )<]{0,30}" web/index.html | wc -l
18
→ 18 处 http(s) 的构成：15 处 <a href>（走出去的出口：doubao×4 / v0 / deepseek×2 /
  gaoding / stirling / doubao 图片生成 / mingos×3 / ymai.me / ymai.love）、
  1 处 <meta property="og:url">、1 处 favicon data-URI 里的 xmlns、1 处 head 注释。
  无一处是资源加载。

结构与可访问性
$ python html.parser 校验           unclosed: []   errors: []
$ 重复 id                           []
$ aria-controls 8 个目标            全部命中页内 id
$ href="#…" 页内锚点                 #entrances #main 全部命中
$ node --check 两段内联 <script>    均 syntax OK
$ 入口行数 / 可复制框数             8 / 8（= 7 个目标 + 1 个三步兜底）
```
