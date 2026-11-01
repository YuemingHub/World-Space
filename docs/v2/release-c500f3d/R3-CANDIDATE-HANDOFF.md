# R3 候选移交（Builder → 独立复核）

- 仓库：`YuemingHub/World-Space`
- 分支：`agent/ws-release-verifier-facade-r3-20261101`
- 候选提交：`6add3a6da178bf36962249300926d0656ee2b66b`（本文件与两个证据装置为随后的追加提交，**不改动任何被判读的代码**；用下方 §9 的 `git diff` 可验证为空）
- 基线：`9654540d129d0b12cd07591855ee42bf9a6dad79`（Deep 复核对象，冻结）
- 复审基准文档：`D:\服务器\repos\ws-965-final-20261101\R2-965-REVIEW.md`
- 本候选**未合并、未部署、未写生产**；未重启服务、未 reload nginx、未改 DNS、未轮换真实密钥、未删除任何工作树、未触碰真实用户数据，也未清理 Deep 的审查证据。

状态：`READY_FOR_INDEPENDENT_CHECKER`（Builder 不自称 READY_TO_DEPLOY）。

---

## 1. 改了什么（相对 9654540）

```
 docs/v2/release-c500f3d/cutover.sh                 | 334 +++++++++----
 docs/v2/release-c500f3d/face-probe.mjs             |  40 ++   （新）
 docs/v2/release-c500f3d/ops-fixture-face.mjs       |  48 +-
 docs/v2/release-c500f3d/ops-selftest.sh            | 246 +++++++---
 docs/v2/release-c500f3d/release-id.mjs             |  53 ++   （新）
 docs/v2/release-c500f3d/release-tooling-selftest.sh| 516 +++++++++++++++---
 docs/v2/release-c500f3d/ws-prep.sh                 | 172 ++++++-
 docs/v2/release-c500f3d/ws-verify-faces.sh         |  90 +++-
 docs/v2/release-c500f3d/ws-verify-faces.sh.sha256  |   1 +    （新：核验器哈希钉）
 server/world.mjs                                   | 182 ++++++-
```

沙箱里全部为原生 POSIX symlink（Linux `node:20` 容器），不是 Junction 等效。

---

## 2. P0：运行身份闭环（唯一允许 `CUTOVER=OK` 的情形）

**做法**：不新增进程管理，只给既有单进程模型加一条可测量的自证链。

1. `server/world.mjs` 启动时对自己所在的发布树做内容测量
   `release_id = sha256("world-release-tree-v1\n" + Σ sorted(relpath+"\0"+sha256(file)+"\n"))`
   （排除 `.git` / `node_modules` / `var`），并在 **3201 诊断面**自报
   `release_id` / `release_id_scheme` / `started_at_ms` / `diagnostic_face=ops-v1`。
2. `release-id.mjs` 对**已逐文件核对过**的批准发布树做同一口径测量；`cutover.sh` 算出的
   `EXPECT_RELEASE_ID` 同时写进 `state/approved-meta.txt`。
3. `ws-verify-faces.sh` 在 dual_face 下逐项断言：诊断面字段齐全、`release_id` 与批准树相等、
   `started_at_ms` 不早于本次切流 T0、`pid` 等于重启后的 MainPID。
   缺一项 → 退出码 2（保留现场）；旧版单面 → 退出码 7（身份不可核实，**不给 OK 也不关站**）。
4. 环境变量自报的 SHA 不再被采信：核验器优先自己从批准树现算，env 只做交叉核对，两者矛盾即拒绝。

**真应用闭环证据**（`real-app-identity-it.sh`，跑发布树里真实的 `server/world.mjs`，
不含任何 fixture 代码；身份值由脚本对树独立现算，不读进程自报）：

```
PASS runtime_release_id_equals_approved_tree    = 37cc8d15…（进程自报 == 独立实算）
PASS runtime_pid_is_the_process_we_started      = 2607
PASS runtime_started_after_cutover              = … >= T0
ops_release_id_matches_approved                 PASS  …
ops_started_after_cutover                       PASS  …
verifier_exit_equals_0                          PASS  0        ← 正常树 → OK 形状
verifier_exit_equals_2                          PASS  2        ← 树被改 1 字节（运行中 37cc… ≠ 批准 5515…）
verifier_exit_equals_2 (old process)            PASS  2        ← 期望启动时间在未来
verifier_exit_equals_2 (pid mismatch)           PASS  2
REAL_APP_IDENTITY_IT=PASS（0 失败）
```

注：`37cc8d15…` 是**提交 6add3a6 的 `git archive` 树**的身份值，可用 `release-id.mjs` 复算；
它不是"当前分支最新提交"的身份（后续提交只追加文档/装置）。

---

## 3. 逐条 blocker：RED（旧）→ GREEN（新）

RED 用**同一个装置**（`r3-baseline-red-probes.sh`，原生 symlink、真 git 提交、真端口）跑两份工具：
`TOOL_BASELINE=9654540 树` 断言**旧行为确实错**，`TOOL_CANDIDATE=候选树` 断言**同一构造不再放行**。
GREEN 的完整矩阵在 `release-tooling-selftest.sh`（405 项）与 `ops-selftest.sh`（118 项）。

| Deep 项 | 构造 | 旧版（9654540）实测 RED | 候选 GREEN（同一构造/等价用例） |
|---|---|---|---|
| P1 = P0 假重启 | `RESTART_CMD=true`，旧进程仍在 3200/3201 | `CUTOVER=OK` rc=0，pid 前后同值、current 已切到 C2、3200 仍由旧进程应答 → **假报上线** | 目标无身份能力 → `ABORT_IDENTITY_UNSUPPORTED_BY_TARGET` rc=3，零写入；带身份能力的目标 + 假重启 → `CUTOVER=FAILED_SCENE_PRESERVED` rc=1，不关站（I-B） |
| P2 恢复失败仍称已退回 | 重启脚本把 `current` 换成真实目录后 exit 1 | 打印"current 已退回 …"，实际 `current` 是目录、非符号链接 rc=1 | `恢复核实=no` + 留档 `restore_verified=no`，并记录真实 current（C31）；切换失败但 current 从未变 → `恢复核实=unchanged`，**不出现 `=yes`**（C32） |
| P3 current 在 ROOT 外 | `current → /tmp/outside/<合法 SHA>` | `CUTOVER=OK` rc=0，全文不提位置边界 | `ABORT_LIVE_IDENTITY_UNKNOWN` rc=3，零写入（C25） |
| P4 releases 根是链接 | `$ROOT/releases` 指向 ROOT 外 | `CUTOVER=OK` rc=0，REL 物理在 ROOT 外 | `ABORT_RELEASES_NOT_DIRECTORY` rc=3，零写入（C23）；发布树内符号链接 → `ABORT_PATH_ESCAPE|RELEASE_TREE_MISSING`（C24） |
| P5 info/grafts 伪造祖先 | 缓存 `info/grafts: X C2`，批准 X（孤儿） | `CUTOVER=OK` rc=0，绕过发布线闸门 | `ABORT_GIT_METADATA_TAMPERED` rc=3（C22）；replace refs 同样被拦（C21） |
| P6 WS_POLL_TRIES=0 | 服务全程健康 | 判成"公网面探测不到"→ `FAILED_AND_CLOSED`、调用关站 rc=1 | `ABORT_USAGE_ERROR` rc=3，零写入、不关站（C19）；`abc` 同样（C20）；没有真实探测不得判"不可用" |
| P7 残留 env 换线 | `WS_RELEASE_LINE=alt` | `CUTOVER=OK` rc=0，越线无人拦 | `ABORT_RELEASE_LINE_OVERRIDE` rc=3（C18）；ws-prep 侧 `PREDEPLOY_ABORT_RELEASE_LINE_OVERRIDE` |
| P8 注释伪造诊断面 | `world.mjs` 仅注释里有 `opsPort` | 预检判成 `dual_face`，未拦 `LEGACY_AS_UPGRADE`，current 被切到 K | `face-probe.mjs` 去注释/字符串后判能力：K → 无身份 → `ABORT_LEGACY_AS_UPGRADE`/`ABORT_IDENTITY_UNSUPPORTED_BY_TARGET`，零写入 |
| P9 生产核验器版本 | 本机到生产无网络路径 | — | 核验器哈希钉 `ws-verify-faces.sh.sha256`：不符 → `ABORT_VERIFIER_IDENTITY_MISMATCH`（C16）；文件缺失 → `ABORT_VERIFIER_IDENTITY_UNKNOWN`（C17）。**生产实机哈希仍为 UNKNOWN**（见 §7） |

RED 装置自检（可复跑）：
```
R3_BASELINE_RED_PROBES_FAILS=0（共 31 项）
R3_BASELINE_RED_PROBES=PASS
```
即：31 条"旧版本应当出错"的断言全部成立，而候选侧（P0 的 green 分支）不再报 OK。

---

## 4. 六种情形只有 A 允许 OK（Deep 要求的最小集合）

| 情形 | 候选实测 | 退出码 |
|---|---|---|
| A 正常重启 | `CUTOVER=OK`（I-A / B1 / C1） | 0 |
| B 重启 rc=0 但没重启 | `FAILED_SCENE_PRESERVED`，不关站（I-B） | 1 |
| C 重启 rc=1 | `FAILED_RESTART_SCENE_PRESERVED`，恢复并核实（C13） | 1 |
| D 旧进程带着新 SHA 的 env | `FAILED_SCENE_PRESERVED`（I-D） | 1 |
| E 3200/3201 被别的进程占 | `FAILED_SCENE_PRESERVED`，不关站（I-E） | 1 |
| F 新进程起来了但身份不符 | `FAILED_SCENE_PRESERVED` + 点名 `release_id_matches_approved`（I-F） | 1 |
| 额外：诊断面缺身份字段 | `FAILED_SCENE_PRESERVED`（I-G） | 1 |
| 额外：服务真不可用 | `FAILED_AND_CLOSED`，**关站恰好 1 次**（I-H） | 1 |

---

## 5. 失败 / 部分写入矩阵（全部来自自测断言，非推断）

| 失败点 | current | approved-sha / 批准记录 | 重启 | 关站 | 留档 |
|---|---|---|---|---|---|
| 预检 ABORT_*（C16–C28 等） | 不变 | 不变 / 未写 | 未执行 | 0 | 无新留档 |
| 切换失败（C32） | 不变（如实记 `unchanged`） | 不变 | 未执行 | 0 | 记真实状态 |
| 切换后再也切不回去（C31） | 被破坏时如实记 `非符号链接` | 不变 | 已执行 | 0 | `restore_verified=no` |
| 重启失败（C13） | 已退回且**核实**（`=yes`） | 不变 | 已执行 | 0 | 记录恢复核实 |
| 核验失败（非 5） | 指向新版 | 不变 | 已执行 | 0（保留现场） | 记录 |
| 核验退出码 5 | 指向新版 | 不变 | 已执行 | **1 次** | 记录 |
| 身份不可核实（7） | 指向新版 | 不变 | 已执行 | 0 | `FAILED_IDENTITY_UNVERIFIABLE` |

---

## 6. 测试结果（全部在 `node:20` 容器、原生 symlink、真实 git 裸仓上跑）

| 装置 | 结果 |
|---|---|
| `release-tooling-selftest.sh`（提交 6add3a6 的树） | **405 项，失败 0，跳过 0** → `RELEASE_TOOLING_SELFTEST=PASS` |
| `ops-selftest.sh`（同上） | **118 项，失败 0，跳过 0** → `OPS_SELFTEST=PASS` |
| `real-app-identity-it.sh` | `REAL_APP_IDENTITY_IT=PASS`（0 失败） |
| `r3-baseline-red-probes.sh` | `R3_BASELINE_RED_PROBES=PASS`（31/31 项旧行为已复现） |
| 仓库回归（同一棵树） | runtime-isolation / authority / adapter-shape / admission / retry / liveness / runtime / auth / budget-cap / xss-boundary / outcome-loop / date / search-key-failover 全部 rc=0；`oidc-rp-selftest` 为既有 SKIP（未装可选依赖），rc=0 |

其中 `runtime-isolation-selftest` 是本轮必须过的一条：生产运行路径（server/config/web）里
**评测数据引用数 = 0**（扫描 17 个文件）。为满足它，三处身份实现的注释里不再出现被禁止的路径字样，
并去掉了 `eval/out` 排除项（它在 `.gitignore` 里，永远不会出现在 `git archive` 发布树中）。

**复核（推送到 GitHub 之后，在 `43f2256` 的树上原样重跑）**：三条装置读数与上表完全一致
（405/0/0、118/0/0、31/31、`REAL_APP_IDENTITY_IT=PASS`）。该树的身份值为
`a530d1600b9a3be5a19fb76c30464d1d3274fc63ec773fc4c5effd443fbbe86e`，
与本文件 §2 的 `37cc8d15…` 不同是**预期的**——树多了三个装置文件，身份按整棵树算。
两个值都可用 `release-id.mjs` 对对应提交的 `git -c core.autocrlf=false archive` 树复算。

---

## 7. 未解决 / 需要决策（不假装已闭合）

1. **生产核验器哈希 UNKNOWN**：本机到生产无网络路径（Deep 已记录 ssh 超时），我**没有**也无法去生产上读
   `/usr/local/bin/ws-verify-faces.sh`。因此不能假定生产是"新版本"。本轮给出的补偿是**哈希钉**：
   候选目录里带着 `ws-verify-faces.sh.sha256`，任何不符/缺失都在写入前中止（C16/C17）——
   这保证"旧核验器不会被当成新核验器采信"，但**不等于**生产已经装了正确版本。
2. **无身份旧版无法回滚上线**（需要 Founder 决策）：候选对"目标代码不自带 `release_id`"一律拒绝
   （`PREDEPLOY_ABORT_IDENTITY_UNSUPPORTED_BY_TARGET` / `ABORT_IDENTITY_UNSUPPORTED_BY_TARGET`）。
   意味着**当前线上那一版（以及所有 3e8e15f 之前的发布）不能作为回滚目标**，
   只有"自带身份测量的版本"之间才能互相回退。这是 P0 的直接后果，不是缺陷；
   但如果 Founder 需要"回到任何旧版"，就需要另一条明确授权的降级路径。
3. **EOL 敏感性**：发布身份按**实际字节**测量。Windows 上 `git archive` 默认会把工作副本的换行
   转换成 CRLF（本仓库 `core.autocrlf=true`、无 `.gitattributes`），解出的树与 blob 不同 → 身份不同。
   生产是 Linux（`autocrlf` 关），不受影响；本机复现必须用 `git -c core.autocrlf=false archive`。
4. `ss` 那一项（`ops_face_loopback_only`）在容器里缺 `ss` 时仍是 SKIP，**没有量到**（不改判为通过）。

---

## 8. 给 Deep 的独立复核入口

```bash
# 1) 取候选树（LF，与 blob 逐字节一致）
#    6add3a6 = 被判读的代码；分支尖端只多出本文件与两个装置脚本（§9 可验证为空）
git -c core.autocrlf=false archive 6add3a6 | tar -x -C /tmp/cand

# 2) 两条自测（在 Linux/容器里跑；真 symlink）
bash /tmp/cand/docs/v2/release-c500f3d/release-tooling-selftest.sh   # 期望 405/0/0
bash /tmp/cand/docs/v2/release-c500f3d/ops-selftest.sh               # 期望 118/0/0

# 3) 真应用身份闭环（另起一个干净端口环境）
bash /tmp/cand/docs/v2/release-c500f3d/real-app-identity-it.sh       # 期望 REAL_APP_IDENTITY_IT=PASS

# 4) 旧版本 RED 复现（需要 9654540 的树）
git -c core.autocrlf=false archive 9654540 | tar -x -C /tmp/base
TOOL_BASELINE=/tmp/base/docs/v2/release-c500f3d \
TOOL_CANDIDATE=/tmp/cand/docs/v2/release-c500f3d \
bash /tmp/cand/docs/v2/release-c500f3d/r3-baseline-red-probes.sh     # 期望 31/31 PASS
```

第 3、4 个脚本会在 3200/3201/沙箱目录上起进程；跑之前请确认这两个端口空闲。

## 9. 证明"追加提交没有改动被判读的代码"

```bash
git diff --stat 6add3a6..<本文件所在提交> -- \
  docs/v2/release-c500f3d/cutover.sh docs/v2/release-c500f3d/ws-prep.sh \
  docs/v2/release-c500f3d/ws-verify-faces.sh docs/v2/release-c500f3d/face-probe.mjs \
  docs/v2/release-c500f3d/release-id.mjs docs/v2/release-c500f3d/ops-fixture-face.mjs \
  docs/v2/release-c500f3d/ops-selftest.sh docs/v2/release-c500f3d/release-tooling-selftest.sh \
  docs/v2/release-c500f3d/ws-verify-faces.sh.sha256 server/world.mjs
# 期望：空
```

## 10. 边界声明（本轮遵守）

`NO PRODUCTION WRITE` / `NO MERGE` / `NO DEPLOY` / `NO NGINX RELOAD` / `NO SERVICE RESTART` /
`NO DNS CHANGE` / `NO REAL SECRET ROTATION` / `NO DELETION OF OTHER WORKTREES`；
不触碰真实用户数据；不清理 Deep 的审查证据（只读引用其 `R2-965-REVIEW.md` 与 fixture 构造）。
