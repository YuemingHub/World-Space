# AI 从零开始 · v0.1 最终验收报告

> 唯一最终验收报告。
> **当前状态（Commander 2026-11-01 裁决）**：`WS_AI_V0.1_CODE_ACCEPTED` / `REAL_USER_EVIDENCE_PENDING` / `PUBLIC_RELEASE_HOLD`
> 生成时间：2026-11-01 01:50 +08:00 · 执行：Deep（Builder）· 独立验收：final-checker（独立会话、干净副本、仅可写自己的证据目录）
> 本报告只写**能被复跑或能指向外部证据**的结论；作者自测不替代独立验收。

---

## 0. 一句话

`ymai.fun/ai/` 的候选已完成并通过独立终审：**P0=0 / P1=0 / P2=0 / P3=0**，8 个验收维度里 7 项 VERIFIED、1 项 BLOCKED（真人验证 = 0，工程无法替代）。
**尚未合并、尚未发布**；发布执行方固定为**总运维窗口**。

### 0.1 交付身份（三个 SHA，别混用）

| 角色 | SHA | 含义 |
|---|---|---|
| **代码验收基线（历史）** | `888a97726c9a63ebbb7a3c74abc6b99ddbb3a0d8` | 独立终审在这上面跑到 **8 维度 7 VERIFIED / 1 BLOCKED、160/160 独立断言全绿**。Commander 的 `CODE_ACCEPTED` 针对这一份**代码**。 |
| 当前分支 head | 见 PR #34（以远端为准） | 在 `888a977` 之后**只增加了本报告**，代码零改动。 |
| 远端 main | `3f619d1676f10efa4e8e69517ce16cd4f201f793` | **未改动**。 |

**`888a977 → 956bb4a` 的差异证明**：`git diff --name-only 888a977 956bb4a` 只有 `docs/ai-beginner/FINAL-ACCEPTANCE.md`（新增 155 行）；`git diff --name-only 888a977 956bb4a -- web eval scripts` 输出为空。
也就是说：**代码验收结论对当前 head 仍然成立**，但**不要把"当前 head 上的测试数字"说成"在 888a977 上重跑过"**——两者是同一份代码，证据来源是历史那一次。

| 项目 | 值 |
|---|---|
| 仓库 | `YuemingHub/World-Space` |
| PR | https://github.com/YuemingHub/World-Space/pull/34 （**DRAFT**，base `main`） |
| 分支 | `feature/ai-beginner-20261031` |
| 与 main 的差异（`git diff --name-status origin/main <head>` 实测） | 22 个新增 + 2 个修改（`README.md`、`web/index.html`）；根 `index.html`、`CNAME`、`.cnb.yml`、`.github/**` 未动 |

---

## 1. 文档事实差异与修正（Commander 指令第一项）

Commander 指出：PR 实际改了 `web/index.html`（首屏新增一行入口），但 `RELEASE.md` 仍写"旧首页没有新入口 / web/index.html 未改动 / 回退仅删目录"。**确认属实**。

**精确 diff**（`git diff origin/main..888a977 -- web/index.html`）：

```diff
-  <h1>你想做什么事？</h1>
+  <p style="text-align:center;font-size:15px;color:#6B7280;margin:0 auto 8px;max-width:520px"><span style="white-space:nowrap">第一次用 AI、完全不懂？</span><a href="ai/index.html" style="color:#2563EB;font-weight:600;white-space:nowrap;display:inline-block;padding:8px 2px">从这里开始：AI 从零开始 →</a></p>
+    <h1>你想做什么事？</h1>
```

只有这一处；`index.html`（根跳转页）、`CNAME`、`.cnb.yml`、`.github/workflows/*` **零改动**（`git diff --name-only` 无命中）。

**修正后**：

| 文件 | 修正内容 |
|---|---|
| `docs/ai-beginner/RELEASE.md` | §1 改动范围、§5 第 6 条、§7（发布形态已裁决）、**§8 回退表（逐文件）+ 回退后三条验收**、§8.1「候选存在 ≠ 线上已发布」 |
| `docs/ai-beginner/PRODUCT.md` §10 | 写入 Commander 裁决 `PARALLEL_AI_ENTRY`；删掉与代码冲突的「不改首页」；写明「本候选在 web/index.html 首屏新增一行链接」 |

**回退说明**（RELEASE.md §8，已包含三项）：①撤回 `web/ai/**`；②`git checkout origin/main -- web/index.html` 恢复旧首页那一行；③按三条验收确认七个目标按钮、三步兜底、`/` 跳转、`/ai/` 404 回位。
**不为修文档改产品定位；除下面第 3 项外，本轮未改网页结构。**

---

## 2. 三条路径与原站回归结果（独立复验）

| 项 | 结论 | 证据 |
|---|---|---|
| 三条路径可达性 | **VERIFIED** | 首页三个入口各一次点击进入；路径一 4 段、路径二 4 段、路径三 5 段；每段有"做成"判据、复制按钮、"卡住了怎么办" |
| 复制 / 勾选 / 刷新恢复 / 回退展开 | **VERIFIED** | journey 断言实际读取剪贴板内容；勾选后 reload 仍保留；`details.stuck` 点击后 `open=true` |
| 原站回归 | **VERIFIED** | 七个目标按钮 + 三步兜底全在；点「写点东西」仍展开；AI 入口全站仅 1 处；`/` 仍跳 `web/index.html`；320/390 无横向溢出 |
| 路径一「做成」判据 | **VERIFIED（本轮修正）** | 原判据「发出去并且收到回应」以他人反应为判据 → 改为「真发出去（或存草稿、念给人听）即完成，不需要等谁回复；对方回什么不是你的成果指标」。页面正文、首页摘要、**og 分享卡片**三处一致 |

---

## 3. 自测与真实浏览器旅程（在代码验收基线 `888a977` 上执行）

> 口径：本节数字是 **2026-11-01 在 `888a977` 上真实执行**的记录。`888a977` 之后只增加了本报告，
> 代码零改动（`git diff --name-only 888a977 <head> -- web eval scripts` 为空），
> 因此这些数字对当前 head **成立**，但**不是**在当前 head 上重新跑出来的——证据来源仍是那一次。

| 命令 | 结果 | 位置 |
|---|---|---|
| `node eval/ai-beginner-selftest.mjs` | **285/285，exit 0** | 2026-11-01 01:47 执行记录 |
| `node eval/ai-beginner-journey.mjs` | **70/70，exit 0** | `var/ai-journey/20261101T…/`（`var/` 不入库） |
| 独立 Checker 自有断言 | **160/160，exit 0**（三轮以来首次全绿） | `ws-final-checker-20261101/`（本机，未入库） |
| 变异测试 | 作者 selftest 在 4 类注入下**均变红**（年龄口径、v0 事实、12355、路径一 og/首页摘要、双日期） | 同上 |

**A8 口径声明**：浏览器自动化通过 **不等于** 真人体验成功。上面的 70/70、160/160 只证明"页面行为与契约一致"。

---

## 4. 外部工具与年龄条款复核证据（2026-11-01 重抓）

| 工具 | 页面写的 | 官方原文（独立 Checker 自抓，19/19 逐字一致） |
|---|---|---|
| 豆包 | 未满 18 须监护人；不满 14 按"儿童"须监护人同意 | 《用户协议》2.1/12.1、《隐私政策》7.1–7.3 |
| DeepSeek | 未满 18 须监护人 | 《用户协议》2.1；隐私政策以不满 14 为儿童 |
| v0（Vercel） | 16 岁 | Vercel Terms "at least 16 years of age" |
| Stirling PDF | 18 岁；官方只提供电脑端 | Terms "intended for users 18 years or older"；下载页仅 Windows/Mac/Linux/Docker |
| 稿定设计 | 免费导出**通常**限于"公益免费"模板 | （措辞已降级为可核实表述，不再断言唯一条件） |

18 个外链全部实测可达（`evidence/urls.json`，本轮重跑覆盖）。两项无法核实的事实已按"降级措辞"处理，不再写成断言。

---

## 5. 独立 Checker 报告

| 轮次 | 抓到的关键问题 | 处理 |
|---|---|---|
| 事实核查 1–3 轮 | 2 条 P0（年龄口径写反、v0 事实写反）；1 条**空转断言**（我的守卫恒为真） | 全部修；守卫改为可证伪 |
| 可用性 1–3 轮 | 1 条 P0（首屏「不用注册」与路径需登录冲突）；若干 P1；4 条回归 | 全部修 |
| **终审 1–3 轮** | 3 条 P2（og 卡片残留旧判据、页脚链接 28×44、标题锚点 24px）+ 4 条 P3 + 2 条 UNKNOWN | 全部关闭 |

报告路径（**未入库**，按合同要求保留在 Builder 本机，含本机路径）：
`D:\服务器\repos\ws-final-checker-20261101\{REPORT.md, REVERIFY-790ffaa.md, FINAL-888a977.md}`

**脱敏摘要与复跑方法**：已入库为 `CHECKER-EVIDENCE.md`（只含结论、命令、退出码与路径占位符，不含本机绝对路径、不含参与者任何信息）。原件仍留在 Builder 本机，**不公开入库**。

**已知限制（独立 Checker 明示，不阻塞）**
- L-1 事实守卫是字符串匹配：防复犯、不防改写。
- L-2 日期断言只守「复核于」措辞。
- L-3 旧首页入口在 320–390 下提示句与链接分两行（刻意，箭头不掉行）。
- L-5 作者 journey 不含事实/隐私断言（设计如此，守卫都在 selftest）。

---

## 6. `/ai/` 发布与回退方案

全文：`docs/ai-beginner/DEPLOY-AI-ROUTE.md`（2026-11-01 v2，按真实生产身份重写）。

**已证实**（一次只读 SSH 调查，未改任何文件、未 reload、未部署）：
主机 `iZ2ze97l6qb4ej1dz40ku6Z`；nginx 1.18.0；ymai.fun 仅 2 个 server 块（80 301 + 443）；无 CDN/缓存层；
`world-space.service` 的 `current` → `releases/3e8e15f1…`；静态目录 `/var/www/ymai.fun-static`（`/ming/` 由 snippet 直读磁盘，11 个文件，磁盘与公网 md5 一致 29,892 字节）；`/` 的 302 与 `/healthz` 由 Node 发出；3200/3201 只绑 127.0.0.1。

**方案**：在已被 443 块 include 的 `snippets/ming-portfolio.conf` 追加

```nginx
location = /ai { return 301 /ai/; }
location ^~ /ai/ {
    root /var/www/ymai.fun-static; index index.html;
    try_files $uri $uri/index.html $uri/ =404;
    add_header Cache-Control "public, max-age=300";
}
```

+ 把 `web/ai/` 拷到 `/var/www/ymai.fun-static/ai/`。
**不动** `location /`、Node、webDir、`/ming/`、DNS、Pages；`^~ /ai/` 不会命中 `/api/`（已论证并警告"绝不能写成 `^~ /a/`"）。
**12 条发布后双侧验证** + **一条命令级回退**（删 location → `nginx -t && reload` → 移走目录，**不需重启 Node**）。

**执行权**：`/srv/OPS.md` 规定生产 nginx 由总运维窗口执行，开发只交 SHA + 发布说明 + 证据；`/srv/ops-drift/` 哨兵基线新鲜。
**状态**：`RUNTIME_IDENTITY_VERIFIED`，发布**待授权**（两条路：总运维执行 / 明确授权本窗口执行 ②③ 两段）。
**交接风险**：运行中 release `3e8e15f1` 与 nginx 注释里的候选 `85c7b91e` 不一致，无法判断是"注释未更新"还是"曾回滚"；不影响本方案。

---

## 7. 仍然保留的发布前条件（不得假装已完成）

| # | 条件 | 状态 |
|---|---|---|
| 1 | 运营主体、备案适用性、公开联系方式 | **未完成**（需 Owner 决定主体与路径） |
| 2 | 正式生产部署身份与路由验证 | **身份已证实**；路由未落地（待授权执行） |
| 3 | 一名孩子 + 一名成人零基础者的真实体验 | **未完成（`NOT_YET_TESTED`）**；方案已就绪：`REAL-USER-TRIAL.md`（任务卡 + 观察表 + 判据）。需 Owner 授权"找人" |
| 4 | 外部工具年龄条款正式发布前复核 | **已完成到可核实程度**（19/19 官方原文比对）；发布前建议再跑一次 |
| 5 | 对未完成验证的内容保持准确披露 | **已做**：`RELEASE.md` §6、本报告 §7、页面本身不宣称任何未验证能力 |

---

## 8. 状态

**`WS_AI_V0.1_CODE_ACCEPTED` / `REAL_USER_EVIDENCE_PENDING` / `PUBLIC_RELEASE_HOLD`**（Commander 2026-11-01 裁决）

未合并、未部署、未宣称上线。**发布执行方固定为总运维窗口**。

下一步只剩两件，都不是工程动作：

1. **真人验证**：按 `REAL-USER-TRIAL.md` 执行。**未执行前，本仓库任何文件都不得声称"零基础的人看得懂"**——当前真实状态是 `NOT_YET_TESTED`。
2. **合并与发布授权**：Commander 决定时机后，由总运维按 `DEPLOY-AI-ROUTE.md` 执行；本轮不碰 nginx、不碰生产目录。
