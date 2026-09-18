# Pre-Human Capability Reach Long Run — 统一报告（2026-09-19 夜）

> 一句话：**没有证明 World Space 有价值，也没有推翻它。**
> 把"进真人之前机器能查清的事实"查清了，并且把 8 条候选里 **4 条判了死刑**。
> 真人 Case 仍然是 **0**。

---

## A. Repository Reality

| 项 | 实测结果 |
|---|---|
| 本轮工作分支 | `research/capability-reach-20260919`（自 `release/v01-c500f3d @ 7911239` 分出） |
| `CONSTITUTION.md` | 首落地 `release/v01-c500f3d @ 6a3d7e7`；本轮在研究分支上加了权威链表与分支说明 |
| `docs/CAPABILITY_REACH_LAB.md` | 首落地 `7911239`；本轮追加 §20（§19 处置状态 + Path B 操作定义），全部标 `PROPOSED` |
| GitHub 默认分支 | `main @ 1516515`：**没有合同、没有 Lab、没有 `research/`、没有后端代码**（见 NC-01） |
| 线上生产 | `v2 @ e8284c4`（2026-09-16 00:15 切流）。ymai.fun → ECS 39.107.228.76 → nginx → 127.0.0.1:3200 → `server/world.mjs`，静态来自 `web/v2/` |
| 本轮公网实测 | 未登录 `GET /` → 302 `/login`；未登录 `POST /api/world` → 401；`/login` 与 `origin/v2:web/v2/login.html` **md5 逐字节相同**（`186ab14156`）；`healthz`：`auth:ready`、`search_keys:2`、`daily_cap:50`、`monthly_cap_rmb:20`、`month_cost_rmb:1.494026` |
| 线上 SHA 的可信度 | 属"记录 + 静态页逐字节一致 + 门后行为一致"的**间接实锤**。本机无服务器授权，未读 `/opt/world-space/current`；要直接实锤需服务器侧执行 `ws-prep.sh verify` |
| 仍存在的文档冲突 | ①默认分支读不到合同（NC-01）②`eval/out/` 原始输出不在库里，P0/P1 结论无法在 GitHub 独立复核（NC-02）③`pilot12.json` 自称 12 条取自"37 条"而 `reality_eval.json` 自称"36 条"（NC-07）④`resources.json` 4 条对外主张过期（NC-08）⑤`www.ymai.fun` 仍 CNAME 到 github.io 但已被 302 收进门后 |

---

## B. What Changed（逐文件）

**新建**

| 文件 | 为什么 |
|---|---|
| `docs/CAPABILITY_SUPPLY_BASELINE_20260919.md` | 本轮主体：8 条种子的四层供应侧审判、跨场景障碍、EXIT/候选、Path A 提案 |
| `research/capability-reach/README.md` | 真人 Case 编号、7 个状态值、台账（0 行）、每轮三问、三条禁令 |
| `research/capability-reach/TEMPLATE.md` | 严格继承 Lab §10 的空模板 |
| `research/capability-reach/DATA_BOUNDARY.md` | 真人原始资料默认不进 Git；允许进的是什么；fixture 必须自生成 |
| `research/capability-reach/NEXT_CANDIDATES.md` | 10 条"想做但没做"，每条带事实/代价/谁有权批 |
| `research/capability-reach/fixtures/*` | 4 份自生成虚构 Excel + 合并脚本 + 实测结果，可本地重跑 |

**改写**

| 文件 | 改了什么 |
|---|---|
| `CURRENT_STATE.md` | 整篇按事实重写。旧版"纯静态、无后端、无 AI runtime、无账号系统"**已不是事实**；新版分列 生产事实 / 历史 V1 / 冻结 V2 / 进行中研究，并写死 `真人 0`、`V0.2 NOT AUTHORIZED`、`代码 0 修改`、`部署 无` |
| `AGENTS.md` | 开工必读顺序（冲突上位赢）+ Lab 期间禁止自主进 V0.2 的 5 条硬约束 + 分支现实表 + 设计真源分层 |
| `CONSTITUTION.md` | 权威链补全（加 CURRENT_STATE / Lab / research / V1 设计）+ 新增"本文件在哪个分支上" |
| `PRODUCT.md` | 给"唯一产品定义"加 scope 限定：产品定义层内唯一，不高于合同、不描述线上状态、不授权开发；§10 V0.1 标为历史 |
| `docs/v2/NORTH_STAR.md` | 给"V2 唯一产品内核"加 scope：只约束 `v2` 那条实验线，**不得推翻合同**；经验性禁令（词典猜意图、证据纪律、隐私、预算上限）继续有效；§4.3"生产目标架构（暂定）"标为已过时 |
| `docs/design/CURRENT_DESIGN.md` | 标题里的"当前线上"已不成立 → 降级为 **V1 设计真源**，下文一字未改 |
| `README.md` | 改成索引页（权威链 + 12 行导航表 + 一条边界纪律）；旧 V1 用法表保留但标注"不是现在打开首页会看到的东西" |

**只加导航、结论一字未改**（Mission 2）：`PILOT12_RESULTS`、`PILOT12_LLM_ONLY_REVIEW`、
`PILOT12_REPLAY_REVIEW`、`SEARCH_EVIDENCE_PILOT12`、`pilot12-raw`、`PRE_DEPLOY_HANDOFF`、`FAILURE_LEDGER`
—— 七处各加一条"Machine Evidence，0 真人，不得引用为 H1/H2"分级条。

**`.gitignore`**：新增一段**只作用于 `research/capability-reach/`** 的拦截（raw/、录音、照片、PDF、Office），
`fixtures/` 放行。故意不做全局屏蔽，以免影响仓库其他资产。

---

## C. Capability Supply Baseline（细账在 `docs/CAPABILITY_SUPPLY_BASELINE_20260919.md`）

| 种子 | 现有最佳供应（非 AI 优先） | 真实门槛 | 判定 |
|---|---|---|---|
| S1 合 Excel | Excel Power Query 从文件夹合并（2016–365）；WPS 内置合并 | 入口要摸 5 步；结构不一致即失败；**手机与网页版路径不成立** | HUMAN_TEST |
| S2 截图抄数字 | 手机端免费通用 AI 出表；iOS 实况文本只给纯文本 | 多一跳 App；无逐格置信提示 | **EXIT** |
| S3 会议录音 | 元宝/千问手机转写+纪要；组织内走妙记/闪记 | 存量要逐个导；官方自设 ≤6h/文件 与商店"不限时"矛盾；留存条款核不到 | HUMAN_TEST |
| S4 手写数字化 | 逐页拍照归档；潦草页按 40–68 元/千字交人工（政府采购成交价为证） | 厂商自述 90–92%，**遗物没有 ground truth** | HUMAN_TEST |
| S5 手机照片 | 系统自带去重+人物相簿；¥1 离线搜索；冲印 68 元/160 张 | 全是一次性动作，**4 周后回到原样**；"无限空间"查不到书面条款 | HUMAN_TEST |
| S6 每月报告 | Excel 模板+透视表（自动刷新）；飞书多维表格定时自动化 | 数据出内网受公司合规限制；Copilot 在中国个人不可得 | **EXIT** |
| S7 个人页面 | 微信生态公开页 / 国内免费建站二级域名（0 元 0 备案） | 自有域名必须 ICP 备案（1–20 工作日）；**上线 ≠ 别人打得开** | **EXIT** |
| S8 重复回复 | 企业微信自带快捷回复 + 免费客服机器人 | 个人微信挂机器人有封号条款，**不得推荐** | **EXIT** |

**跨场景结构**：`DISCOVERY` / `SELECTION` 在 8 条里 **0 次**成为主要障碍；
反复出现的是 `VERIFICATION`、`TRUST`、`INTEGRATION`。

**fixture 实跑到的**（`fixtures/RESULTS-excel-merge.md`）：按列位置合并总额 **少 24.00 元、0 报错**、
还凭空造出一个假品名；改成按表头对齐后总额正确，却被一行"数量单价填反"污染
（数量 7→9.1，**金额恰好不变**）——"我看下总数没问题"这种核对抓不到它。

---

## D. Exit Candidates（本轮最有价值的产出）

```text
E1  图片/截图 → 结构化表格      多款免费手机 AI 已覆盖            不要再设计功能，最多留一句"逐格核对"
E2  每月重复报告               Excel 透视表 / 飞书定时自动化      "复制上月改数字"在很多公司就是正解
E3  不会编程做公开个人页面       微信公开页 / 免费建站二级域名      直接带用户出去，只保留"别人能不能打开"的提醒
E4  大量重复回复               企业微信自带快捷回复                个人微信机器人有封号风险，禁止推荐
```

这 4 条按 Lab §11 就是 `WORLD_SPACE_REMAINDER = NONE`。
**但它们只是供应侧判定，终判要等真人。** 每条都附了能推翻它的观察设计。

---

## E. Human Test Candidates（各带待证伪 barrier）

| # | Capability Exists | 怀疑的 Reach Gap | 怀疑的 Barrier | 为什么 Direct AI 可能不够 | 什么真人行为能证伪 |
|---|---|---|---|---|---|
| H1 S1 | Power Query + 多家免费 AI 可上传多 xlsx | 能起跑，但拿到的表可能悄悄是错的 | VERIFICATION(+TRANSLATION) | 错的形式是"总额对、明细错"，不会有任何提示 | 真人只输原话，≤5 分钟拿到 .xlsx，行数=各文件之和、表头只一次、抽 3 列合计逐列一致，**换一批文件再测一次**两次全过 → 转 EXIT |
| H2 S3 | 手机免费转写+纪要+待办 | 存量批量、跨录音检索、敢不敢交出去 | ACCESS + TRUST | 单条能过；几十条与"以后还能找回"无人承接 | 10 条约 8 小时旧录音，30 分钟零付费跑完导入→纪要→待办→导出并检索命中 → 转 EXIT |
| H3 S4 | 厂商自述 90–92%；人工录入 40–68 元/千字有官方成交价 | 转录可跳出去；缺"对不对谁判、哪页值得留" | VERIFICATION + TRUST | 会给一份读得通但可能是编的转写，错误藏在通顺里 | 真人手稿 10 页喂免费 App，另一位家属**不必**逐字校对且隐私顾虑一句话化解 → 转 EXIT |
| H4 S5 | 系统自带去重/人物/备份/冲印都在 | 整理完维持不住，也没变成成品 | INTEGRATION + TRUST | 这不是"答一次"的问题，所有供给都是跑一次 | 只给一句入口指引：30 分钟做完 + **4 周后还干净** + 自己做出过一次相册 → 转 EXIT |

共同点（**假设，未证**）：机会可能不在"找到能力"，而在
**"让人敢把自己拿到的结果交出去"**（H1/H2/H3）与**"做成一次之后能不能留在生活里"**（H4）。
按 `CONSTITUTION.md` §07，前两格**不能用更多自动化来填**。

---

## F. Lab §19 处置状态

| §19 | 状态 | 说明 |
|---|---|---|
| 1 Path A 冻结口径 | **PROPOSED** | 推荐 China 基线 = 手机上免费版国民通用 AI App（默认对话、原话逐字、≤3 轮、跑前截首页记模型名与额度）；Global 基线只在 A 判"没做到"的 case 上代跑，**分母不同禁止合并比较**。落选理由与替换触发条件已写全。**未获批准** |
| 2 真人从哪来 | **STILL FOUNDER-DECISION** | 本轮未接触任何人，也未代她约人 |
| 3 原始资料与隐私 | **PROPOSED** | `DATA_BOUNDARY.md` + `.gitignore` 拦截已就位；是否录音/谁持原件/要不要参与者说明三项仍归她 |
| 4 研究者是谁 | **STILL FOUNDER-DECISION** | Path B 已写成不依赖具体人的六项职责定义，但不同人做的 Path B 不是同一条路径 |
| 5 预算与停线 | **PROPOSED** | 沿用 50 次/日、¥20/月，未自动放宽；本轮真人研究消耗 **0 次** |

⚠️ 交叉冲突必须让批准人看见：**Path A 推荐的那个产品，正是我们自己文案里承诺"免费"而依据已过期的那一个**
（NC-08 第二条）。拿它当基线在"现实可访问"上对，在"我们对外说的话"上会自相矛盾——两件事都得修，不能互相掩盖。

---

## G. Reality Boundary

```text
REAL HUMAN CASES = 0
H1 = UNRESOLVED
H2 = UNRESOLVED
H3 = NOT YET TESTED
V0.2 DEVELOPMENT = NOT AUTHORIZED
```

补充三条同样不许省略的边界：

```text
本轮全部结论证据等级 = Machine / Operator Evidence（研究者自己跑通 ≠ 普通人跑得通）
ORDINARY_REACHABLE 宣布次数 = 0
大陆网络侧可达性实测 = 0（本轮出口在境外美国西雅图；境外站点在微信里能否打开一律 unverified）
```

---

## H. Git

| 项 | 值 |
|---|---|
| 远程分支 | `origin/research/capability-reach-20260919`（本轮新建） |
| 本轮提交 | `9d6bb7e` 真源收敛 → `8821e3f` 证据分级 → `99a389b` fixture 实测 → `4f040c1` 供应侧基线 → `6d7b40a` 八条收齐 → 本报告 |
| 业务代码改动 | **0**（本轮相对分叉点的改动全部落在 `docs/`、`research/`、根文档与 `.gitignore`；`server/`、`web/`、`eval/`、`contracts/` 一字未动） |
| 部署 | **NO**。未登录生产、未使用任何凭据、未切流、未改 env / nginx / systemd |
| 工作树 | 本报告提交后 clean |
| 密钥 | 提交内容经形状扫描，无 key/token/口令；`healthz` 只引用公开字段名与计数 |
| 未推送内容 | 无 |

---

## I. 15 条停止条件逐条自查

| # | 条件 | 状态 | 依据 |
|---|---|---|---|
| 1 | 权威链无冲突 | **达成（本轮范围内）** | 三处"唯一"claim 全部加 scope；CONSTITUTION 权威链表 + AGENTS 必读顺序 + README 索引一致。残留冲突已登记（NC-01/02/07/08），不隐藏 |
| 2 | `CURRENT_STATE.md` 与事实基本一致 | **达成** | 逐条按公网实测 + 分支实测重写；"纯静态无后端"已删；线上 SHA 的间接性如实标注 |
| 3 | Lab 在 README / 权威导航可被找到 | **达成（分支内）** | README 索引表 + AGENTS 必读顺序第 4 项 + CONSTITUTION 权威链表三处指向。**注意**：默认分支 `main` 上仍然找不到，因为 `main` 上没有这些文件 → NC-01 |
| 4 | PILOT12 不可能再被误认为真人验证 | **达成** | 7 份文件加证据分级条；README/AGENTS/CURRENT_STATE/Lab §18 四处重复边界；`Reality Pilot 12` 命名源本身记 NC-07 |
| 5 | 真人 Case 模板与最小数据纪律就位 | **达成** | `TEMPLATE.md`（继承 Lab §10）+ `DATA_BOUNDARY.md` + `.gitignore` 定向拦截；`cases/` 故意不建 |
| 6 | 8 条 Pressure Seeds 完成供应侧审判或说明为何无法核实 | **达成** | 8/8 有归属；unverified 项逐条列明（大陆侧可达性、各家留存条款、部分定价） |
| 7 | 明确列出 EXIT CANDIDATES | **达成** | 报告 D 节 + 基线 §7，4 条 |
| 8 | 明确列出 HUMAN TEST CANDIDATES | **达成** | 报告 E 节 + 基线 §8，4 条 |
| 9 | 每条候选都有明确待证伪 barrier | **达成** | 4 条各带 barrier + "什么真人行为能证伪"的可执行判据（含通过阈值与复测要求） |
| 10 | Path A 有推荐基线，但明确等待总审查冻结 | **达成** | 基线 §9 + Lab §20 状态 `PROPOSED`；含落选理由、替换触发、冻结协议、与自家文案的交叉冲突 |
| 11 | 真人 Case 数仍明确为 0 | **达成** | G 节 + CURRENT_STATE §4 + README 纪律 + research README 首行 |
| 12 | 没有修改生产业务代码 | **达成（已验证）** | `git diff` 对分叉点比对：改动全在 `docs/`、`research/`、根文档、`.gitignore`；`server/`、`web/`、`eval/`、`contracts/` 0 改动 |
| 13 | 没有部署 | **达成** | 未使用凭据、未登录生产、未触服务器；全部生产结论来自未认证可见路径 |
| 14 | working tree clean | **本报告提交后达成** | 提交前唯一未提交项就是本报告与两处索引 |
| 15 | 本轮所有 commit 已 push | **达成** | 6 个提交推到 `origin/research/capability-reach-20260919`，SHA 逐个核对 |

## J. 下一轮只需要做三件事

1. **总审查批准 Path A 基线**（批准之前不开始第一个真人）。
2. **跑那三个欠下的 fixture**（截图 OCR / 公开音频 / 手写页）——它们直接检验 §V 假设，且不依赖真人。
3. **补一次大陆网络侧实测**，然后才允许任何"在中国能不能打开"进入对外文案。

