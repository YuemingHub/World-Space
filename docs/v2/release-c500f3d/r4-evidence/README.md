# R4 验收证据（不是发布候选）

这个分支只放 **R4 集成候选那一次验收的原始输出**，方便独立 Checker 直接读退出码与逐条判据。
它不是发布候选，不要合并、不要部署；发布候选是：

- 分支 `agent/ws-r4-integration-20261101`
- 提交 `705ba5ce7f4bd715f4957c317eaec0148bdb4212`
- 树 `5dacef3ca7cdcd91e951975628b39543ccf13952`
- `release_id = e8c949a681901ce0d9841483303ed8dfb765ef035459e89d335bda8099152a2f`
  （v1 口径；对 `git -c core.autocrlf=false archive 705ba5c` 展开树现算，等于该次运行进程自报的身份）

## 这次跑的是什么

- 宿主：Windows 11 + Docker Desktop
- 容器：`node:20`（实测 `v20.20.2`）、`nginx:1.18.0`
- 顶层脚本：`docs/v2/release-c500f3d/r4-acceptance.sh`（本分支同一路径下也有候选那份）
- 命令（在候选提交的检出里执行，`R4_TREE_REF` 默认 `HEAD`）：

```
bash docs/v2/release-c500f3d/r4-acceptance.sh
```

## 结论（原文见 `r4-acceptance.log` 末行）

- `R4_ACCEPTANCE_TOTAL=94  FAILS=0`
- `R4_ACCEPTANCE=PASS`
- 宿主侧 `R4_HOST_ACCEPTANCE=PASS`，退出码 0

## 目录

| 文件 | 内容 |
|---|---|
| `r4-acceptance.log` | 容器内全部 94 条判据的逐行 PASS/FAIL、四个场景的 cutover 原文 |
| `summary.txt` | 本次的镜像版本、四棵树 tree 对象号、集成树身份、上一版/基线身份、`/ai/` 树号 |
| `scenes/s1-upgrade.log` | 正常发布：`CUTOVER=OK` |
| `scenes/s2-fake-restart.log` | 假重启：`CUTOVER=FAILED_SCENE_PRESERVED`，全文无 OK |
| `scenes/s3a-restart-fail.log` | 重启失败但旧进程还在：`FAILED_RESTART_SCENE_PRESERVED` |
| `scenes/s3b-kill-then-fail.log` | 旧进程已停且新进程起不来：`FAILED_RESTART_AND_CLOSED`，关站 1 次 |
| `scenes/s4-rollback.log` | 两把钥匙回滚：`CUTOVER=OK`，运行身份回到上一版 |
| `scenes/cutover-*.txt` | 每次切流的回执（status / target_release_id / verifier_sha256 / restore_verified 等） |
| `scenes/r3_tooling.log` | `release-tooling-selftest.sh` 原文（405 项 0 失败） |
| `scenes/r3_ops.log` | `ops-selftest.sh` 原文（118 项 0 失败） |
| `scenes/r3_real_app_it.log` | `real-app-identity-it.sh` 原文（含三种反例） |
| `scenes/r3_baseline_red.log` | `r3-baseline-red-probes.sh` 原文（旧工具 31 条应红） |
| `scenes/public_entry_selftest.log` | 首页回归原文 |
| `scenes/auth_selftest.log` | 访问门回归原文 |
| `app.log` / `nginx.log` | 应用与 nginx 容器日志 |

## 读日志时必须记住的两件事

1. 失败的只有两种：判据 `FAIL`（说明被测行为不合期望）与 `CUTOVER=FAILED_*`（说明切流被拒/回退）。
   核验器退出码 3 与 5 含义不同：3 是"判据不过/两面矛盾"，5 是"公网面确实不可用"——只有 5 才触发关站。
2. 隔离环境没有 TLS：核验器的访问门指向 nginx 的 `8080`（仍经 nginx），生产是 `https://ymai.fun:443`；
   应用公网口在容器里绑 `0.0.0.0` 是因为 nginx 在另一个容器，生产同机时仍是 `127.0.0.1`。

## 复核核验器哈希时的坑（CRLF）

回执里的 `verifier_sha256=f291021a6d25…` 与树内 `ws-verify-faces.sh.sha256`，以及 `git cat-file blob` 的字节一致。
但在 `core.autocrlf=true` 的 Windows 检出里直接 `sha256sum docs/v2/release-c500f3d/ws-verify-faces.sh`
会得到 `cc7b64cf…`——那是工作副本的 CRLF 版本，不是发布树口径。要复核就用发布树同一口径：

```
git -c core.autocrlf=false archive <候选提交> docs/v2/release-c500f3d/ws-verify-faces.sh | tar -x -C /tmp/vf
sha256sum /tmp/vf/docs/v2/release-c500f3d/ws-verify-faces.sh   # 应为 f291021a…
```

同理，`release_id` 也必须对 `git -c core.autocrlf=false archive` 展开的树计算，对工作副本直接算会因 CRLF 变成另一个值。
