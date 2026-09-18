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

## NC-06 · 本轮供应侧研究新暴露的施工缺口（只在研究结论指向时才写）

（等 8 个 Pressure Seeds 的审判结果汇总后填；若某条真人候选需要现成能力做适配，
按 `PRODUCT.md` §5 复用优先级先想"接"，不要写进这里当施工许可。）
