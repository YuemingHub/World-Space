# World Space · 收敛 + fixture + 大陆实测统一报告（2026-09-19 第二轮）

> 一句话：**candidate 树已生成待审；三个 fixture 全部跑完，没有一个能把结论推到"普通人已经可以"；
> 大陆网络实测第一次有了硬证据；真人仍然是 0。**
>
> 本轮**不是产品功能开发**。未部署、未切默认分支、未合并进 main、未接触任何真人。

---

## A. Canonical Candidate

### A1 基本信息

```text
candidate branch : candidate/world-space-canonical-20260919
final SHA        : （本报告提交后填入，见 A7）
来源关系          : research @ c6a3486（底）
                    ├─ merge --no-ff v2   @ e8284c4   （生产代码）
                    └─ merge --no-ff main @ 205df01   （仓库基础设施）
收敛方法          : merge --no-ff（保留全部历史，未 cherry-pick、未 replay、未改写任何提交）
```

为什么用 merge 而不是别的：三条分支的共同祖先清楚（`v2` 与 `research` 的 merge-base = `c500f3d`；
`main` 与二者的 merge-base = `6e41b48`），三方合并没有歧义，也不需要重放历史。
**禁止为了方便覆盖历史**，所以没有 rebase、没有 squash、没有 force push。

### A2 相对 v2 @ e8284c4 的代码差异

```text
git diff e8284c4 HEAD -- server/ web/v2/ eval/
→ 空
```

**零差异。** 生产代码逐字节等于当前线上批准点。
（合并实际带入三项：`server/search.mjs`、`server/world.mjs`、`eval/search-key-failover-selftest.mjs`
——它们正是 `v2` 上比 `research` 新的那部分：搜索备用钥匙 failover。research 分支上的是旧版。）

### A3 相对 research @ c6a3486 的文档差异

```text
git diff c6a3486 HEAD -- research/ docs/ CONSTITUTION.md CURRENT_STATE.md PRODUCT.md AGENTS.md
→ 空（在收敛动作完成的那一刻）
```

**收敛本身零差异。** 本轮之后新增的内容全部是**追加**，不是改写旧结论：

| 文件 | 性质 |
|---|---|
| `docs/CAPABILITY_REACH_LAB.md` §21–§24 | 追加（Path A 协议、Path B checklist、第二研究轴、降级纪律） |
| `CURRENT_STATE.md` §6 | 追加本轮事实 |
| `NEXT_CANDIDATES.md` | 只给 NC-09 加处置状态，原文一字未改 |
| `research/capability-reach/WAVE1-PACK.md` | 新建（纸面准备） |
| `research/capability-reach/fixtures/*` | 新建（A/B/C 三个 fixture 的脚本与结果） |
| `catalog/README.md` | 新建（冻结声明 + 四字段规则） |
| 本报告 | 新建 |

### A4 相对 main @ 205df01 的基础设施差异

```text
git diff 205df01 HEAD -- .cnb.yml .github/
→ 空
```

**完整保留。** `main` 独有的 cnb 双向同步配置与 GitHub Actions 工作流都在树上。
唯一冲突是 `.gitignore`（`main` 加了本地工作目录忽略，`research` 加了研究目录拦截），
已取**并集**解决，两边规则都在。

### A5 历史 release 记录是否仍可追溯

| 分支 | 在 candidate 历史里？ | 处理 |
|---|---|---|
| `release/v01-c500f3d @ 7911239` | **是**（research 的祖先） | 随历史带入 |
| `release/v0-85c7b91 @ 2e37b84` | **否**（独立归档分支，不在任何主链上） | **未强行并入**。它是 V0 归档，代码与现行 V0.1 差异巨大，合并会污染树。仍以远程分支形式可追溯 |

### A6 是否存在行为变化

```text
无。
```

- 生产代码与 `e8284c4` 逐字节一致（A2）；
- 本轮**未部署**：未登录生产、未使用任何凭据、未改 env / nginx / systemd、未切流；
- 未改 `main` 的默认分支地位；
- 未把 candidate 合并进 `main`。

### A7 待审

```text
本分支是"候选"，不是既成事实。
切默认分支 / 合入 main，都属 Founder 决定（NC-01），本轮一条都没做。
```

---

## B. Fixture Findings

三个 fixture 全部只使用**本地 / 免费**能力，未消耗任何生产预算与凭据。
证据等级统一是 **Machine / Operator Evidence**。

### B1 · A 数字截图 → OCR / 结构化表格

| 项 | 内容 |
|---|---|
| 输入 | 虚构费用明细截图，5 行 + 合计；埋 8/3、0/O、1/l、日期、小数点、千分位、相似人名 |
| 能力 | 本地 PP-OCR（rapidocr-onnxruntime 1.2.3），纯离线 |
| 画质 | v1 clean / v2 jpeg45（微信压缩）/ v3 lowres（缩略图） |
| 错误形态 | v1：空白插入（无害）；v2：`8,300.00 → 8.300.00`（逗号变小数点）；v3：三个日期连字符消失（`2026-09-16 → 20260916`） |
| 是否显眼 | v1 显眼无害；v2 半显眼；**v3 不显眼**（像一个合法编号，只有与同列对照才发现格式不一致） |
| Verification | 重算合计能抓 v2（差 8291.70），**抓不到 v3**；逐列看格式一致性能抓 v3，但要"想到去看" |
| Operator 结论 | `TECHNICAL_FEASIBILITY` + `OPERATOR_OBSERVATION` |

详细：`fixtures/RESULTS-ocr-tables.md`

### B2 · B 公开音频 → 转写

| 项 | 内容 |
|---|---|
| 输入 | 自生成虚构中文语音（TTS），埋中文数字、长数字串、小数点、同音"零/欧" |
| 能力 | 本地 sherpa-onnx + paraformer 中文模型，纯离线 |
| 错误形态 | 标点全丢；"欧"→"哦"（同音替换）；**数字全部保持中文形式**（八千三百 / 一百零三点五） |
| 是否显眼 | 标点丢失显眼；同音替换**不显眼**且改了语义；中文数字显眼，但"想录入表格时"才成为问题 |
| Verification | 只能回听对照——**等于把录音重听一遍**，正是用户想省掉的力气 |
| 关键发现 | 对转写输出做 `/\d+/` 提取阿拉伯数字 → **（无）**。转写完成了，可用数据没产生 |
| Operator 结论 | `TECHNICAL_FEASIBILITY` + `OPERATOR_OBSERVATION` |

详细：`fixtures/RESULTS-asr-audio.md`

### B3 · C 手写页 → OCR

| 项 | 内容 |
|---|---|
| 输入 | 虚构手写便条（楷体 + 逐字抖动近似工整手写），埋 l/1、O/0、日期、小数点、相似人名 |
| 能力 | 同一个本地 OCR |
| 画质 | v1 clean / v2 photo（手机随手拍） |
| 错误形态 | v1：`l03.50 → "103 50"`（小数点变空格，有破绽）；**v2：`l03.50 → "10350"`（小数点彻底消失，差 100 倍，完全合法）**；`l38OOl3lO08 → 13800131008`（全对）；"不是字母 O"→"不是字母0"（语义反转） |
| 是否显眼 | `10350` **不显眼**；语义反转**不显眼**；全对的手机号当然也不显眼 |
| 最值得记的一条 | **画质越差，错误越干净**——引擎输出"最可能成立的合法串"，合法就意味着不像错的 |
| Verification | 手写便条**没有合计行可兜底**，只能靠常识量级校验（两袋水泥不可能一万块）或逐条回看 |
| Operator 结论 | `TECHNICAL_FEASIBILITY` + `OPERATOR_OBSERVATION` |

详细：`fixtures/RESULTS-ocr-handwriting.md`

### B4 三个 fixture 的共同结论

```text
没有一个是"做不到"。
三个都是"做得到，但产出物里藏着不会报错的错"。
```

重复出现的形态是同一个：

```text
错了，但看起来合法——
所以不会触发任何"这里有问题"的信号。
```

而普通人现实可行的 Verification，只有两类：

```text
1  结构性兜底（重算合计）  —— 只在有合计的场景存在，且只覆盖金额
2  逐条回看              —— 可行，但就是用户想省掉的那份力气
```

这**不能**被解读为"World Space 应该做 Verification"。按 Lab §24，它目前只是
`Suspected Structure`，等真人重复证据。

---

## C. Mainland Reach

```text
MAINLAND_NETWORK_TEST = DONE
```

### C1 先证明这个测试站得住

| 项 | 值 |
|---|---|
| 代理环境变量 | `http_proxy/https_proxy = http://127.0.0.1:56993` |
| **绕过代理直连**出口 | `1.80.234.204` → 中国 陕西 西安 电信 |
| 走代理出口 | 同一个 `1.80.234.204` |
| 结论 | 两者一致，**本机真实位于中国大陆网络**，不是用境外代理冒充 |

### C2 实测结果（2026-09-19，中国电信陕西西安，直连）

| 入口 | 直接打开 | 备注 |
|---|---|---|
| `claude.ai` | **HTTP 200，但页面是 `App unavailable in region \| Claude by Anthropic`** | 硬证据：明确地区不可用 |
| `chatgpt.com` | 连接失败（000） | 不可达 |
| `gemini.google.com` | 连接失败（000） | 不可达 |
| `www.doubao.com` | 200 | 页面命中"登录/App"字样 |
| `chat.deepseek.com` | 200 | 页面命中"App" |
| `yuanbao.tencent.com` | 200 | 命中"下载/不支持"字样 |
| `tongyi.aliyun.com` | 200 | 命中"验证/付费/地区"字样 |
| `ymai.fun` | 200 | 我们自己的生产入口 |

### C3 逐格回答

| 要记录的格 | 结果 |
|---|---|
| 直接浏览器能否打开 | 国内 4 个全部 200；境外 3 个中 2 个连不上、1 个明确地区不可用 |
| 微信内打开是否正常 | **UNVERIFIED** —— 本机没有可自动化的微信客户端。用微信 UA 请求只得到 200，**UA 模拟不构成真机证据**，故不填这一格 |
| 是否必须特殊网络 | 国内 4 个**不需要**；境外 3 个需要（其中 Claude 即使有网络也按地区拒绝） |
| 是否强制登录 | 未逐项实测到"强制"级别；页面含登录/验证入口（豆包命中"登录"，通义命中"验证"）。**判定强度：页面存在登录入口 ≠ 强制登录**，本轮不下强结论 |
| 是否强制下载 App | 未实测到强制；豆包/元宝/通义页面含 App 引导字样。**同上，不下强结论** |
| 是否需要付费才能进入关键能力 | **未测到付费墙**：是否能"免费用到关键能力"要在真实交互里跑，本轮只做了匿名 GET |

### C4 这条实测证明了什么 / 不证明什么

```text
证明了：境外入口在中国大陆普通网络下不可及（Claude 是明确地区拒绝）。
不证明：国内没有替代品。
不证明：国内替代品更好或更差。
```

---

## D. Path A Candidate Protocol（完整冻结文本）

> 完整版已写进 `docs/CAPABILITY_REACH_LAB.md` §21，此处全文复述以便审查者不必跳文件。
> **状态：`PROTOCOL CANDIDATE`。冻结 ≠ 批准。**

### D1 第一原则

```text
Path A 测的不是"哪一款模型更强"。
Path A 测的是：一个普通人在现实条件下，把自己那句原话直接交给一个通用 AI，能走多远。
```

禁止：品牌 Benchmark、模型横向评分、为结果好看挑更强的模型或入口、把"谁赢了"当结论。
重点是：**这个人有没有真的开始，有没有拿到第一次真实结果。**

### D2 用哪个 AI

```text
如果参与者平常已经在使用某个通用 AI：
    → 用他自己最常用的那一个，用他自己平常的入口、他自己的账号、他自己的页面状态。

如果参与者从不用任何通用 AI：
    → fallback：豆包免费版，默认普通对话。
```

禁止：研究者替他挑更好的；因为"这个更强"临时换；换成 Agent/工作流/深度研究/编程模式；
换成研究者的账号（连登录态和历史记忆一起换掉，那就不是他的现实）。

### D3 执行纪律（八条）

```text
1  用参与者自己的设备，不是研究者的设备
2  由参与者自己操作；研究者不得代点、代输、代粘贴
3  原话逐字输入：Raw Reality 那一句，不改写、不润色、不补背景
4  研究者不得改 Prompt，不得追加"请详细说明""请给出步骤"
5  不主动切换 Agent / 工作模式 / 深度思考 / 联网开关
6  最多自然追问 3 轮；追问必须是参与者自己想问的
7  研究者不得替他点"继续 / 重试 / 换一个"
8  研究者不得解释下一步该怎么做
```

违反任意一条 → 本 Case 的 Path A 作废，要么重来，要么如实记为"已被研究者污染"。

### D4 必须记录的九格

```text
产品 / 版本 / 页面状态（含是否登录、哪个模式）
是否付费（免费版 / 会员 / 按次 / 试用）
用户的原话（逐字）
AI 的实际回复（原文保留，不摘要）
用户的真实动作（做了什么，或明确地没做什么）
卡点（哪一步停住，停了多久，他说了什么）
第一次结果（有没有产生外部可观察的东西）
Verification（他自己怎么判断对不对；没能判断就写"没判断"）
时间（从输入到第一个结果 / 到放弃，多少分钟）
```

### D5 Global AI 的位置

```text
Global（境外）通用 AI 只作为 Supply Baseline。
不进入中国真人 Path A 的分母。
不得合并统计、不得互相折算、不得互相补位。
```

（C 节实测：`claude.ai` 在中国大陆返回地区不可用——这就是 Global 不能进中国分母的现实理由。）

### D6 仍然没批

```text
2 · 真人从哪来          STILL FOUNDER-DECISION
3 · 是否录音/谁持原件     PROPOSED（Wave 1 先不录音，见 F 节）
4 · 研究者是谁           STILL FOUNDER-DECISION
5 · 预算与停线           PROPOSED（沿用 50 次/日、¥20/月）
```

**在总审查确认 candidate 树之前，即使本节被批准，也不开始第一个真人 Case。**

---

## E. Path B Operator Checklist

> 完整版见 Lab §22。核心一句话：**World Space Method 不是"研究者更聪明"。**

### E1 研究者只能做六件事

```text
识别 Capability Gap
查现成能力（世界上本来就有的）
选择最低阻力路线
翻译成第一步
帮助用户进入
帮助定义 Verification
```

### E2 研究者禁止做六件事

```text
替用户做完
替用户决定（目标、是否公开、是否付费、是否继续）
临场写一个定制程序来赢 Path A
不断鼓励用户继续
解释为什么 World Space 更好
修改用户最初的目标
```

### E3 判定规则

```text
如果只有靠研究者的大量专业服务才能胜出 → SERVICE_SIGNAL
不得判 → PRODUCT_SIGNAL
```

`SERVICE_SIGNAL` 不是失败，是诚实结论：它指向服务形态而非产品形态（Lab §15 结论 C）。

### E4 每一处代做都要标注

```text
谁做的：研究者代做 / 用户自己做到
```

把代做记成做到 → **本 Case 作废**（它直接污染 `Next Time` 那一格）。

---

## F. Human Wave 1 Pack

> 完整版见 `research/capability-reach/WAVE1-PACK.md`。状态：**PREPARED — NOT EXECUTED**。

```text
规模      2 人 × 1 件事，只挑 VERIFICATION 型
目标      不是得结论，是验证 Case 协议本身能不能跑
```

**开场一句**（不提 AI）：

> 最近有什么事情，你已经觉得麻烦很久，但一直就这么做？

**数据方式（Mission 6：第一轮不录音）**：

```text
让参与者在自己的手机备忘录 / 输入框里，亲手写一句上面那句话。
他自己写的那一句就是 Raw Reality。
原件留在他设备上，不传、不存、不截图进仓库；仓库只进脱敏后的必要摘录。
```

这样同时解决：不录音、隐私面最小、**研究者没有转写机会所以不可能改写原话**、Path A/B 输入一致。

**Case 操作顺序**：开场 → 写 Raw Reality → 问现状 → Path A（八条纪律）→ 记九格 →
Path B（六件事/六禁止）→ 记九格 + 标注代做 → Verification → Before/After → "以后再遇到类似事情你会怎么做"。

**停止条件（命中即停）**：参与者不想继续 / 涉及医疗法律投资心理危机或他人隐私 /
需要上传身份证银行卡通讯录他人照片 / 研究者在替他操作 / 研究者在临场写程序 / 参与者要求代做。

**强制停线**：

```text
Wave 1 跑完必须停。
不允许自动扩到 6 人 × 2 Case。
不允许因为"才两个人说明不了什么"而继续加人。
扩规模的权力在总审查，不在研究者。
```

---

## G. Possibility Expansion（只登记研究轴，不造 Case）

> 完整版见 Lab §23。

### G1 为什么立这一条

§6 那 8 条 Pressure Seeds **全部**属于 `Friction Reduction`（把已在做的事做省一点）。
只沿这 8 条研究下去，World Space 会被研究成"办公效率 / 数字整理"工具。
这不是结论，是**种子选择本身造成的偏差**。

### G2 第二条轴研究什么

```text
Possibility Expansion
一个人原本根本没有能力实现、甚至不会认真考虑去实现的事情，
因为这个时代的新能力，现在第一次成为可能。
```

| | Friction Reduction | Possibility Expansion |
|---|---|---|
| 起点 | 他已经在做，只是烦 | 他根本没想过这件事可以做 |
| Before | 我知道要做，只是累 | 我以为这不属于我 |
| 失败形态 | 半途而废 | 从没开始，因为没起过念头 |

### G3 候选形态（只是方向，不是需求）

```text
孩子想做自己的小游戏
普通人想把自己的故事做成作品
老人想把几十年的材料变成一本家庭书
不会设计的人想把一个真实想法变成可见作品
```

### G4 硬纪律

```text
没有真人原话之前：不建立 Case、不写"需求已存在"、不开发任何功能。
```

上面四行**不得**被引用为"用户需要这个"。

### G5 未来要证伪的问题（现在不回答）

```text
Q1  普通人在没有外力提示时，会不会自己起这个念头？
Q2  起了念头之后，卡住的是"不知道能做"还是"不会开始"？
Q3  做出来之后，它留在生活里了，还是只是一次新鲜？
Q4  这一类与 Friction Reduction 类在 Barrier 分布上是不是真的不同？
Q5  如果 Direct AI 已经能让人起念头，这一轴还剩什么？
```

---

## H. Reality Boundary

```text
REAL HUMAN CASES = 0
H1 = UNRESOLVED
H2 = UNRESOLVED
H3 = NOT YET TESTED
V0.2 DEVELOPMENT = NOT AUTHORIZED
PRODUCTION DEPLOYMENT = NO
```

补充六条同样不许省略的边界：

```text
本轮全部证据等级        Machine / Operator Evidence（研究者跑通 ≠ 普通人跑得通）
ORDINARY_REACHABLE 宣布次数  0
已招募的真人            0
已发出的邀请            0
默认分支是否切换         NO（main 仍是默认分支）
candidate 是否合入 main   NO
生产代码是否被改动        NO（与 e8284c4 逐字节一致）
```

**本轮到此停止。**
不进入 Wave 1，不修改生产，不切默认分支，不合入 main。等总审查。
