# CURRENT_STATE

> 最后更新：**2026-09-19**（本轮由长跑重写；上一版停在 2026-09-11，那时写的"纯静态、无后端、无 AI runtime、无账号系统"已经**不是事实**，见 §1）
> 本文件只写**已核实的事实**与**明确的未决**。推测一律进 §5 待裁决，不写在这里。

```text
生产产品          V0.1，带访问门，跑在 v2 @ e8284c4（不是 GitHub Pages）
冻结版本          V1 静态站（web/index.html）与 V2 实验线文档
进行中的研究      Capability Reach Lab（真人可达性研究）—— 还没开始接触真人
真人 Case         REAL HUMAN CASES = 0
V0.2 开发         NOT AUTHORIZED
本轮代码改动      0（只动文档与研究骨架）
本轮部署          无
```

---

## 1. 当前生产事实（2026-09-19 公网实测复核）

| 项 | 事实 | 怎么核的 |
|---|---|---|
| 入口 | `https://ymai.fun/` | `nslookup` → `39.107.228.76`（阿里云 ECS），**不是** Pages 的 `185.199.x` |
| 链路 | ymai.fun → nginx(443) → `127.0.0.1:3200` → `server/world.mjs` | 记录见 `docs/v2/release-c500f3d/CUTOVER-RECORD.md` §1 |
| 线上代码 | `e8284c4`（分支 `v2`，2026-09-16 00:15 切流，实测中断 0.2 秒） | 批准点写在 CUTOVER-RECORD；`origin/v2` HEAD 仍是 `e8284c4`（未追加提交） |
| 前端 | `web/v2/`，首屏是自由输入框「你现在想做成什么？」 | 拉取 `https://ymai.fun/login` 与 `origin/v2:web/v2/login.html` **逐字节 md5 相同**（`186ab14156`） |
| 访问门 | 未登录 `GET /` → **302** `/login`；未登录 `POST /api/world` → **401** | 本轮公网实跑（只读请求） |
| 后端能力 | `healthz` 报：`auth:"ready"`、`search_keys:2`、`provider:openai_compatible`、`model:deepseek-flash`、`search:tavily`、`fail_closed:true` | 本轮公网实跑 |
| 预算闸 | `daily_cap:50`、`monthly_cap_rmb:20`；实账 `month_cost_rmb:1.494026`、`today_calls:0` | `healthz` 字段，非估算 |
| 账号 | 门后账号由 Founder 持有；本轮**未使用任何凭据登录**，全部结论来自未认证可见路径 | 本轮操作边界 |

一处方法诚实说明：本机 curl 走的是本地代理（`remote_ip=127.0.0.1`），TLS 校验通过（`ssl_verify_result=0`），
返回内容与门后 302 行为一致；若上层总审查要实锤"线上树 SHA"，需在服务器侧读
`/opt/world-space/current` 与 `state/approved-sha`，本轮**没有**服务器授权，因此线上 SHA 属"记录+间接证据一致"，不是直接读出。

## 2. 分支现实（2026-09-19 实测）

| 分支 | HEAD | 是什么 | 权威？ |
|---|---|---|---|
| `main` | `1516515` | **GitHub 默认分支**。旧 V1 静态站（无 `server/`、无 `web/v2/`、**无 `CONSTITUTION.md`、无 Lab**）+ 09-16 加的双端同步配置（`.cnb.yml`、`.github/workflows/sync-to-cnb.yml`） | 内容过期 |
| `v2` | `e8284c4` | **生产批准点**，冻结，不追加提交 | 代码权威 |
| `release/v0-85c7b91` | `2e37b84` | V0 发布记录归档 | 归档 |
| `release/v01-c500f3d` | `7911239` | V0.1 发布准备 + `CONSTITUTION.md` 与 Lab 首次落地处 | 合同上一级来源 |
| `research/capability-reach-20260919` | 本轮 HEAD | **本轮工作与真源收敛分支**（自 `7911239` 分出） | 本轮工作分支 |

⚠️ 由此产生的一个真实缺口，本轮**未修**（不属于本轮授权）：
从 GitHub 仓库页默认进入的是 `main`，那里读不到最高合同、读不到 Lab、也读不到线上那套后端代码。
收敛方案与命令留在 `research/capability-reach/NEXT_CANDIDATES.md`，等 Founder 决定
（与历史遗留的 `v2 → main` 收敛、Pages 退役是同一件事）。

## 3. 已冻结 / 已废止，不要再当成待办

- **V1 静态站**（`web/index.html` + `paths/` + `docs/design/CURRENT_DESIGN.md`，2026-09-11）：
  7 目标按钮 + 三步兜底那一版。文件仍在仓库，但**已不是线上形态**；`CURRENT_DESIGN.md` 自称
  "描述当前线上产品"这一句在 2026-09-19 已不成立，已加限定条。
- **V2 实验线**（`docs/v2/*`，2026-09-12~09-16）：内核冻结在 `docs/v2/NORTH_STAR.md`，
  其经验性禁令（禁用词典猜意图、证据纪律、隐私决定、预算上限）**仍然约束后续所有工作**；
  其 §4.3"生产目标架构（暂定）"一段已过时，以 §1 的生产事实为准。
- **机器评测**（`eval/`、`docs/v2/PILOT12_*`）：12 条模型跑的测试意图，**0 个真人**。
  其中的 P0/P1 与 "Gate 1 达成" 不得跨用为真人侧证据。evaluator v2 的冻结结论原样保留。

## 4. 正在进行：Capability Reach Lab（尚未接触真人）

| 项 | 状态 |
|---|---|
| 实验手册 | `docs/CAPABILITY_REACH_LAB.md`（v0.1，Founder 定稿 2026-09-19） |
| 真人 Case 骨架 | `research/capability-reach/`（编号规则 + 模板 + 数据边界），模板全空 |
| 真人 Case 数 | **0** |
| 本轮长跑统一报告 | `research/capability-reach/LONGRUN-REPORT-20260919.md`（A–H 八节，含 15 条停止条件自查） |
| 供应侧基线 | `docs/CAPABILITY_SUPPLY_BASELINE_20260919.md`（**Machine/Operator 层，无真人证据**） |
| 供应侧审判进度 | 8 条种子**全部完成**：4 条判 `EXIT_CANDIDATE`（截图转表 / 月报 / 个人页面 / 重复回复），4 条判 `HUMAN_TEST_CANDIDATE`（Excel / 录音 / 手写 / 照片）。浮出障碍是 VERIFICATION、TRUST、INTEGRATION；**DISCOVERY/SELECTION 一条都没成为主障碍** |
| 本地 fixture | `research/capability-reach/fixtures/`（4 份自生成虚构表 + 脚本 + 结果）：实测出"总额对、明细错"这种**任何核总数都抓不到**的失败形态 |
| Path A（真人自己直接问通用 AI 的固定基线） | `PROPOSED`，等 Founder / 总审查批准后才冻结 |
| Path B（Concierge Method） | 方法已写死，未跑真人 |
| H1 / H2 / H3 | 全部 `UNRESOLVED` / `NOT YET TESTED`——没有任何真人数据之前不可能有结论 |

## 5. 未决（等 Founder 或上层总审查，不在本轮自行决定）

1. `research → main` 与 `v2 → main` 收敛、Pages 退役：本轮不动。
2. Path A 基线产品与是否拆 China / Global 两条基线：本轮只出推荐。
3. 真人从哪来、谁做研究者、录音与原始文件谁持有：本轮只立边界（`research/capability-reach/DATA_BOUNDARY.md`）。
4. 实验期预算是否追加：现行为 50 次/日、¥20/月，实账 ¥1.494026/月，**本轮 0 次消耗**。
5. 曾在会话窗口出现过的 key 与明文口令残留的清理：仍按"未下令不删除"原样保留，清单见 CUTOVER-RECORD §6–§7。
6. **对外推荐里有 4 条主张已过期**（稿定"免费模板够用"、豆包无保留"免费"、醒图"免费修图"、
   DeepSeek 旧按钮名），其中两条属"误指路"级；本轮**未修改** `catalog/resources.json` 与任何文案，
   修复顺序与判据见 `research/capability-reach/NEXT_CANDIDATES.md` NC-08。
   已实测：带这些旧文案的页面目前公网打不开（www 与 Pages 均 302 到 `/login`），**是潜在风险不是正在发生的误导**。
   真正的问题不是哪句话写错，而是这批主张被记作 2026-09-07"free tiers confirmed"——**核对的保质期只有 8–12 天**。
