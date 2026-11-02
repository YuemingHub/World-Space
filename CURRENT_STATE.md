# CURRENT_STATE

> 最后更新：**2026-11-02**（M0 产品真源核查后重写；此前版本停留在 2026-09-11 的 V1 静态页口径）
> 真源关系：使命与阶段 = 长期建设合同 V1.0 + `docs/v2/NORTH_STAR.md`；产品定义 = `PRODUCT.md`；本文件只描述**现在真实是什么**。

---

## 1. 线上是什么（2026-11-02 实测）

| 项 | 现实 |
|---|---|
| 公开入口 | `https://ymai.fun` |
| 主机 | 阿里云 ECS `39.107.228.76`（WireGuard 内网 `10.254.0.1` 运维） |
| 运行时 | Node v20.20.2 · systemd `world-space` · nginx 1.18.0 |
| 应用 | `server/world.mjs`：`/api/world`（LLM + 联网搜索）、`/api/auth/*`（账号/会话）、`/healthz`；诊断面仅 `127.0.0.1:3201` |
| 线上版本 | `v2` = `c953aabb…`（2026-11-02 切流；release_id `e5e27983…`） |
| 匿名 `/` | 200 公开门面（`web/v2/public/index.html`，43KB，c953aab 版） |
| `/ai/` | 200 静态（PR #34 的 AI 入门，10 文件） |
| `/login` | 200；登录后 `/` 是 V2 应用页 |
| `/healthz` | 200 `{"ok":true}`；`/healthz/detail` 404 |
| `/ming/` | 200（另一产品的作品集，nginx 静态，不归本仓） |
| 生产配置 | `provider=openai_compatible`（deepseek-flash）· `search=tavily`（已配置 2 key）· `auth: ready` · `fail_closed: true` · 预算 50 次/天、20 元/月由代码强制 |
| 发布机制 | `/opt/world-space/releases/<sha>` + `current`；`cutover.sh` 两把钥匙 + 发布身份核验 + 回执；verifier 哈希钉；`ws-prep`；应急关站/带外回退（见 `WORLD-SPACE-FINAL-RELEASE-RUNBOOK.md`） |

**不再成立**：本文件旧版写的「纯静态 HTML / GitHub Pages / 无后端 / 无账号系统 / 无 CI-CD」。那是 V1 的形态，已被 V2 取代（见 `docs/v2/NORTH_STAR.md` §4.3 与 §5）。

## 2. 应用与门面

- **V2 应用**（登录后）：一句话说清想做什么 → 系统理解意图 → 必要时最多问 1–2 个关键问题 → 给出可点开的默认路径与今天的第一步 → 用户做完带回世界反馈 → 调整下一步。输出契约在 `contracts/world.schema.json`（含证据纪律：`source_type` / `checked_at` / `confidence`；`"我不知道"` 是合法输出）。
- **公开门面**（未登录 `/`）：R2 候选 `agent/ws-homepage-experience-r2-20261102` @ `7810fa7` 已 `READY_FOR_COMMANDER_REVIEW`（一个想法 → AI → 世界已有工具 → 真实结果 → 回现实；含孩子/家长入口与诚实标注的月亮样例）。**尚未上线**。
- 未登录且门面文件缺失时，`/` 回落 302 `/login`（删文件即回滚，契约回归覆盖）。

## 3. 仓库资产（摘要，详见 `docs/M0-PRODUCT-RECON-20261102.md`）

| 资产 | 状态 |
|---|---|
| `server/` + `web/v2/`（应用 + 门面） | 线上在用 |
| `contracts/world.schema.json` | 有效（认知链输出契约 v3.0.0） |
| `catalog/resources.json` | 7 条已核验资源（2026-09-07 复核；缺 M4 的隐私条件/替代能力字段） |
| `paths/step-1..3-*.md` | V1 三步兜底的镜像（3 个），不是行动路径库 |
| `docs/v2/FAILURE_LEDGER.md` | 23 条真实失败记录（P0/P1/P2/P3/OPS） |
| `docs/v2/PILOT12_*.md` | 12 条**合成压力用例**在真实 provider 下的运行；**不是真实用户验证** |
| `eval/*.mjs` | 20 个测试装置；发布验收 174 项、公开入口契约 22 项 |
| `web/index.html` + 根 `index.html` | V1 静态页与 GitHub Pages 跳转页：历史资产，线上不服务 |
| `docs/v2/release-c500f3d/` | 发布工具（cutover/verifier/identity/emergency/verifier-update） |

## 4. 已验证 / 未验证（诚实边界）

**已验证**（可复跑）：174 项发布验收、22 项公开入口契约、405/118/31 工具自测、真实应用身份闭环、发布失败矩阵（假重启/重启失败/关站/回滚/带外回退的拒绝路径）、首页候选 R2 的三视口浏览器自测与两位独立 Checker。

**未验证 / UNKNOWN**：
- **真实用户证据：零**。没有任何真实孩子或成人使用记录（PILOT12 是合成用例）。
- 搜索与证据绑定未在真实搜索下跑过（生产已配 tavily，但 `resources` 判据只在离线 fixture 验证）。
- 儿童专属任务与隐私流程未建。
- 成人零基础「从真实任务开始」的路径库未成型。
- Outcome Loop 有实现，无真实回执。

## 5. 与 `NORTH_STAR.md` 的一处冲突（待 Owner 裁决）

`NORTH_STAR.md` §4 写「无账号、无服务端会话」，但生产已有账号/会话（`/api/auth/*`、users 文件、session 密钥）。两者只能留一个：要么承认账号是 V2.1 的正当扩展并更新 NORTH_STAR，要么按 NORTH_STAR 移除账号（影响登录与门面分流）。**本文件不擅自选择**，等 Owner 裁决后同步。

## 6. 明确没有的

- 无社区、无埋点/行为追踪、无积分/排行榜/打卡
- 无自研模型、搜索、Agent Runtime、Workflow Engine、工具市场
- 无数据库（用户与预算状态是文件 + 浏览器持有回路状态）
- 无 CI/CD（发布靠 runbook + cutover + 回执）
