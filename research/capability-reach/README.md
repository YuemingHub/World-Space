# research/capability-reach/ — 真人 Case 台账

> 上位文件：`docs/CAPABILITY_REACH_LAB.md`（怎么做）与 `CONSTITUTION.md`（该不该做）。
> 本目录只放**真人**产生的研究记录。没有真人的时候，这里必须是空的（除本目录的说明文件）。

```text
REAL HUMAN CASES = 0
```

---

## 1. 编号规则

```text
C<人名代号>-<事序号>    例：C01-A / C01-B     （一个人最多 2 件真实事，正好对应 Lab §7 的 6 人 × 2 事）
```

- 人名代号只用 `C01…C06`，**不写姓名、单位、微信号、手机号、住址**（Lab §10 Person 只要求年龄段、
  技术熟悉度、常用设备、与本任务相关的必要背景）。
- 文件名单个 Case 一个：`cases/C01-A.md`。**在第一个真人出现之前不建 `cases/` 目录**（不造空目录）。
- 编号一经分配不复用、不重排，作废的 Case 保留文件并在状态里写 `VOID` 与原因。

## 2. Case 状态（只用这几个值，不发明新状态）

```text
NOT_STARTED      还没约到人
BASELINE_DONE    已完成 Lab §8 的开场（No-World-Space Baseline 已建立）
PATH_A_DONE      Direct AI 已按冻结口径跑完并记录
PATH_B_DONE      World Space Method 已跑完并记录
RESULT_VERIFIED  第一次真实结果已出现，且 Verification 有外部可观察证据
CONCLUDED        已填 Before/After 与 Next Time，可进入 Lab §15 裁决
VOID             数据不可用（写明原因）
```

`RESULT_VERIFIED` 的门槛：结果必须**外部可观察**（文件真的合成了、页面真的被别人打开了）。
"用户了解了""用户觉得有用"不算，见 Lab §10 First Real Result。

## 3. 台账

| Case | Person（最低信息） | 事 | 状态 | Path A | Path B | 第一次真实结果 | 结论 |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

**当前 0 行。这张表在有人之前就该是空的；填了就是造假。**

## 4. 每轮结束必须回答的三问

1. 这一轮新增了几个**真人** Case？（不是新增了几个文档）
2. 其中 Direct AI 已经自然做完、`WORLD_SPACE_REMAINDER = NONE` 的有几个？（Lab §11，这些要退出）
3. 还剩哪几道门是 Direct AI 没打开、而 World Space 能在不重造能力的前提下拆掉的？（Lab §12）

## 5. 本目录的文件

| 文件 | 作用 |
|---|---|
| `README.md` | 本文件：编号、状态、台账、纪律 |
| `TEMPLATE.md` | 单个 Case 的记录模板，严格继承 Lab §10 |
| `DATA_BOUNDARY.md` | 数据边界：什么能进 Git、什么不能（Mission 4） |
| `NEXT_CANDIDATES.md` | 想改代码时写在这里，**不施工** |

## 6. 三条禁令（与 Lab 一致，写在离文件最近的地方）

1. **禁止 Fake / Demo / Synthetic Case**：不许用模型扮演一个用户来填满模板。
2. **禁止机器证据冒充真人证据**：`eval/` 与 `docs/v2/PILOT12_*` 的结论不得写进本目录。
3. **禁止为了"有进展"而降低判定**：宁可 `NOT_STARTED`，不可假 `RESULT_VERIFIED`。
