# World Space 发布候选 · 冻结清单（P7）

> 本文件是**证据分支**上的冻结记录，不属于发布树本身。
> 发布树 = 提交 `5b08b6590b787cacd05b78042b2a0c46026efc64` 经 `git archive` 展开的 184 个文件。

## 1. 身份

| 项 | 值 |
|---|---|
| 发布候选提交 | `5b08b6590b787cacd05b78042b2a0c46026efc64` |
| 父提交 | `05794a07162cb6a897e1acea727d5d420eb2aa4d` |
| 树对象 | `42c18bc94ca1a9d663fa0af1513dd73765f207af` |
| 文件数（发布树） | 184 |
| 内容清单 `sha256` | `fb35f605b28b60aa0ebc79548d6fb5f60d74b706232aaa88bd3357e06d7a354c` |
| 发布身份 `release_id` | `f40b621121ef880d2b37c521d1c3018b17a208dd8cb68f4ac097889448073020` |
| 身份方案 | `world-release-tree-v1`（`release-id.mjs`，与 `server/world.mjs` 的 `computeReleaseId()` 同口径） |

**不复用旧值。** R4 阶段的 `e8c949a681901ce0d9841483303ed8dfb765ef035459e89d335bda8099152a2f`
对应的是另一棵树（本轮在其上补齐了最终手册、回执模板、匿名首页新契约与嵌套探测修复）。
本清单只认上表的 `f40b6211…`。

### 1.1 两个哈希的口径（可复算）

```bash
# 发布身份：对 git archive 展开的 LF 树逐文件内容测量
git -c core.autocrlf=false archive 5b08b6590b787cacd05b78042b2a0c46026efc64 | tar -x -C /tmp/rel
node /tmp/rel/docs/v2/release-c500f3d/release-id.mjs /tmp/rel
# 期望：f40b621121ef880d2b37c521d1c3018b17a208dd8cb68f4ac097889448073020

# 内容清单：仓库自身的 tree 清单（blob 号 + 路径），排序后整体哈希
git ls-tree -r --format='%(objectname) %(path)' 5b08b6590b787cacd05b78042b2a0c46026efc64 \
  | LC_ALL=C sort | sha256sum
# 期望：fb35f605b28b60aa0ebc79548d6fb5f60d74b706232aaa88bd3357e06d7a354c
```

> 审计身份时必须用**发布形态树**（`git archive` 展开）。直接对 Windows 工作副本跑会被
> 两件与发布无关的东西干扰：未跟踪的 `_local/` 会进入身份；链接工作树的 `.git` 是普通文件
> （其内容被身份方案按顶层 `.git` 排除，但会被朴素的 `find` 选成突变目标）。
> 本轮证据一律使用 `/tmp/rel` 这类展开树。

## 2. 工具钉（8 件，发布形态树逐条复验 8/8）

来源：`docs/v2/release-c500f3d/verifier-update/TOOLS.sha256`（4 件在 `release-c500f3d/`，4 件在 `verifier-update/`）。

| 文件 | 字节 | sha256 |
|---|---:|---|
| `cutover.sh` | 26325 | `ee418a61b0a7505cc86aa7ac3ae59ff0556e2dd3664b4a26935f62672c42cb11` |
| `ops-selftest.sh` | 35410 | `6fc6153aa8e2b699d21bfc1a72763a90ead11133dce330e5144fef0da3093521` |
| `ws-prep.sh` | 31714 | `1c67558db97c3f536655a6fc70ef1532fea874cf500daf26027eed5d59eaf4e5` |
| `ops-fixture-face.mjs` | 7920 | `527bc2a5f75002d7f79d7ae99b24928dba61a9cc1d07c3126722adb6833a15fc` |
| `ws-verify-faces.sh` | 20347 | `f291021a6d25f42904a93755c3a5d700d2f6b7762094b35d6861bb799124065c` |
| `ws-verify-faces.sh.sha256` | 85 | `79cb6dbb2e14531e7224f9b42df383d728e198001ff393693a553330189bb7a9` |
| `face-probe.mjs` | 2265 | `9e805cf32014bb5b0165a4427a5f4679ec0cc3d97342262c4d530a15f6c1aba2` |
| `release-id.mjs` | 2480 | `330678c7eadf578615cc3117136a7f6f394e5ba2fec4235637bbae11918db02a` |

生产现状（只读实测，2026-11-01T16:01Z）：核验器是旧版 10623 B `52359796…`，无哈希钉、
无 `face-probe.mjs` / `release-id.mjs`；cutover/ws-prep/ops-selftest/ops-fixture-face 也均为旧哈希。
因此这 8 件必须**整组换新**，不能只换核验器（兼容矩阵见 `verifier-update/README.md` §3）。

## 3. `/ai/` 静态入口（10 文件）

- 树对象：`73726ee17b1020a44e52ec781c38fdf6ec66da6b`
- 来源：`5b08b65:docs/v2/release-c500f3d/ai-entry/files`（与 PR #34 的 `web/ai` 同树）

| 路径 | 字节 | blob |
|---|---:|---|
| `index.html` | 10402 | `6671036d31c133c9c119863c9b0180ba66cde97b` |
| `tools.html` | 11349 | `72d18ce1a8e917089c98d04af3a2e6c87182ebbd` |
| `limits.html` | 9193 | `51f95670cf0d792049af23b41105f3571d11d5f8` |
| `safety.html` | 7891 | `ba7046b760d82b94c522b47672d0cd3925035780` |
| `paths/find-the-facts.html` | 10413 | `af853564cb01733424065f9c035ff8b5c212f644` |
| `paths/make-a-picture.html` | 9568 | `ec2591de0b632be0d9bfebe8282d9b862c9e1a9e` |
| `paths/make-something.html` | 10346 | `d23a39fdc9ff303eb2605bc8bb79b427af191637` |
| `assets/ai.css` | 11790 | `97f97a416266ae1fcdf962a2f10f3f8fedd2a39f` |
| `assets/ai.js` | 3365 | `9f642f7eb773969aeb00e265713e5854a0628000` |
| `assets/tools.js` | 1966 | `4ac7aa721f60daab783c65069e664e9497c85146` |

## 4. 冻结边界

- 冻结对象只有上表提交的 184 个文件；`_local/`、`node_modules/`、`var/`、`.git` 不在发布树内。
- 证据分支（本分支）只追加 `EVIDENCE/`，不修改发布树里的任何文件。
- 冻结后若再改发布树，必须重新计算 `release_id` 并重跑三环境验收；本清单随之作废。

## 5. 逐环境验收（摘要）

| 环境 | 结论行 | 发布身份 |
|---|---|---|
| Linux 容器（node:20.20.2 + nginx:1.18.0，嵌套 Docker） | `R4_ACCEPTANCE_TOTAL=174  FAILS=0` / `R4_HOST_ACCEPTANCE=PASS` | `f40b6211…` |
| Windows CRLF 检出（153 个文本文件全带 CR） | `R4_ACCEPTANCE_TOTAL=174  FAILS=0` / `R4_HOST_ACCEPTANCE=PASS` | `f40b6211…` |
| Windows LF 检出（0 个 CR） | 见 `ACCEPTANCE-MATRIX.md`（同一轮三环境） | `f40b6211…` |

原始日志在 `EVIDENCE/logs/`。详细矩阵见 `EVIDENCE/ACCEPTANCE-MATRIX.md`。
