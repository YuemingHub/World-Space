# 生产核验器闭环 · 只读核查 + 更新包（P3）

> 本目录只做两件事：**证明生产上装的是哪一版核验器**，以及**给出可证、可退的更新包**。
> 本目录不包含"已经装好了"的声明；生产写入必须等 Owner 批准（见 §7）。

## 1. 生产实测（只读）

采集时间 2026-11-01T15:55Z（UTC），来源：`ssh family-space` 只读 `stat`/`sha256sum`。

| 文件 | 大小 | 权限 | 属主 | sha256 |
|---|---|---|---|---|
| `/usr/local/bin/ws-verify-faces.sh` | 10623 | 755 | root:root | `523597968809da7ca3ebb4000704077cfb069f7e12b2f33049621567bde3aad8` |
| `/usr/local/bin/ws-verify-faces.sh.sha256` | — | — | — | **不存在** |
| `/usr/local/bin/face-probe.mjs` | — | — | — | **不存在** |
| `/usr/local/bin/release-id.mjs` | — | — | — | **不存在** |
| `/usr/local/bin/cutover.sh` | 6425 | 755 | root:root | `405a9b803f359d691e0741285fdd208f7946be2b1f5bab351e106be586f91425` |
| `/usr/local/bin/ops-selftest.sh` | 19535 | 755 | root:root | `2f876b13880114ec9a0499cf6ac8cf42336267da12972cc27c76258e48799906` |
| `/usr/local/bin/ws-prep.sh` | 15271 | 755 | root:root | `2533365a2c7946403d0d0a2aaae1d65a8e8829fe5d38af93e6d190c238ba150e` |
| `/usr/local/bin/ops-fixture-face.mjs` | 3832 | 755 | root:root | `9a35cfd934e65b46c3c7d770ab76c87951188fb50e55fd3f16d4099ba8ed7767` |
| `/usr/local/bin/ws-env-put.sh` | 5847 | 755 | root:root | `bcef652bfe805112f210c2ecf402dee554b607b781e44339e88a813e663a0372` |

结论：

- 生产核验器是 **旧版**（10623 B）；本轮候选是 20347 B —— **两者不同，必须换**。
- 生产没有哈希钉、没有两个辅助文件（`face-probe.mjs` / `release-id.mjs`）。
- `ws-env-put.sh` 与候选**完全相同**（同为 `bcef652b…`），不需要写。

## 2. 候选（本目录钉住的字节）

唯一事实源是本目录的两个哈希钉；下表只是方便人读：

- `ws-verify-faces.sh.sha256`（1 行）：`f291021a6d25f42904a93755c3a5d700d2f6b7762094b35d6861bb799124065c`
- `TOOLS.sha256`（8 行）：核验器 + 哈希钉 + 两个辅助文件 + cutover / ops-selftest / ws-prep / ops-fixture-face

`ws-verify-faces.sh` 的依赖不只是命令，还包括**同目录的两个文件**：

- `face-probe.mjs` —— 从发布树代码判断"这一版有没有内部诊断面"；缺了它，核验器对所有树都报 `STATIC_PROBE_FAILED(6)`。
- `release-id.mjs` —— 从批准发布树现算 `release_id`；缺了它，身份不可核实。

## 3. 调用方与兼容性（实测，不是推断）

生产调用方式：

- `/usr/local/bin/cutover.sh` 第 92 行：`bash "$VERIFY"`，**无位置参数**，只按退出码动作
  （`0` = OK，`5` = 唯一允许关站，`*` = 保留现场）。
- `/usr/local/bin/ops-selftest.sh` A 段：`VERIFY="$HERE/ws-verify-faces.sh"`，用同目录 `ops-fixture-face.mjs` 起假面。

Docker（`node:20` = v20.20.2）四组配对实测：

| 核验器 | ops-selftest | 结果 | 说明 |
|---|---|---|---|
| 旧 | 旧 | **PASS 75/0** | 生产现状基线 |
| 新 | 新 | **PASS 118/0** | 发布树里的配套状态 |
| 新 | 旧 | **FAIL 21/75** | A1 期望 0 实得 7（新契约：无诊断面 = 身份不可核实）→ **不可只换核验器** |
| 新 | 旧 cutover.sh | 退出 2 `NEW_INCOMPLETE` → `CUTOVER=FAILED_SCENE_PRESERVED` | 旧 cutover 不传 `WS_EXPECT_START_AFTER`；新核验器拒绝在"无法证明重启生效"时给 OK。**不关站、留现场**，属安全失败 |

因此：**这五件必须整组装**（核验器 + 哈希钉 + 两个辅助文件 + ops-selftest + cutover + ws-prep + 夹具），
`install-tools.sh` 就是为此写的 —— 任何一件对不上就零写入退出。

过渡态（只装了核验器、没装新 cutover）不会把站点关掉，但也**不可能**得到 `CUTOVER=OK`；
这是刻意的：宁可拒绝宣布成功，也不让"没重启"被当成成功。

## 4. 安装包内容

```
verifier-update/
├── README.md                 本文件
├── install-tools.sh          整组装（推荐入口）
├── install-verifier.sh       只装核验器三件（核验器 + 钉 + 两个辅助文件），用于定点恢复/演练
├── verify-production.sh      只读认证（装前、装后各跑一次）
├── ws-verify-faces.sh        核验器本体（LF）
├── ws-verify-faces.sh.sha256 哈希钉
├── face-probe.mjs            静态面探针
├── release-id.mjs            发布身份计算器
├── HELPERS.sha256            两个辅助文件的哈希钉
└── TOOLS.sha256              整组 8 件的哈希钉
```

## 5. 命令与期望输出

### 5.1 装前认证（只读，任何时刻可跑）

```
sudo WS_VERIFY_TO=/usr/local/bin/ws-verify-faces.sh \
     WS_VERIFY_HELPERS_PIN=<发布树>/docs/v2/release-c500f3d/verifier-update/HELPERS.sha256 \
     bash verify-production.sh <期望 sha256>
```

- 现在（旧版）期望：`PROD_VERIFIER_CERT=FAIL`，且失败项集中在 `sha256` / `helper_*` / `pin_*`。
- 装好后期望：`PROD_VERIFIER_CERT_TOTAL=23  FAILS=0` + `PROD_VERIFIER_CERT=PASS`。
  （已在模拟生产目录上实测通过；沙箱里无服务时 `public_healthz` / `detail_not_public` 会红，属预期。）

### 5.2 安装（整组）

```
cd <发布树>/docs/v2/release-c500f3d/verifier-update
sudo bash install-tools.sh
```

期望输出：`TOOLS_INSTALL=OK  files=cutover.sh,ops-selftest.sh,ws-prep.sh,ops-fixture-face.mjs,ws-verify-faces.sh,ws-verify-faces.sh.sha256,face-probe.mjs,release-id.mjs`
已是最新时：`TOOLS_INSTALL=NOOP_ALREADY_CURRENT`。

失败语义：`FAIL_SOURCE_HASH` / `FAIL_PIN_ENTRY` / `FAIL_SYNTAX` 等 = **零写入**，生产不受影响；
`FAIL_READBACK` = 已尝试整组回滚，需人工按 `backup_dir` 处理。

### 5.3 只装核验器三件（定点恢复/演练）

```
sudo WS_VERIFY_EXPECT=f291021a6d25f42904a93755c3a5d700d2f6b7762094b35d6861bb799124065c \
     bash install-verifier.sh
```

期望：`VERIFIER_INSTALL=OK`；重复执行：`VERIFIER_INSTALL=NOOP_ALREADY_CURRENT`。
备份目录：`/root/backups/world-space-verifier-<时间戳>/`，含 `receipt.txt`（装前/装后哈希、调用方哈希）。

### 5.4 回滚

```
cp -a /root/backups/world-space-verifier-<时间戳>/ws-verify-faces.sh.orig /usr/local/bin/ws-verify-faces.sh
# 辅助文件若安装前不存在：mv（保留，不删除）
```

整组回滚见 `install-tools.sh` 输出的 `backup_dir` 与 `TOOLS_INSTALL=OK` 提示行。

## 6. 实测证据汇总（本轮 Docker）

- `install-tools.sh`：篡改源 → 零写入（rc=2）；正常安装 rc=0，8 件哈希全部读回一致；重复执行 NOOP rc=0。
- `install-verifier.sh`：错误期望哈希 → 零写入；篡改辅助文件 → 零写入；正常安装 → 三件字节与权限正确；重复执行 NOOP。
- `verify-production.sh`：对着模拟生产（新核验器 + 假双面）→ `PROD_VERIFIER_CERT_TOTAL=23  FAILS=0`。
- 兼容性矩阵：见 §3 表（全部在 `node:20` 容器内实跑）。

## 7. 需要 Owner 批准的生产写入（精确清单）

以下写入**尚未执行**；本轮只读核查 + 本地/Docker 演练。逐项都需要 Owner 明确点头：

| # | 目标路径 | 动作 | 新字节 sha256 | 现状 |
|---|---|---|---|---|
| 1 | `/usr/local/bin/ws-verify-faces.sh` | 覆盖 | `f291021a…`（TOOLS.sha256 第 5 行） | 旧版 `52359796…` |
| 2 | `/usr/local/bin/ws-verify-faces.sh.sha256` | 新建 | `79cb6dbb…`（TOOLS.sha256 第 6 行） | 不存在 |
| 3 | `/usr/local/bin/face-probe.mjs` | 新建 | `9e805cf3…` | 不存在 |
| 4 | `/usr/local/bin/release-id.mjs` | 新建 | `330678c7…` | 不存在 |
| 5 | `/usr/local/bin/ops-selftest.sh` | 覆盖 | `6fc6153a…` | 旧版 `2f876b13…` |
| 6 | `/usr/local/bin/cutover.sh` | 覆盖 | `ee418a61…` | 旧版 `405a9b80…` |
| 7 | `/usr/local/bin/ws-prep.sh` | 覆盖 | `1c67558d…` | 旧版 `2533365a…` |
| 8 | `/usr/local/bin/ops-fixture-face.mjs` | 覆盖 | `527bc2a5…` | 旧版 `9a35cfd9…` |
| 9 | `/root/backups/world-space-tools-<stamp>/` | 新建（备份） | — | 目录可建 |

不写入：`/usr/local/bin/ws-env-put.sh`（字节相同）、`world-space-emergency.sh`（本轮不换）、
`/opt/world-space/` 下任何内容（那是切流动作，另行授权）。

批准后执行顺序：先 `verify-production.sh`（记录装前）→ `install-tools.sh` → `verify-production.sh`（记录装后）
→ `ops-selftest.sh`（期望 `OPS_SELFTEST=PASS`）→ 再进入切流。
