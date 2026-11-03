# R4 集成候选交接（Commander / 独立 Checker）

## 0. 状态口径

本目录所在的 R4 分支是**待独立验收的整合候选**，不是上线许可：

- 未合并 main / v2，未部署，未改 DNS，未 reload nginx，未写生产，未触碰其他 worktree；
- 三条保留阻塞仍在（§7），本轮**没有**解除，也不假装解除；
- 判定口径只有一条：在被测树上跑出的退出码、PASS/FAIL 行与实际运行身份，而不是本文的措辞。

## 1. 这份候选由什么组成

| 来源 | 固定提交 | 提供什么 |
|---|---|---|
| 生产发布线 v2 | `3e8e15f1` | 当前线上代码基线（没有公开门面、没有发布身份） |
| 首页候选 | `f1986b1` | `web/v2/public/index.html` 公开门面、匿名/登录后分流、首页回归 `eval/public-entry-*` |
| R3 发布工具候选 | `b02691d`（判定代码 `6add3a6`） | `cutover.sh` / `ws-prep.sh` / `ws-verify-faces.sh` / `release-id.mjs` 与各套自测装置；`server/world.mjs` 的发布身份 |

集成方式是两个**合并提交**：分别把 `f1986b1` 与 `b02691d` 完整带入，基线是 `3e8e15f1`。
没有把 main 整条历史混进来，没有改写任何已有提交，也没有拿单文件覆盖别的候选。

自己核一遍：

```
# 两条线都以 v2 生产基线为共同祖先
git merge-base --is-ancestor 3e8e15f1 f1986b1
git merge-base --is-ancestor 3e8e15f1 b02691d
# 候选的第一父链就是 v2 那条线，不是 main
git log --oneline --first-parent -3
# 工具目录与 R3 分支头逐字一致（除本轮新增的两个验收脚本）
git diff --stat b02691d -- docs/v2/release-c500f3d/ \
  ':(exclude)docs/v2/release-c500f3d/r4-acceptance.sh' \
  ':(exclude)docs/v2/release-c500f3d/r4-acceptance-inner.sh'
# 首页三件与首页候选逐字一致
git diff --stat f1986b1 -- web/v2/public/index.html eval/public-entry-selftest.mjs eval/public-entry-journey.mjs
```

`/ai/` 仍然是 nginx 静态入口（`web/ai` 十文件树），不进应用发布树；它的并列入口位置没有被改动。

## 2. 最终集成树的发布身份（本轮最重要的一条）

- 口径 v1：`sha256("world-release-tree-v1\n" + Σ sorted(relpath + "\0" + sha256hex(file) + "\n"))`，排除 `.git`、`node_modules`、`var`。
- 现算（**唯一可信来源**）：

```
rm -rf /tmp/r4tree && mkdir -p /tmp/r4tree
git -c core.autocrlf=false archive <候选提交或已固定的树对象> | tar -x -C /tmp/r4tree
node docs/v2/release-c500f3d/release-id.mjs /tmp/r4tree
```

必须相等的四处：

1. 上式对候选树的现算值；
2. 运行中进程诊断面（`127.0.0.1:<ops>/healthz`）的 `release_id`；
3. `state/approved-meta.txt` 的 `release_id`；
4. cutover 回执里的 `target_release_id`。

本文件**故意不写死身份值与候选提交号**：任何写进被提交文件的 SHA/身份，下一轮提交就会自我过期（本仓有过这个教训）。权威值在候选提交的提交信息、Issue #82 和交接报告里，一切以现算为准。

起点事实：生产基线 `3e8e15f1` **没有身份能力**（诊断面没有 `release_id`）。所以升级只接受带身份的目标；回滚目标也必须是带身份的祖先，并且要两把钥匙（`WS_MODE=rollback` + `WS_ROLLBACK_TO`）。

## 3. 怎么复跑验收

前置：Docker；镜像 `node:20`（实测 v20.20.2）与 `nginx:1.18.0`。

```
bash docs/v2/release-c500f3d/r4-acceptance.sh
# 固定了树对象时也可以：
R4_TREE_REF=$(git write-tree) bash docs/v2/release-c500f3d/r4-acceptance.sh
```

脚本做四件事：按 LF 展开四棵树（base / prev / r4 / r3base）并复算身份 → 起独立网络里的 node + nginx 容器（只发布 `127.0.0.1:1428x`）→ 容器内跑 `r4-acceptance-inner.sh` → 收日志、只拆自己的容器与网络。日志目录在结尾打印（`r4-accept-<时间>/logs`），内含逐条 PASS/FAIL、四个场景的 cutover 原文与回执。

诚实边界：

- 隔离环境没有 TLS，核验器的"访问门"指向 nginx 的 8080（仍然经过 nginx 1.18，不绕过它）；生产是 `https://ymai.fun:443`。
- 应用公网口在容器里绑 `0.0.0.0`，因为 nginx 在另一个容器；生产同机部署时它仍是 `127.0.0.1`。诊断口在代码里写死 `127.0.0.1`，不随该变量暴露。
- 容器里从展开树合成 git 提交时，Windows 绑定挂载不保留 exec 位，整棵 tree 对象号会与真实提交不同。验收因此用**"路径 + blob 内容"清单**逐条证明导入无损（发布身份只认内容字节；cutover 的树核对也只比路径与 blob 内容，模式只用于判符号链接）。

## 4. 12 项验收在装置里的对应

| 需求 | 装置里的判据 |
|---|---|
| 1 匿名公开首页 | `a1_*`：200 + 三个门面标志 + ≥8000 字节，且不是登录页兜底 |
| 2 `/ai/` 并列入口 | `a2_*`：`/ai/` 200、`/ai` 301、深链 200、`assets/ai.css` 200、不存在 404 |
| 3 登录 / 登出 | `a3_*`：登录 200 + `ok:true` + 只有身份 cookie；`/api/auth/me` 200；登录后 `/` 是应用页 |
| 4 登录后 API 可用 | `a4_*`：`POST /api/world` 200 且无 `error`；登出后 `me` 401 |
| 5 未授权不泄露 | `a5_*`：`/api/world`、`/api/auth/me` 均 401，响应里没有用户名/会话信息 |
| 6 `/healthz` 正常 | `a6_*`：200 `{"ok":true}`；`/healthz/detail` 公网面 404 |
| 7 `/ming/` 不受影响 | `a7_*`：200 且 md5 与夹具一致；`/ming` 301 |
| 8 正常发布识别新进程 | `S1`：exit 0 + `CUTOVER=OK`；pid 改变、`started_at_ms ≥ T0`；运行身份 = 集成树身份；meta 与回执一致 |
| 9 假重启不得假报成功 | `S2`：exit 1 + `FAILED_SCENE_PRESERVED`，全文无 `CUTOVER=OK`，旧进程仍在服务 |
| 10 发布失败保护现有服务 | `S3a`（重启 rc=1、旧进程还在）→ `FAILED_RESTART_SCENE_PRESERVED`，不关站；`S3b`（旧进程已停且新进程起不来）→ `FAILED_RESTART_AND_CLOSED`，关站恰好 1 次 |
| 11 回滚核实真实恢复 | `S4`：两把钥匙回滚 → exit 0 + `CUTOVER=OK`；current 与运行身份都变成上一版；`/` 回到 302 `/login` |
| 12 身份全部一致 | `a8_*` + `S1`/`S4` 的 meta、回执字段；`tree_*`/`manifest_*` 证明被测树就是集成树 |

## 5. 四个切流场景的现场口径

| 场景 | 期望 | 现场落在哪 |
|---|---|---|
| S1 正常发布（真重启） | 0 / `CUTOVER=OK` | current=集成树目录；新 pid；身份=集成树 |
| S2 重启 rc=0 但没重启 | 1 / `FAILED_SCENE_PRESERVED` | current 停在目标目录、旧进程仍在服务——这是留给人判断的现场，cutover **不**自动退回；关站 0 次 |
| S3a 重启 rc=1、旧进程还在 | 1 / `FAILED_RESTART_SCENE_PRESERVED` | current 退回旧版并核实；旧版仍在服务；关站 0 次 |
| S3b 旧进程已停、新进程起不来 | 1 / `FAILED_RESTART_AND_CLOSED` | 关站恰好 1 次，然后由装置按"人工恢复"重新起回旧版 |
| S4 两把钥匙回滚 | 0 / `CUTOVER=OK` | current=上一版；运行身份=上一版身份；根路径回到登录跳转 |

S2 之后装置会做一次显式"人工修复"（把 current 与批准记录指回真正在服务的版本）才能继续下一场景。这是把人做的判断写进脚本，不是 cutover 自己会做的事。

## 6. 同时在跑的既有装置

内层最后重跑 R3 的四套装置与首页/访问门回归，判定只认每套末尾的 PASS token 与退出码，不数"通过了多少条"：

- `release-tooling-selftest.sh`
- `ops-selftest.sh`
- `real-app-identity-it.sh`（真应用身份闭环 + 树被改一字节 / 旧进程 / pid 不符三种反例）
- `r3-baseline-red-probes.sh`（同一构造喂旧工具基线应全红、喂候选不再放行）
- `eval/public-entry-selftest.mjs`、`eval/auth-selftest.mjs`

## 7. 保留的 UNKNOWN 与阻塞（本轮未解除）

1. **生产核验器身份仍是 UNKNOWN**：生产 `/usr/local/bin/ws-verify-faces.sh` 的真实 sha256 拿不到（本机到生产没有网络路径）。仓库里的 `ws-verify-faces.sh.sha256` 只钉住仓库这一份；没有生产实机哈希，就不能宣称"可生产发布"。
2. **无身份旧版的回滚应急通道未获 Owner 授权**：回滚两把钥匙 + 目标必须带身份；这条授权不在本轮范围。
3. **R3 的 reservations 继续有效**：见 `R3-CANDIDATE-HANDOFF.md`，本轮不新增也不解除。

## 8. 边界

不合并、不部署、不改 DNS、不 reload nginx、不写生产、不删其他 worktree、不清理 Deep 审查证据。
