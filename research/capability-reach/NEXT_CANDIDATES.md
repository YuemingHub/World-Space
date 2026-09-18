# NEXT_CANDIDATES — 本轮想做但**没做**的事

> 纪律：`AGENTS.md`「现行研究阶段纪律」+ `docs/CAPABILITY_REACH_LAB.md` §16。
> 这里的东西一律**不施工**。每条都给：事实、为什么值得、动什么、代价、谁有权批。

---

## NC-01 · GitHub 默认分支 `main` 上读不到最高合同（**本轮最大的真源缺口**）

**事实**（2026-09-19 实测）：`main` @ `1516515` 是 GitHub 默认分支，上面**没有**
`CONSTITUTION.md`、没有 `docs/CAPABILITY_REACH_LAB.md`、没有 `research/`、没有 `server/` 与 `web/v2/`。
它同时是 `ymai.fun` 的 DNS 已不再指向的旧 Pages 站。

**为什么值得**：任何从仓库页进来的新 agent，默认落在 `main`，会读到一份**没有北极星合同的世界**，
然后按旧 V1 静态站继续微调——这正是 `AGENTS.md` 和 Lab 想阻止的事。

**如果要修，动作是什么**（**本轮一条都没执行**）：

```bash
# 方案 A（推荐，不碰历史）：只把默认分支从 main 切到 research/capability-reach-20260919
gh api -X PATCH repos/YuemingHub/World-Space -f default_branch=research/capability-reach-20260919

# 方案 B（真收敛）：把文档链合进 main，保留 v2 代码另行处理
git checkout main && git merge --no-ff research/capability-reach-20260919
```

**代价与风险**：改默认分支会让 GitHub 上所有既有链接与 PR 基线换目标；合并 main 会牵动
Pages 与那套双端同步配置（`.cnb.yml` 覆盖全部分支）。**这两件都不是本轮授权范围，属 Founder 决定**
（与历史遗留的 `v2 → main` 收敛、Pages 退役是同一件事）。

---

## NC-02 · 机器评测的**原始输出不在仓库里**

**事实**：`.gitignore` 把 `eval/out/` 与 `var/` 排除了；`docs/v2/PILOT12_RESULTS.md`、
`pilot12-raw.md`、`eval/pilot12.json` 是 tracked 的，但**跑出来的那批日志/输出只存在于本机**。

**为什么值得管**：这意味着"P0=0""Gate 1 达成"这类结论，在 GitHub 上**无法被独立复核**。
按本仓库自己的证据纪律（`NORTH_STAR.md` §4.1），结论应当可追溯。

**本轮处理**：只登记，不提交日志（日志里可能含 provider 响应正文，先过 `DATA_BOUNDARY.md` 再谈）。

---

## NC-03 · `healthz` 在未认证情况下暴露运行配置（**观察，未判定**）

**事实**（未登录公网直接取到）：`provider:openai_compatible`、`model:deepseek-flash`、
`search:tavily`、`search_keys:2`、`daily_cap:50`、`monthly_cap_rmb:20`、`month_cost_rmb:1.494026`、
`today_calls:0`、`rate_limit_per_min:20`、`trusted_proxy:true`。

**为什么提出来**：这些不是密钥，但足够让外人知道用哪家模型/搜索、当前预算余量与调用节律。
是否算问题由 Founder 或上层安全审查判断——**本轮不改**（生产、认证、搜索配置都是禁区）。

---

## NC-04 · 前端文案里"V1 七按钮"的残留

`web/v2/` 是线上前端，但仓库里同时存在 `web/index.html`（V1）与 `paths/`。
`README.md` 本轮已把 V1 文案标注为历史；**代码层面的双份前端是否合并/退役，属 V0.2 决定，本轮不动**。

---

## NC-05 · `cases/` 目录**故意不建**

按 `AGENTS.md` 仓库结构规则（不建空目录）与 Lab §16：第一个真人之前，`research/capability-reach/cases/`
不存在。将来由 `TEMPLATE.md` 复制出第一个文件时自然创建。

---

## NC-06 · 本轮供应侧研究产生的施工判断：**不登记施工项**

7 条 Pressure Seeds 审判完成（S5 未审）。结论是：**本轮没有任何一条候选构成"该改业务代码"**。

理由不是没想到功能，而是这轮浮出来的两个真实障碍——`VERIFICATION`（结果对不对没人背书）与
`TRUST`（数据出去之后归谁、被拿去干什么）——按 `CONSTITUTION.md` §07
「能力越强，不等于授权越大」**不能靠更多自动化来填**。
所以正确动作是拿真人去验（Lab §7–§10），不是先写代码。

唯一与代码有关的待办是 NC-08（推荐数据过期）与 NC-01（默认分支），都不是新功能。


---

## NC-08 · 我们对外推荐里有两条已到"误指路"级 —— **本轮只登记，未改数据**

**事实**（详见 `docs/CAPABILITY_SUPPLY_BASELINE_20260919.md` §5，每条都带官方 URL 与行号）：
稿定设计的"免费模板够用"、豆包的无保留"免费"、醒图的"免费修图…消除路人都能做"、
DeepSeek 的旧按钮名「深度思考/联网搜索」——四条与 2026-09-19 现状不符或依据不足；
而 `catalog/resources.json:4` 把这批主张记为 09-07 "free tiers confirmed"。

**可达性已核**：`www.ymai.fun` 与 GitHub Pages 根均 302→`ymai.fun/login`，深层 `web/index.html` 404，
**所以这些旧文案目前公网打不开，是潜在风险而非正在误导人**。

**为什么不顺手改**：①`resources.json` 与 `paths/`、`web/` 文案是产品对外推荐的实质内容，
Lab §16 与本轮代码边界都禁止在施工；②真正要修的不是那四行字，而是**核对的保质期**——
8–12 天就足以让一条推荐变误指路，改字不改机制，下个月还会再错过一遍。

**如果批准修，建议的动作顺序**：
1. 先把 `resources.json:3` 的 `last_reviewed_at` 与 `:4` 的 reviewer_note 更新到实际复核日；
2. 只改有官方证据的那几条措辞（稿定→"可下载的免费模板仅限公益模板；无水印与商用授权要会员"；
   醒图→去掉无保留的"免费"；DeepSeek 路径→改成不依赖具体按钮名的说法）；
3. 把"每条推荐的有效期"写进 Lab 的证据纪律（建议：面向普通人的免费/额度类主张，**超过 30 天不得再对外引用**）；
4. 若要把 V1 文案重新发布，必须先做完 1–2。

---

## NC-09 · 本轮欠下的三件实测（下一轮的第一批活）

1. ~~S5 手机照片整理未审判~~ —— 本轮已回收并判为 `HUMAN_TEST_CANDIDATE`（障碍是 INTEGRATION），
   8 条种子审判全部有归属：4 条 EXIT、4 条待真人验，无一使用猜测填格。
2. **三个 fixture 没跑**：假数字截图 OCR、公开音频转写、虚构手写页识别——都要真调外部视觉/语音服务，
   本轮按"不擅自消耗预算、不碰生产配置"未执行。**这三条恰好直接检验 §V（VERIFICATION）假设**，
   是下一轮最该先跑的。
3. **大陆网络侧可达性 0 实测**：本轮出口在境外（美国西雅图），所有"境外域名/站点在微信里能不能打开"
   都只有商店目录与官方文档作依据。要补一次在中国大陆网络里的浏览器实测。

---

## NC-10 · `research → main` 之外还有一个镜像面

本仓库存在双端同步配置（`main` 上的 `.cnb.yml` 与 `.github/workflows/sync-to-cnb.yml`，覆盖全部分支）。
这意味着**推到 GitHub 的内容可能同步到另一侧托管**。本轮所有研究文档均为无凭据、无个人内容的公开材料，
但 NC-01 的分支收敛动作、以及将来任何"顺手推上去"的东西，都要把这一层考虑进去。
**本轮未对同步配置做任何改动**。

---

## NC-07 · `eval/pilot12.json` 的名字本身是误读源头

**事实**：该文件 `"name": "Reality Pilot 12"`，`"why"` 里写"从 37 条里选 12 条做最小真实调用"。
"Reality" + "真实" 两个词叠在一起，是后来人把它读成"12 个真人"的直接原因。

**本轮处理**：**没改这个 JSON**。理由有二：①`name` 字段是**被读的**——`eval/run.mjs:27` 会把它打印成
`Pilot：${p.name}（12 条）`，而今晚业务代码与评测脚本都是禁区；②`"why"` 里"37 条"与
`eval/reality_eval.json` 自称的"36 条"本来就对不上，要改得连口径一起对平，不该顺手做。

**如果要修**：加一个不参与逻辑的元数据字段即可，例如
`"evidence_class": "MACHINE_ONLY_0_HUMANS"`，并在同一次改动里把 36/37 的口径对平。
**需要 Founder 或总审查点头后另开一轮做**（届时也要重跑一遍引用它的自检，确认没读坏）。

