# Wave 1 Pack — 只准备，未执行

> **状态：`READY — WAVE1 EXECUTION = APPROVED`（范围严格限定：2 人 × 1 件事）。**
>
> 本文件是给"第一个真人 Case"用的操作包。**批准不等于已经开始**——
> 现在仍然 `REAL HUMAN CASES = 0`，下一步由 **Founder 去现实里找两个人**。
>
> 三道门都已通过：
>
> ```text
> 1  Path A 口径      PATH_A_PROTOCOL = APPROVED_FOR_WAVE1（§10）
> 2  candidate 树     CANONICAL CANDIDATE = APPROVED
> 3  Wave 1 执行      WAVE1 EXECUTION = APPROVED（仅 2 人 × 1 件事，不得扩大）
> ```
>
> 2026-09-19 先后修过五处协议问题：
> Raw Reality 采集（§3）、私有/公开证据分层（§4）、A→B 的实验语义（§5）、
> 参与者说明（§9.0）、公开 Case 隐私红线（`TEMPLATE.md` 与 `DATA_BOUNDARY.md` §3）。

---

## 1. 规模：先小到不能再小

```text
Wave 1 = 2 人 × 1 件事
```

不铺开四类障碍。第一批**只挑 `VERIFICATION` 型**的事：

> 意思就是：能力大概率已经存在、用户大概率能起跑，
> 但**拿到手的东西对不对，他自己判不了**。

这是当前四个候选里最可能重复出现、也最容易被"看起来完成了"掩盖的一类。

Wave 1 的产出**不是结论**，是对下面七格的回答：

```text
1  Raw Reality 能不能保持原话
2  Path A 会不会被研究者污染
3  Path B 是否执行一致
4  First Real Result 能否明确
5  Verification 是否可观察
6  Before / After 是否能真实记录
7  全程有没有被迫录音
```

七格里任意一格答不出来，就是**协议本身有问题**，先修协议，不许靠加人来凑。

---

## 2. 开场一句（不提 AI）

研究者只能说这一句，然后闭嘴：

> **最近有什么事情，你已经觉得麻烦很久，但一直就这么做？**

禁止的问法：

```text
✗ 你平时怎么用 AI？
✗ 你希望 AI 帮你什么？
✗ 你想自动化什么？
✗ 有没有什么想用 AI 解决的？
```

如果对方反问"这跟什么有关"，如实回答：

> 我们在看普通人身上的麻烦事，今天是不是已经有别的办法了。

不得在这一步解释 World Space、不得演示产品、不得打开 ymai.fun。

---

## 3. Raw Reality：问的是研究者，写的是参与者

> **修正（2026-09-19）**：上一版把"最近有什么事情你已经觉得麻烦很久……"写成让参与者
> 亲手打的那句话——那是**研究者的问题**，不是参与者的 Raw Reality。此处已改正。

第一轮**不录音**。分两步，别混成一步：

**第一步 · 研究者口头问**（就这一句，然后闭嘴）：

> **最近有什么事情，你已经觉得麻烦很久，但一直就这么做？**

**第二步 · 等他想到了，研究者只说这一句引导**：

> **请用你自己的话，在你的手机上写一句刚才想到的那件事。怎么说都行，不用整理。**

参与者**写出来的那一句（他的答案）**才是 **Raw Reality**。
不是研究者的问题，不是研究者的转述，不是整理后的版本。

研究者不得：

```text
✗ 改写
✗ 总结
✗ 补背景
✗ 提供示例答案（哪怕只是"比如整理照片"）
✗ 建议怎么表达
```

这样同时解决四件事：

```text
1  无需录音设备，无需录音同意
2  不产生原始音频，隐私面最小
3  研究者没有转写机会 → 原话不可能被他改写
4  Path A 可以直接复制同一句，A / B 两条路输入完全一致
```

**原件留在参与者设备上**，不传、不存、不截图进仓库。
仓库只进：脱敏后的必要摘录（按 `DATA_BOUNDARY.md`，另见本文件 §4）。

如果 Wave 1 跑完证明"不录音"拿不到可用的 Raw Reality（例如参与者不方便打字），
**停下来单独决策**，不许研究者临场改成"我帮他转述"——那等于改写原话。

---

## 4. 证据分两层：Private 与 Public

> **修正（2026-09-19）**：旧写法里有个自相矛盾——Path A 要求"AI 回复原文保留"，
> 而 `DATA_BOUNDARY.md` 禁止真人原始内容进公开 Git。这里把它们分开。

### 4.1 Private Session Evidence

由**参与者本人设备**或 **Founder 的私有本地空间**持有。

```text
允许包含：
    完整 AI 对话
    原始文件
    完整 Raw Reality
    操作截图
    必要的结果文件

绝不允许：
    commit
    push
    进入 Git 历史
    进入 CNB 镜像
```

不需要保留的，实验结束后由持有人直接删掉即可。
**不要因为研究需要，去制造一个新的私人数据仓库**——能用参与者自己的设备就用他自己的。

### 4.2 Public Research Record

Git 仓库里的那个 Case 文件。只允许：

```text
最低人物信息（Lab §10 Person 四项）
脱敏后的任务描述
必要原话摘录 ≤ 25 字
耗时
行为
Barrier
结果是否成功
Verification 事实
Before / After 必要摘录
Next Time 必要摘录
```

禁止：

```text
完整 AI 回复
完整聊天
真实 Excel
照片
录音
手稿
公司资料
任何可识别个人的信息
```

### 4.3 Path A 那一条怎么改

原表述"AI 实际回复**原文保留**"改为：

> **原文只在 Private Session Evidence 中保留；
> Git Case 只记录完成研究所需的脱敏摘要或必要短摘录。**

### 4.4 如果 Founder 选择不保留 Private Evidence

允许。只需在 Case 里注明：

```text
RAW_AI_RESPONSE_RETAINED = NO
```

---

## 5. A → B 不是 A/B test

> **修正（2026-09-19）**：不要把它读成两组对照实验。

真实设计是一条链，不是两个臂：

```text
Direct AI Baseline
      ↓
观察这个普通人自然能走多远
      ↓
识别 WORLD_SPACE_REMAINDER
      ↓
如果 remainder ≠ NONE
      ↓
World Space Rescue / Adoption Method
      ↓
看这道剩余门槛能否被拆掉
```

因此**禁止输出**：

```text
✗ "B 战胜 A"
✗ "World Space 比某模型强"
✗ "我们的转化率高于通用 AI"
```

**只允许输出**这两种句式：

```text
Path A 已自然解决 → WORLD_SPACE_REMAINDER = NONE

或

Path A 停在 X
Path B 消除了 / 没消除 X
```

H2 的真实问法也随之改成：

> **Direct AI 之后是否仍存在稳定的 remainder，
> 以及 World Space Method 能否在不重造执行能力的情况下消除它。**

---

## 6. Case 操作顺序（一步一步，不许跳）

```text
步骤 1   开场一句（§2），记录他的口头第一反应
步骤 2   按 §3 两步走：先口头问，再让他自己写下那件事（他写的答案 = Raw Reality）
步骤 3   问现状：他现在怎么弄 / 多久一次 / 最烦哪一步 / 为什么没换办法
步骤 4   Path A：他自己、自己设备、原话逐字、最多 3 轮（§21.3 八条）
步骤 5   记录 Path A 的九格（§21.4），包括"第一次结果"有没有出现
步骤 6   Path B：研究者只做六件事（§22.1），禁止六件事（§22.2）
步骤 7   记录 Path B 的同一套九格，注明哪些是研究者代做
步骤 8   Verification：让他自己说"你怎么知道它是对的"
步骤 9   Before / After：只记他的原话变化，不得诱导
步骤 10  问他一句："以后再遇到类似事情，你会怎么做？"
```

时间要记真实值：从步骤 4 开始到第一次结果 / 到放弃，用了多少分钟。

---

## 7. 停止条件（命中任意一条，当场停）

```text
A  参与者表现出不想继续（任何形式）
B  事情涉及医疗 / 法律 / 投资 / 心理危机 / 他人隐私
C  需要参与者上传身份证、银行卡、通讯录、他人照片
D  研究者发现自己正在替他操作（违反 §22.2 第 1 条）
E  研究者发现自己正在临场写程序（违反 §22.2 第 3 条）
F  参与者要求研究者替他做完
```

命中 D / E / F：该 Case 判 `SERVICE_SIGNAL`，**不得**记成产品胜出（§22.3）。

---

## 8. Wave 1 结束后的强制停线

```text
Wave 1 跑完必须停。
不允许自动扩到 6 人 × 2 Case。
不允许因为"才两个人说明不了什么"而继续加人。
```

停下来之后只做两件事：

1. 填 `TEMPLATE.md` 的两个 Case（如果这一步填不出来，说明协议有洞，先补协议）；
2. 把七格（§1）的自查结果交给总审查，等下一步指示。

**扩规模的权力在总审查，不在研究者。**

---

## 9. 研究者与参与者（已冻结）

### 9.1 Facilitator

```text
研究者 / Facilitator：Founder 本人。

Founder 只执行协议，不做最终研究裁决。
最终 barrier / signal 判定由后续总审查进行。
```

### 9.2 Wave 1 规模

```text
2 个真人 × 每人 1 件真实事情
```

### 9.0 先给参与者看这份说明

```text
research/capability-reach/PARTICIPANT-NOTICE.md
```

用普通话写的，讲清楚：可以随时停、不录音、东西留在他自己设备上、
公开记录里不会记姓名单位手机号。**参加前给他看，不要替他总结。**

### 9.3 参与者要求与招募边界

**只要**：

```text
2 名成年人
每人 1 件真实事情
自愿参加
```

**优先**：

```text
与 Founder 没有上下级关系
不是当前付费服务对象 / 咨询个案
不是 World Space 项目协作者
非 AI 重度用户
```

**第一轮不找**：

```text
未成年人
当前客户 / 个案
明显因为关系压力不好意思拒绝的人
```

另外每条 Case 本身还必须满足：

```text
真实存在一件 Verification 型任务
不涉及公司机密 / 客户资料 / 医疗法律等高风险信息
```

结构上尽量：

```text
P1：平时偶尔使用通用 AI
P2：平时基本不用通用 AI
```

**但招募不到就不凑**：不为了凑这个结构去造人、去硬拉不符合条件的人。
结构上没凑齐这件事，要如实写进 Case，不能当它没发生。

### 9.4 优先场景

```text
1. 非敏感 Excel / 表格处理
2. 本人拥有且无第三方隐私的普通手写 / 文本数字化
```

Wave 1 **暂不主动选择**：

```text
家庭照片
会议录音
医疗
法律
投资
心理危机
客户资料
公司机密
```

理由：第一轮不要把 `TRUST` 和 `VERIFICATION` 混在一起——
混在一起就分不清卡住他的是"不敢交出去"还是"不知道对不对"。

---

## 10. Path A 口径与状态

保留原有两条：

```text
参与者已有常用通用 AI      → 用他自己最常用的。
完全不用 AI                → fallback 豆包免费版普通对话。
```

其余八条执行纪律（§21.3）**全部保留**。

```text
PATH_A_PROTOCOL = APPROVED_FOR_WAVE1
```

**这不是全项目永久冻结**——它只授权到 Wave 1。
Wave 1 跑完可以根据真实暴露出来的问题修改协议。

### 10.1 执行授权与范围

```text
WAVE1 EXECUTION = APPROVED

授权范围只有：2 人 × 1 件事。
不得扩大。
Founder 本人作为 facilitator。
```

执行链条（**不是 A/B Benchmark**）：

```text
Direct AI Baseline
      ↓
观察自然做到哪里
      ↓
识别 WORLD_SPACE_REMAINDER
      ↓
如 remainder ≠ NONE
      ↓
World Space Rescue / Adoption Method
      ↓
观察 remainder 是否被消除
```

---

## 11. 状态与边界（不许省略）

### 11.1 本轮结束状态

```text
RAW_REALITY_FIX = DONE
PRIVATE/PUBLIC_EVIDENCE_SPLIT = DONE
PARTICIPANT_NOTICE = DONE
PUBLIC_CASE_PRIVACY = DONE
PATH_A_PROTOCOL = APPROVED_FOR_WAVE1
FACILITATOR = FOUNDER
WAVE1 EXECUTION = APPROVED      ← 范围只有 2 人 × 1 件事
REAL HUMAN CASES = 0
PRODUCTION CHANGE = 0
DEPLOYMENT = NO
```

### 11.2 跑完两个人之后的强制停线

两个人结束**立即停止**。不要：

```text
✗ 再找第三个人
✗ 改产品 / 开发 V0.2 / 修改首页
✗ 根据两个 Case 宣布产品定位
✗ 宣布 Verification / Trust / Integration 是核心
```

只做这五件：

```text
1  生成两个脱敏 Case（按 TEMPLATE.md，只进 Public Research Record）
2  更新 REAL HUMAN CASES = 2
3  写一份 Wave 1 protocol review
4  commit + push
5  停止，交总审查
```

### 11.3 现在的边界

```text
REAL HUMAN CASES = 0        （协议已批准，但一个真人都还没接触）
录音 = 无
已招募的人 = 0
已发出的邀请 = 0
FACILITATOR = FOUNDER（本人，尚未开始）
RAW_AI_RESPONSE_RETAINED = N/A（还没有任何 Case）
```

下一步不在仓库里：**由 Founder 去现实里找两个人。**
