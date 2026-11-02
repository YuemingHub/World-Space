# M0 · 现状与产品真源核查（2026-11-02）

> 阶段：长期建设合同 V1.0 · M0（现状与产品真源核查）
> 执行：DeepSeek Code · 只读核查 + 文档修正，未部署、未合并 main/v2、未触碰生产
> 方法：仓库实读（git、文件）+ 线上实测（HTTPS）+ 文档互相对照；**不推断，拿不到就写 UNKNOWN**

---

## 1. 唯一产品真源（权威顺序）

**冲突时的排序：Owner 当前原话 > 下列真源 > 其他文档 > 历史报告。**

| 层 | 文件 | 状态 | 覆盖范围 |
|---|---|---|---|
| **使命与阶段** | 本长期合同 V1.0（Owner 原文，2026-11-02）+ `docs/v2/NORTH_STAR.md`（V2 内核，2026-09-12 冻结） | 有效 | V1.0 = 长期使命、用户、五领域、M0–M6、最高原则；NORTH_STAR = V2 产品内核（认知链、五原则、三条禁止、隐私决定、目标架构、通过标准） |
| **产品定义** | `PRODUCT.md`（2026-09-06） | 有效（V1 口径） | Resource First：找/选/带着开始；不造轮子；内容诚信；可直接跳出去 |
| **当前状态** | `CURRENT_STATE.md` | **本轮重写为现实** | 线上是什么、部署结构、候选、已验证/未验证 |
| **设计真源** | `docs/design/CURRENT_DESIGN.md`（V1，冻结）+ 线上 V2 结构 | V1 冻结 / V2 以代码为准 | V1 单页设计；V2 = `web/v2/`（应用）+ `web/v2/public/index.html`（公开门面）+ `server/` |
| **仓库规则** | `AGENTS.md` | 有效（本轮补充 V2/发布说明） | 复用优先级、内容诚信、每轮 commit+push |
| **发布与回退** | `WORLD-SPACE-FINAL-RELEASE-RUNBOOK.md` + `docs/v2/release-c500f3d/` | 有效（生产在用） | G1–G8 授权门、cutover、verifier 哈希钉、发布身份、应急回退 |
| **资源目录** | `catalog/resources.json`（v3.0.0，7 条，2026-09-07 复核） | 有效，需按 M4 补字段 | 资源的能力/来源/门槛/费用/局限/复核时间 |
| **失败记录** | `docs/v2/FAILURE_LEDGER.md`（23 条） | 有效（只记真实失败） | P0/P1/P2/P3/OPS 分级 + 根因 + 最小修复 + 回归 |
| **真实证据** | `docs/v2/PILOT12_*.md`、`eval/*`（20 个装置） | 有效，**注意边界** | PILOT12 是**合成压力用例**，不是真实用户验证 |

> **不新建第二套真源**：本轮没有新增"产品定义"类文件，只新增本核查报告 + 把 `CURRENT_STATE.md` 改成现实。

---

## 2. 资产地图

### 2.1 线上部署（实测，2026-11-02）

| 项 | 实测 |
|---|---|
| 域名 | `https://ymai.fun`（`/` 200 · 43326B 门面；`/ai/` 200 10402B；`/login` 200；`/healthz` 200 `{"ok":true}`；`/ming/` 200 29892B；`/public/index.html` 200 同门面） |
| 主机 | 阿里云 ECS `39.107.228.76`（`Ymai`），经 WireGuard 内网 `10.254.0.1` 运维 |
| 运行时 | Node v20.20.2 · systemd `world-space`（active）· nginx 1.18.0 |
| 应用 | `server/world.mjs`：`/api/world`（LLM + 搜索）、`/api/auth/*`（账号/会话）、`/healthz`、静态面；ops 诊断面仅 127.0.0.1:3201 |
| 发布 | `/opt/world-space/releases/<sha>` + `current` 符号链接；`cutover.sh`（两把钥匙、身份核验、回执）；verifier 哈希钉；`ws-prep`；应急关站/带外回退 |
| 线上版本 | `v2` = `c953aabb…`（2026-11-02 03:15 切流，release_id `e5e27983…`） |
| 生产配置事实 | `provider=openai_compatible`（deepseek-flash）· `search=tavily`（`search_configured:true`，2 key）· `auth: ready` · `fail_closed: true` · 预算 50 次/天、20 元/月由代码强制 |

### 2.2 代码与内容资产

| 资产 | 路径 | 状态 |
|---|---|---|
| V2 应用 | `server/*.mjs` + `web/v2/{index.html,app.js,style.css,login.html,login.js,render.mjs}` | **线上在用**（登录后 `/` 是应用页） |
| 公开门面 | `web/v2/public/index.html` | 线上在用（c953aab 版，43KB）；R1/R2 候选未上线 |
| 认知链契约 | `contracts/world.schema.json`（Intelligence Contract v3.0.0） | 有效：`understanding / questions / safe_next_action / next_action / recommended_path / resources(证据纪律) / uncertainties / reality_feedback_prompt / fallback_if_refused / meta` |
| V1 静态页 | `web/index.html`（23KB）+ 根 `index.html`（1KB 跳转） | **历史资产**：线上不服务；根跳转页指向 `web/index.html` |
| 资源目录 | `catalog/resources.json` | 7 条：豆包 / v0 / DeepSeek / Stirling PDF / 稿定设计 / 一刻相册 / 醒图 |
| 行动路径 | `paths/step-1..3-*.md` | V1 三步兜底的镜像文件（3 个），不是 4–6 条行动路径 |
| 设计档案 | `archive/design/v1,v2` | 历史资产（AGENTS.md 规定不得修改） |
| 测试装置 | `eval/*.mjs`（20 个）+ `docs/v2/release-c500f3d/*`（174 项验收、405/118/31 工具自测、22 项公开入口契约） | 有效 |
| 发布工具 | `docs/v2/release-c500f3d/`（cutover/ws-prep/verifier/identity/emergency/verifier-update） | 有效，生产在用 |

### 2.3 候选资产（未上线，未合并 main/v2）

| 候选 | 分支 | SHA | release_id | 状态 |
|---|---|---|---|---|
| R1 首页 | `agent/ws-homepage-20261102` | `cba7488` | （分支树） | 原候选，未改动 |
| **R2 首页体验** | `agent/ws-homepage-experience-r2-20261102` | **`7810fa7`** | **`4b0a8c90…`** | `WORLD_SPACE_HOME_EXPERIENCE_R2_READY_FOR_COMMANDER_REVIEW`；174/174、22/22、两位独立 Checker PASS |

### 2.4 真实用户证据

**结论：零。** 目前没有任何真实孩子或成人使用 World Space 的记录。
`PILOT12` 是 12 条**合成压力用例**（S1–S12）在真实 provider 下的运行（P0=0，但无搜索 provider、资源恒 0），按合同 §6.1「不能把自动化测试通过描述为真实用户验证」——它不算真实用户证据。

---

## 3. 冲突清单（文档 ↔ 文档 / 文档 ↔ 现实）

| # | 冲突 | 证据 | 严重度 | 处置 |
|---|---|---|---|---|
| 1 | `CURRENT_STATE.md` 称「纯静态 HTML / GitHub Pages / 无后端 / 无账号系统 / 无 CI/CD」 | 现实：Node 服务 + systemd + nginx + releases + 账号会话 + 发布系统 | **P1（文档失真）** | **本轮已重写** |
| 2 | `CURRENT_DESIGN.md` 称「当前线上产品（`web/index.html`）」 | 现实：匿名 `/` 是 `web/v2/public/index.html`，登录后是 `web/v2/` 应用 | P2 | 本轮已加冻结说明（V1 冻结，线上以 V2 为准） |
| 3 | `README.md` 结构表：`web/index.html 公开入口`、`index.html 根跳转页` | 同上 | P2 | 本轮已更新 |
| 4 | **`NORTH_STAR.md` §4「无账号、无服务端会话」 vs 生产已有账号/会话（`/api/auth/*`、users 文件、session 密钥）** | 生产实测 `auth: ready`；`AUTH_UI_*` 交接文档存在 | **P1（产品契约冲突）** | **需 Owner 裁决**：要么承认账号是 V2.1 的正当扩展并更新 NORTH_STAR，要么按 NORTH_STAR 移除账号（影响登录/门面分流）。**本轮不擅自决定** |
| 5 | `PRODUCT.md` §10「paths/ 4–6 条行动路径」 vs 现实 `paths/` 只有 3 个三步兜底文件 | 目录实读 | P2 | 记入差距（M3/M4 时补齐或调整口径） |
| 6 | `catalog/resources.json` 的 `used_in` 指向 V1 面板 id（`goal-*-panel`） | V2 应用不使用这些面板 | P3 | 记入差距（资源目录需按 V2 使用面重新标注） |
| 7 | 根 `index.html` 是 GitHub Pages 时代的跳转页（指向 `web/index.html`，文案为 V1） | 线上不服务；与 V2 无关系 | P3 | 记为死资产；不删除（历史资产保护），在 README 标注 |
| 8 | `AGENTS.md` 未提及 V2 应用、发布系统、线上部署 | 仓库已有 `docs/v2/release-c500f3d` 全套 | P2 | 本轮已补一节"线上与发布" |
| 9 | `NORTH_STAR.md` §4.3「无数据库 / 无服务端会话」 vs 生产 users 文件 + session | 同 #4 | P1 | 并入 #4 裁决 |
| 10 | 线上首页仍是 `c953aab` 原版门面（43KB），R1/R2 候选未上线 | 线上实测 43326B | 状态事实（非冲突） | 待 Commander 终审 R2 → 走发布流程 |

---

## 4. 真实差距清单（面向 M1–M6）

| # | 差距 | 影响阶段 | 现状证据 | 最小可行动作 |
|---|---|---|---|---|
| 1 | **零真实用户证据** | M1/M5 | §2.4 | 找 1 个真实孩子 + 1 个成人零基础者，用真实问题跑通一次并记录回执（需 Owner 安排真人） |
| 2 | 搜索/证据绑定未在真实搜索下验证 | M1 | PILOT12 无搜索；生产已配 tavily | 用生产搜索跑一次真实问题，检查 `resources` 的证据纪律（`source_type`/`checked_at`/`confidence`） |
| 3 | 儿童专属流程缺失（任务、隐私、家长旁看） | M2 | R2 候选有孩子区但只是静态引导；应用无儿童模式 | M2 设计：儿童任务卡 + 隐私前置说明 + 家长回执 |
| 4 | `catalog` 缺 M4 字段：隐私条件、替代能力；最后复核 2026-09-07 | M4 | JSON 字段实读 | 补两个字段 + 逐条复核（每条附核验时间与来源） |
| 5 | 成人零基础「从真实任务开始」的路径库未成型 | M3 | 应用是「一句话意图→路径」，无任务库 | 3–5 条真实任务路径（写通知/查政策/做海报…），每条含第一步与卡住怎么办 |
| 6 | Outcome Loop 有实现但无真实回执 | M5 | `meta.receipt_*` 字段存在 | 等真实用户跑通后收集第一份真实回执 |
| 7 | R2 首页待 Commander 终审 | 入口 | `7810fa7` READY_FOR_REVIEW | 终审通过后按 runbook 发布（身份重新冻结） |

---

## 5. 本轮结论

1. **唯一产品真源已建立**：V1.0 合同 + NORTH_STAR（V2 内核）+ PRODUCT（Resource First）三层互不冲突；`CURRENT_STATE.md` 已改为现实；`CURRENT_DESIGN.md`/`README.md`/`AGENTS.md` 已修正失真处。
2. **资产地图清楚**：线上 V2 应用 + 门面 + 发布系统 + 20 个测试装置 + 23 条失败账本 + 7 条资源目录；R1/R2 候选待审。
3. **冲突清单 10 条**，其中 **1 条需要 Owner 裁决**（NORTH_STAR 的"无账号"与生产账号系统的冲突），其余已处置或记为差距。
4. **真实差距清单 7 条**，最关键的是 **#1 零真实用户证据**——这是 M1 的硬前提，也是合同 §九「产品价值必须有真实使用证据」的当前状态。

### 下一步（M1 合同草案，等真实用户即可启动）

**M1 · 第一条完整的探索创造体验**

- 对象：1 个真实孩子（8–12 岁）+ 1 个成人零基础者
- 任务：各带一个真实问题进来（例如孩子的「为什么月亮会跟着我走？」、成人的「帮我写一条家长群通知」）
- 链路：真实意图 → 应用理解 → 搜索/资源 → 第一步行动 → 真实结果 → 核验 → 下一步
- 证据要求：真实回执（截图/文字/作品）、时间戳、可复现的输入输出、家长旁看记录
- 验收：用户当天真的做了一个动作，并能说出"发生了什么"；系统在事实不足时如实说"判断不了"
- **前置**：Owner 提供 2 位真实用户；无真实用户时，M1 不做"模拟验收"，只做不依赖真人的准备（任务卡模板、回执模板、隐私说明）

---

## 6. 本轮未做（明确边界）

- 未部署、未合并 main/v2、未改生产、未 reload nginx、未改 DNS
- 未替 Owner 裁决 NORTH_STAR 账号冲突
- 未把 PILOT12 当作真实用户证据
- 未改动 R1/R2 候选分支（保持原样）
