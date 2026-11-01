# World Space · 验收矩阵（P2/P3/P4/P5/P6 证据）

> 冻结对象：`8e10fd0c79536549607c856bf475323378c6aee8`
> 发布身份：`80a92a7a4a4587385ff62691bef04353432e5f0e6b08ac938078fdb250b31d84`
> 原始日志：`EVIDENCE/logs/{linux,crlf,lf}/`（每个环境含宿主总日志 + 容器内场景/套件日志）

## 1. 三环境复跑（P2A）

同一提交、三种检出/运行形态，跑同一套 `r4-acceptance.sh`（真实 `node:20` = v20.20.2、`nginx:1.18.0`，
经 nginx 真实转发；Docker 隔离网络，只发布 `127.0.0.1:1428x`）：

| 环境 | 形态 | 结论 | 身份 |
|---|---|---|---|
| Linux 容器（嵌套 Docker） | `git clone` 后 checkout，LF；内层再起 node/nginx 容器 | `R4_ACCEPTANCE_TOTAL=174  FAILS=0`<br>`R4_ACCEPTANCE=PASS`<br>`R4_HOST_ACCEPTANCE=PASS` | `80a92a7a…` |
| Windows CRLF 检出 | `core.autocrlf=true` 实检出：162 个含换行的文本文件全部带 CR；另 2 个单行文件（无换行）保持 LF；20 个二进制 | 同上 174/0 | `80a92a7a…` |
| Windows LF 检出 | 文本文件 0 个 CR | 同上 174/0 | `80a92a7a…` |

CRLF 形态的证明点：`r4-acceptance.sh` 在 `set -o pipefail` 之前自愈自身 CRLF 并重执行；
所有发布树都用 `git -c core.autocrlf=false archive` 展开，绝不使用工作副本。
（CRLF 检出里 `git status` 会把 162 个文件显示为 modified —— 那是换行差异，不是内容差异。）

> 口径提醒：脚本自报的 `含 CR 的文件=N` 在 MSYS 下不成立（CR 参数在 argv 里被吃掉 → 空模式命中所有文本文件，
> 本轮报 163 = 文本文件数）。上表数字来自逐字节扫描，不用该行。完整说明见 `RELEASE-MANIFEST.md` §1.1。

## 2. 发布身份机制复审（P2D）

| 位置 | 结论 | 检查 |
|---|---|---|
| 容器内（真运行进程 + 批准记录 + 真核验器） | `IDENTITY_AUDIT=PASS`（12/12） | 确定性 / 形状 / 与 base、prev 唯一 / 一字节敏感 / 改回可逆 / 批准记录 = 树 / 运行自报 = 树 / 核验器哈希 = 钉 |
| 宿主（发布形态树，`git archive` 展开） | `IDENTITY_AUDIT=PASS`（8/8） | 同上（无运行进程项） |

日志：`logs/linux/scenes/identity_audit.log`、`logs/identity-audit-host-release-form.log`。

## 3. Git 元数据伪造对抗（P2B，容器内 S6）

`GIT_METADATA_ADVERSARIAL=PASS`。证明：

- `git replace` 与 `info/grafts` 都能让非后代提交在普通 git 眼里变成后代（伪造确实有效）；
- `GIT_NO_REPLACE_OBJECTS=1` 只挡 replace，挡不住 grafts —— 所以“拒绝其存在”的前置检查是必要的；
- 对缓存副本投毒后，`cutover.sh` 以退出码 3 + `CUTOVER=ABORT_GIT_METADATA_TAMPERED` 中止，
  `current`、进程、回执零变化；
- 清掉投毒后同一套参数能越过元数据闸（在更后面的核验器闸按设计被拒），说明拒绝是精确的，不是一律误伤。

## 4. 仓库级回归（P2C）

容器内同一棵树：`REPO_REGRESSION_TOTAL=20  PASS=15  FAIL=0  SKIP=1  NOT_RUN=4`，
`REPO_REGRESSION_SKIP_IS_NOT_PASS=yes`，verdict `PASS`。

| 类别 | 项 | 说明 |
|---|---|---|
| SKIP | `oidc-rp-selftest.mjs` | `SKIP: oidc-provider 未安装`；零依赖运行时不受影响 |
| NOT_RUN | `date-selftest.child.mjs` | 子进程模块，由 `date-selftest.mjs` 调用，不单独执行 |
| NOT_RUN | `outcome-journeys.mjs` | 外部活体服务驱动器，只留痕不判分 |
| NOT_RUN | `public-entry-journey.mjs` | 需要 playwright-core + 浏览器二进制，容器内不装 |
| NOT_RUN | `run.mjs` | 真实 provider 压测（计费 + 日预算上限），不属于回归套件 |

另有首页自身回归：`public-entry-selftest.mjs` 退出 0、零 `✗`；`auth-selftest.mjs` 退出 0。

## 5. 无身份旧版应急回退（P4）

| 场景 | 结果 |
|---|---|
| S9 从有身份候选回退到无身份基线，带第二把钥匙 | `EMERGENCY_ROLLBACK=OK`；进程换、服务 200、诊断面身份为空、回执 `identity_verified=no`、目标 `unidentified`、`target_id=unidentified` |
| S9 缺第二把钥匙 | 退出 3，`EMERGENCY_ROLLBACK=ABORT_SECOND_KEY_MISSING`，`current` 未动 |
| S10 再从无身份旧版正常前进 | `CUTOVER=OK`，身份恢复为 `80a92a7a…`，`/` 200 门面 |

S9 回执里的 `from_id` 是回退前那一刻的身份（本轮 `37cc8d15…`，即 prev/R3 树），与最终候选 `80a92a7a…` 不同是正确的。

## 6. 最终产品验收（P5）

经 nginx 1.18 真实转发的四条旅程（同一进程、按真实顺序）：

| 旅程 | 断言 | 结果 |
|---|---|---|
| 匿名访客 | `/` 200、含“你想做什么事”、不是登录页；`/login` 200；`/ai/` 与深链 200 | 通过 |
| 登录用户 | 登录 200 + 会话 cookie；`/` 是本人页面（含“你现在想做成什么”）；`/api/world` 200 | 通过 |
| 未授权反证 | `/api/world`、`/api/auth/me` 均 401；响应不含 `u-r4` | 通过 |
| 登出后再访 | 登出 200；`/` 回到公开门面；`/api/auth/me` 401 | 通过 |

边界同时验证：`/ai` → 301 `/ai/`、`/ai/` 深链与静态资源 200、缺失页 404；
`/ming/` 200 且内容 md5 不变（`dfac7e01…`）、`/ming` → 301；`/healthz/detail` 与 `/api/ops/roster` 不公开；
匿名首页不再 302 到登录页；`GET /api/world` 返回 404 且契约文本为 `only POST /api/world exists`。

## 7. 发布工具验收矩阵（P6）

| 编号 | 场景 | 期望 token | 退出码 |
|---|---|---|---|
| S1 | 正常发布（真重启） | `CUTOVER=OK` | 0 |
| S2 | 重启命令退出 0 但没重启 | `CUTOVER=FAILED_SCENE_PRESERVED` | 1 |
| S3a | 重启失败、旧进程还在 | `CUTOVER=FAILED_RESTART_SCENE_PRESERVED` | 1 |
| S3b | 旧进程已停、新进程起不来 | `CUTOVER=FAILED_RESTART_AND_CLOSED` | 1 |
| S4 | 回滚（两把钥匙） | `CUTOVER=OK` | 0 |
| S5 | 核验器哈希不符 | `CUTOVER=ABORT_VERIFIER_IDENTITY_MISMATCH` | 3 |
| S6 | replace refs / grafts | `CUTOVER=ABORT_GIT_METADATA_TAMPERED`（对抗脚本 PASS） | 3 |
| S7a | 发布树被改 | `CUTOVER=ABORT_RELEASE_TREE_MISMATCH` | 3 |
| S7b | 发布树含符号链接 | `CUTOVER=ABORT_RELEASE_TREE_SYMLINK` | 3 |
| S7c | 目标目录是链接 | `CUTOVER=ABORT_RELEASE_TREE_MISSING` | 3 |
| S7d | `current` 逃逸 / 活体身份不可知 | `CUTOVER=ABORT_LIVE_IDENTITY_UNKNOWN` | 3 |
| S9 | 无身份应急回退 / 缺第二把钥匙 | `EMERGENCY_ROLLBACK=OK` / `ABORT_SECOND_KEY_MISSING` | 0 / 3 |
| S10 | 无身份旧版再前进 | `CUTOVER=OK` | 0 |

工具自测：`RELEASE_TOOLING_SELFTEST` 405 项 0 失败；`OPS_SELFTEST` 118 项 0 失败；
`REAL_APP_IDENTITY_IT` 0 失败；`R3_BASELINE_RED_PROBES` 31 项 0 失败。所有失败分支都断言了
“current / 进程 / 回执零变化”。

## 8. 生产核验器闭环（P3，只读）

生产实测（2026-11-01T16:01Z，只读）：旧核验器 10623 B `52359796…`；
无 `.sha256`、无 `face-probe.mjs`、无 `release-id.mjs`；cutover/ws-prep/ops-selftest/ops-fixture-face 均为旧哈希。
候选 8 件与 `TOOLS.sha256` 逐条一致（发布形态树 8/8）。
生产更新**未执行**，精确写入清单见 `docs/v2/release-c500f3d/verifier-update/README.md` §7，
授权门见 `WORLD-SPACE-FINAL-RELEASE-RUNBOOK.md` §3（G1–G8）。

## 9. 本矩阵不证明什么

- 不证明生产已经发布：本清单全部在 Docker / 宿主隔离环境完成，生产写入等待 Owner 逐项授权；
- 不证明真实模型语义：`WS_PROVIDER=stub`、`WS_SEARCH=fixture`；付费真实回路未跑；
- 不证明 OIDC 路径：`oidc-provider` 未安装（SKIP，不计入 PASS）；
- 不替代生产核验器安装后的认证：装前/装后各一次 `verify-production.sh` 必须由执行者在生产上留下输出。
