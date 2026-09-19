# 单个真人 Case 记录模板

> 严格继承 `docs/CAPABILITY_REACH_LAB.md` §10。字段名、顺序、可选值都不许自行增删——
> 跨 Case 可比是这次实验唯一值钱的地方。
>
> 用法：复制本文件为 `cases/C01-A.md`，逐节填写。**没有真人就不要复制它。**

> ## ⚠️ 本文件是 Public Research Record（会进公开 Git）
>
> ```text
> 真人原话摘录 ≤ 25 字
> 不得含姓名 / 单位 / 手机号 / 微信号 / 住址
> 不得含真实文件名 / 私人 URL / 账号标识
> 不得上传真人原始文件
> ```
>
> 完整 AI 对话、原始文件、完整原话 → 只归 Private Session Evidence（见 `DATA_BOUNDARY.md` §3）。
> 违反以上任何一条，**这个 Case 不得 commit**。

---

## CASE ID

`C__-_` ｜ 记录日期：YYYY-MM-DD ｜ 记录人：＿＿ ｜ 状态：NOT_STARTED / BASELINE_DONE / PATH_A_DONE / PATH_B_DONE / RESULT_VERIFIED / CONCLUDED / VOID

### Person

> 只允许 Lab §10 的四项。不得为画像收集无关个人资料。姓名 / 单位 / 手机号 / 微信号 / 住址一律不写。

- 年龄段：
- 技术熟悉程度：
- 常用设备：
- 与本任务相关的必要背景：

### Raw Reality

> **采集方式**（Lab §10）：研究者口头问「最近有什么事情，你已经觉得麻烦很久，但一直就这么做？」；
> 参与者想到之后，研究者只说「请用你自己的话，在你的手机上写一句刚才想到的那件事，怎么说都行，不用整理」。
> **参与者写下的答案**才是 Raw Reality。研究者的问题不是。
>
> 研究者不得改写、总结、补背景、提供示例答案、建议怎么表达。
> 一个字都替他改，Path A 就失效了。
>
> **完整原文属于 Private Session Evidence；本格只写脱敏后的必要摘录（≤25 字）。**

「……（≤25 字必要摘录，不含可识别信息）」

### Current Method

（他现在到底怎么做，一步一步照实写）

### Current Cost

- 时间：
- 重复次数：
- 金钱：
- 放弃 / 拖延：
- 需要别人帮助：

> 只记可观察成本，不强行货币化。

### Capability Gap

```text
exists: YES / NO / UNKNOWN
```

- 过去认为不能 / 很难做到什么：
- 今天实际上已经可以做到什么：
- A/B/C 三条件是否同时成立（Lab §4）：

### Direct AI Result（Path A）

- 用的哪个产品（按 Wave 1 已批准口径，见 `docs/CAPABILITY_REACH_LAB.md` §21）：
- 输入是否为**原话逐字**：YES / NO（NO 则本 Case 的 A 臂作废）
- 它给了什么路径（**只写脱敏摘要；完整回复留在 Private Session Evidence，不进 Git**）：
- 用户是否看懂：
- 用户是否开始：
- 是否完成：
- 真实卡点（原话）：

### Adoption Barrier（允许多项，必须附现实证据）

```text
DISCOVERY / RELEVANCE / SELECTION / TRANSLATION / ACCESS / TRUST / VERIFICATION / INTEGRATION / NONE / OTHER
```

- 判定：
- 现实证据（他做了/说了什么，或哪一步停住了）：

### World Space Route（Path B）

- 选择了什么现成能力：
- 为什么不是更强的那个：
- 为什么这条路线**对这个人**阻力最低：
- 是否借用了现成能力（必须是）／有没有自己重新开发能力（不得有）：

### Activation

- 用户需要提供什么：
- 机器承担什么：
- 人自己决定什么：
- 第一次只做哪一步：

### First Real Result

> 必须外部可观察。写"用户了解了自动化"= 本节不合格。

- 结果物（**只写结果类型**，例如：`生成 1 个合并后的 xlsx` / `生成 1 份转录文本` / `生成 1 个可打开页面`）：
- 达成时间（真实耗时）：
- 是不是他自己做成的：

> ⚠️ **不得写**：真实文件名、私人链接、私人照片路径、账号标识、私人 URL。
> 如确有私人结果文件，**只留在参与者设备 / Private Session Evidence**。

### Verification

- 怎么确认结果真的正确（谁核的、核了什么、发现过错没有）：

### Before / After

> **只放必要脱敏摘录，每段 ≤25 字。**
> 完整原话如需保留，只能存在 Private Session Evidence，不进 Git。

- Before（他原来的能力认知，脱敏摘录 ≤25 字）：
- After（用后变化，脱敏摘录 ≤25 字）：
- 是否出现「原来这个我也可以」：**记录原话或写"未出现"**。禁止诱导他说这句。

### Next Time

> **只放必要脱敏摘录 ≤25 字。**

- 问：「以后再遇到类似事情，你会怎么做？」
- 答（脱敏摘录 ≤25 字）：

> 这一格区分"用了一次 AI"与"获得了能力"。

### 证据留存声明

```text
RAW_AI_RESPONSE_RETAINED: YES / NO
Private Session Evidence 持有人: 参与者本人设备 / Founder 私有本地空间 / 未保留
```

> 若未保留，只写 NO 即可，**不需要为了研究去补建一份**。

### 裁决输入（供 Lab §15 汇总用）

> **这不是 A/B 对照**（Lab §9）。只能写 remainder 句式，不许写谁赢。

```text
WORLD_SPACE_REMAINDER: NONE / <具体哪道门>
Path A 停在: <X>            （若 remainder = NONE 则写"已自然解决"）
Path B 是否消除了 X: 消除 / 未消除 / 未进入 B
Reach state（Lab §13，缺真人证据一律 UNCONFIRMED）:
一句话结论:
```

禁止出现：「B 战胜 A」「World Space 比某模型强」之类的表述。
