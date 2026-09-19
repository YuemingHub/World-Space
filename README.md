# World Space

> **让普通人拥有这个时代正在产生的能力。**

**公开入口：https://ymai.fun**

> ⚠️ 2026-09-16 起该入口**带访问门**：未登录访问首页会被 302 到 `/login`，未登录调用
> `/api/world` 返回 401（本轮公网实测复核过）。线上跑的是 **V0.1**，不是下面那份 V1 文案描述的东西。
> 线上真实状态一律以 [`CURRENT_STATE.md`](CURRENT_STATE.md) 为准。

---

## 这个仓库的读法（权威链，冲突时上位赢）

```text
1  CONSTITUTION.md      最高产品合同：这件事该不该做
2  PRODUCT.md           产品细则：是什么 / 不是什么 / 复用优先级
3  CURRENT_STATE.md     当前真实状态：线上是什么、什么还没做
4  当前任务的实验或版本文件
5  代码
```

## 索引

| 我要找 | 去哪里 |
|---|---|
| 产品最高合同、绝对禁令、开发前五问 | [`CONSTITUTION.md`](CONSTITUTION.md) |
| 当前产品定义与废止方向 | [`PRODUCT.md`](PRODUCT.md) |
| 当前真实状态（生产 / 冻结 / 研究） | [`CURRENT_STATE.md`](CURRENT_STATE.md) |
| 正在进行的真人研究怎么做 | [`docs/CAPABILITY_REACH_LAB.md`](docs/CAPABILITY_REACH_LAB.md) |
| 真人 Case 编号、模板、台账、数据边界 | [`research/capability-reach/`](research/capability-reach/) |
| 2026-09 能力供应侧基线（**无真人证据**） | [`docs/CAPABILITY_SUPPLY_BASELINE_20260919.md`](docs/CAPABILITY_SUPPLY_BASELINE_20260919.md) |
| 本轮长跑的统一报告（进真人之前的清单） | [`research/capability-reach/LONGRUN-REPORT-20260919.md`](research/capability-reach/LONGRUN-REPORT-20260919.md) |
| **收敛候选树 + 三个 fixture + 大陆实测（A–H 八节）** | [`research/capability-reach/CONVERGENCE-REPORT-20260919.md`](research/capability-reach/CONVERGENCE-REPORT-20260919.md) |
| Wave 1 操作包（**WAVE1 EXECUTION = APPROVED**，范围 2 人 × 1 件事） | [`research/capability-reach/WAVE1-PACK.md`](research/capability-reach/WAVE1-PACK.md) |
| 给参与者看的说明（普通话，参加前给他） | [`research/capability-reach/PARTICIPANT-NOTICE.md`](research/capability-reach/PARTICIPANT-NOTICE.md) |
| 资源目录为什么冻结 + 保鲜四字段 | [`catalog/README.md`](catalog/README.md) |
| 历史 V2 版本内核（只约束 `v2` 那条实验线） | [`docs/v2/NORTH_STAR.md`](docs/v2/NORTH_STAR.md) |
| V1 静态站设计真源（已不是线上形态） | [`docs/design/CURRENT_DESIGN.md`](docs/design/CURRENT_DESIGN.md) |
| V0.1 上线与切流的可核对事实 | [`docs/v2/release-c500f3d/CUTOVER-RECORD.md`](docs/v2/release-c500f3d/CUTOVER-RECORD.md) |
| 机器评测集与评测结论（**不是真人证据**） | [`eval/`](eval/)、[`docs/v2/PILOT12_RESULTS.md`](docs/v2/PILOT12_RESULTS.md) |
| 归档设计资产（只读，不得修改或删除） | `archive/design/` |

## 一条不可跨界的纪律

```text
Machine Evidence  ≠  Human Adoption Evidence
```

`eval/` 与 `docs/v2/PILOT12_*` 里那 12 条是**模型跑的测试意图，全程 0 个真人**。
其中任何 "P0=0"、"Gate 1 达成" 都不构成"普通人已经需要 World Space"的证据。
真人 Case 现在数量是 **`REAL HUMAN CASES = 0`**。

## 仓库结构

```text
CONSTITUTION.md         最高产品合同（先读这个）
PRODUCT.md              产品定义
CURRENT_STATE.md        当前真实状态
AGENTS.md               仓库规则（含开工必读顺序）

docs/
  CAPABILITY_REACH_LAB.md            真人实验操作手册（进行中）
  CAPABILITY_SUPPLY_BASELINE_*.md    供应侧基线（无真人证据）
  design/CURRENT_DESIGN.md           V1 设计真源
  v2/                                V2 实验线文档（含发布与切流记录）
  loop/MINIMAL_LOOP.md               Prototype 0（不再是产品契约）
research/capability-reach/           真人 Case 台账、模板、数据边界
eval/                                机器评测集与评测输出
catalog/resources.json               资源目录
paths/                               V1 兜底路径
web/                                 前端（v2/ 为线上那套；index.html 为旧 V1）
server/                              后端（单接口 /api/world + 认证 + 预算闸）
archive/                             历史资产，只读
```

---

## 附：V1 静态站（`web/index.html` + `paths/`）当年给普通人的路径

以下内容描述的是**仓库里仍存在的 V1 静态页**，不是现在公网首页会打开的东西（现在首页在门后，
形态是一个自由输入框「你现在想做成什么？」）。保留是为可追溯；要改线上文案请走 `CURRENT_STATE.md`。

| 你想做的事 | 会发生什么 |
|---|---|
| ✍️ 写点东西 / 🛠️ 做个网页 / 🔍 查明一件事 / 🗂️ 整理资料·处理 PDF | 按需展开面板：一个默认工具 + 可复制的第一步 + 如实限制（做网页的进阶选项：v0 发布上线） |
| 🖼️ 做一张海报 | 要放准确信息→稿定设计模板改字；个人用→豆包 AI 直接画 |
| 📷 整理手机照片 | 去重（手机自带）、备份、印刷相册、修图，每件一个默认做法 |
| 🔤 提取图片文字 | 微信长按、手机相册自带识别、纸质用微信扫一扫 |
| 🌱 不知道从哪开始 | 三步兜底：让 AI 写一段自己的话 → 学会提要求改到满意 → 查一件真事并核实来源（豆包 / 豆包 / DeepSeek，约 10 分钟） |

V1 的选择标准：国内可直接打开、免费开始、中文、手机可用、不用 API Key。
**注意：2026-09-19 的供应侧复核发现这些"免费/额度/水印"主张已有 4 条过期（含稿定、豆包两条高严重度），
逐条与官方证据见 [`docs/CAPABILITY_SUPPLY_BASELINE_20260919.md`](docs/CAPABILITY_SUPPLY_BASELINE_20260919.md) §5。
在上面那批主张被重新核过之前，这些文案不得原样再次对外发布。**
