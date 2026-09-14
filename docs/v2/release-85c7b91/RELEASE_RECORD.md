# WORLD SPACE V0 RELEASE RECORD — 85c7b91

> 本轮身份：Release / Operations。只核实、部署、切流、验证、记录，不做开发。
> 执行人：Qoder CN（本地运维会话）。Founder 指令：`FOUNDER_APPROVED_DEPLOY`。
> 记录时间：2026-09-14 20:30（北京时间）。

## 1. 批准候选与 Git 冻结

| 项 | 值 |
|---|---|
| 仓库 | `YuemingHub/World-Space` |
| 批准分支 | `v2` |
| 批准 SHA | `85c7b91e5252845c541cca211ef48f8748f63ced` |
| 本地 HEAD | `85c7b91e5252845c541cca211ef48f8748f63ced` |
| `origin/v2`（本机 fetch） | 同上 |
| `origin/v2`（服务器独立反查 `git ls-remote`） | 同上 |
| 工作树 | clean |
| commit 父节点 | `723d175`（与本地历史一致） |

未 merge main。未现场改代码。未 cherry-pick。未 hotfix。

## 2. 发布树完整性（跨机独立取证）

服务器从 GitHub 独立取到同一 commit，物化到
`/opt/world-space/releases/85c7b91e5252845c541cca211ef48f8748f63ced/`。

- `git ls-tree -r` 计数 = 110，物化文件计数 = 110
- **逐文件 git blob 哈希比对：checked=110 mismatched=0**（字节级等于批准 commit）
- 本机工作树与服务器聚合哈希不同，原因是本机 `core.autocrlf=true`；以服务器侧 blob 级比对为权威结论

## 3. 发布前 Gate（在服务器真实发布树上重跑）

运行时 `node v20.20.2`（= 生产运行时），shell 内 `WS_*` 变量数 = 0（证明 0 真实 provider 调用）。

`runtime-isolation` `authority` `adapter-shape` `admission` `retry` `liveness`
`xss-boundary` `budget-cap` `date` `outcome-loop` `frontend-e2e` `runtime`
+ `pilot --dry-run` 硬门 → **13 项全部 exit=0**

## 4. 切流前的线上事实（§4）

```
ymai.fun   A     185.199.111.153 / .110 / .109 / .108   TTL 600  → GitHub Pages
www.ymai.fun CNAME yueminghub.github.io                 TTL 600  → GitHub Pages
api.ymai.fun A   39.107.228.76（早已指向本机，本轮未动）
标题：<title>World Space — 你想做什么事？</title>   ← 旧工具站，即 §16 判定"部署错前端"的那句
响应头：server: GitHub.com, HTTP/2, 200
```

## 5. Secret Gate（§6）

| 项 | 结论 |
|---|---|
| `LLM_KEY_CONFIGURED` | yes（`/healthz` 报 provider=openai_compatible, model=deepseek-flash；真实调用成功计费） |
| `SEARCH_KEY_CONFIGURED` | yes（`search_configured=true`；真实搜索调用发生且返回资源） |
| `OLD_TAVILY_KEY_REVOKED` | **yes（Founder-confirmed，agent 未能独立验证）** |

事实经过：核实到笔记本 `var/.env.local` 与服务器 `shared/env/world-space.env` 里是
**两把不同的 Tavily key**（长度均 58、均 tvly 前缀、sha256 前缀 `e1dec51f8b7d` vs `32b9a395ef8f`；
LLM key 两边一致）。Agent 无法从外部判断哪一把曾进过聊天窗口、也无法证明其已失效
（Tavily 控制台 key 列表是唯一真源，且 agent 无该账号访问权）。
Founder 裁决：「服务器那把就是新的，旧的我已删」。本记录按该裁决记 `yes`，并明确标注未独立验证。

Key 文件权限：`-rw------- root:root`，不入 Git（`git log --all -- var/.env.local` 为空，
仓库历史从未提交过 key）。全程无任何 key 值出现在会话、日志或本文件中。

## 6. 部署形态（§9 §10 §13 §14）

```
Internet → HTTPS ymai.fun → Nginx 1.18.0 → 127.0.0.1:3200 → server/world.mjs
```

- 单实例：`ps` 复核只有 1 个 `node .../server/world.mjs`（pid 95250，用户 `wsapp`，非 root）
- 监听：`ss` 显示仅 `127.0.0.1:3200`，公网不可直连
- systemd：`world-space.service` enabled（开机自启）+ `Restart=always`（⊇ 指令要求的 on-failure）
  + 明确 `WorkingDirectory=/opt/world-space/current` + `EnvironmentFile=/opt/world-space/shared/env/world-space.env`
  + `NoNewPrivileges/PrivateTmp/ProtectSystem=full/ProtectHome` + 日志进 journal
- 启动横幅逐项核对：`caps=50/day 20RMB/month fail_closed=true origins=configured rate=20/min liveness=true trusted_proxy=on(127.0.0.1)`
- 生产预算（§8）：`WS_DAILY_CAP=50` `WS_MONTHLY_CAP_RMB=20` `WS_BUDGET_FAIL_CLOSED=1`，
  `/healthz` 回读 `daily_cap=50 monthly_cap_rmb=20 fail_closed=true`，未带测试额度 200
- 反代信任（§11）：`WS_TRUST_PROXY=1` `WS_TRUSTED_PROXIES=127.0.0.1`（本轮新增到 env）
- CORS（§12）：`WS_ALLOWED_ORIGINS=https://ymai.fun`，无 `*`；`www.ymai.fun` 未纳入（见 §10 未决）
- 日志隐私（§14）：journal 只含 status/latency/llm/search/retry/cost/budget，无 intent 正文

## 7. 本轮发现并修复的两处配置错误（均为运维配置，非代码）

### R-1 服务器 env 与已验证配置漂移（导致 §17 首轮必失败）

服务器 env 停在代码默认 `WS_MAX_TOKENS=1500 / WS_TIMEOUT_MS=60000`，
而真实验证过的开发机是 `6000 / 90000`。1500 输出 token 把 compose 的 JSON 拦腰截断
→ 两轮全部 `502 llm_bad_json`（`llm=2 retry=2`，重试也救不回截断）。
已按已验证值对齐并重启。**这是发布配置缺陷，不是模型缺陷。**

### R-2 Nginx `proxy_read_timeout` 起短了（我自己引入）

首版写 120s。实测 2026-09-14 20:07 一条请求 Node 真实耗时 **123.5s**（90s 单调用 × 重试），
nginx 抢先返回 **504**，用户会看到网关页而不是产品的诚实失败页。已抬到 **180s**，
与本机 ymai.love 块同一理由（read timeout 必须大于上游超时）。

### R-3 测试工具链把中文打成乱码（我的取证缺陷，结论已作废重取）

在 Git Bash 里用 `-d '{"intent":"中文…"}'` 构造请求体，被 Windows 控制台 GBK 破坏，
服务端收到乱码。模型如实回答「这句话在传输中出现编码损坏，我读不出具体内容」并拒绝猜路径
——**产品行为正确**（内容诚信在真实边界生效），但：

1. 由此得出的「切流后 5 条真实请求 3 条 502 ≈ 40% 失败率」**统计不成立，已作废**：
   那几条输入本身是乱码，不能用来推断正常输入下的坏 JSON 率。
2. 干净 UTF-8 载荷（服务端构造）的 §17 本机两轮：`200 / 200`，`retry=0`，
   `receipt_ingested=true`，第二轮未重答第一轮。
3. 正确做法：`-d @file`（UTF-8 落盘）或在服务端构造 JSON。

## 8. 生产 smoke 结果

| # | 项 | 结论 | 证据 |
|---|---|---|---|
| 1 | 首页 | **PASS** | 真实浏览器打开 `https://ymai.fun/`：h1=「你现在想做成什么？」、第三方隐私披露在页、旧站工具入口残留 0、`isSecureContext=true`、控制台 0 报错 |
| 2 | 真实 API | **未完成** | 见 R-3：该批输入被 GBK 破坏，需干净重发 |
| 3 | 生产闭环两轮 | **未完成** | 同上（本机 §17 已 PASS，生产域名下待重取） |
| 4 | 无需 AI 的场景 | **部分** | 乱码输入下产品未把问题硬塞给 AI，而是要求重述；正常输入下 mode 分布待重取 |
| 5 | handoff UI | **PASS** | 生产 `/render.mjs` 受控契约：链接 `href` 精确 `https://chat.deepseek.com/`、`rel=noopener noreferrer`、任务书原文完整入 copy 槽；非白名单目标 `EvilGPT` → 0 链接；`handoffLink('deepseek')` 命中、`('EvilGPT')/('')` 返回 null |
| 6 | Receipt | **按钮渲染 PASS / 提交未完成** | 做成了 ✓ / 卡住了 / 粘贴结果 三按钮在生产静态资源渲染齐备；点击→输入框→提交需一次真实往返 |
| 7 | 刷新恢复 | **PASS** | 真实生产源 `https://ymai.fun` 写 `ws.loop.v1` → reload → 恢复横幅「这是你上次进行到的地方（只存在这台设备上）」+ 唯一主行动块（个数=1）+ `done_when` 显示 + 模式标签 + 三按钮 + 来源链接带 `noopener noreferrer` |
| 8 | 新目标 | **PASS** | 点「换个新目标」→ localStorage 已清、主行动块 0、横幅消失、回首页空输入框 |
| 9 | 失败态 | **PASS（隔离实例）** | 假网关实例：`502 {"error":"intelligence_unavailable","code":"fetch failed"}`，响应体**只有 code/error**，无 understanding/next_action（不展示半成品）；生产凭据未参与 |
| 10 | 预算 | **PASS（隔离实例）** | 种子 49/50 × 6 并发 → 账本终值**恰好 50**，未突破；生产账本一字未动（仍 calls=27 / 0.833604） |
| 11 | CORS | **PASS** | 生产 Origin 预检 204；陌生 Origin `403 origin_not_allowed`（未触达 LLM）；成功响应 `access-control-allow-origin: https://ymai.fun`；无 `*` |
| 12 | 移动端 | **部分 PASS** | 桌面 1280 真截图正常；320/390/414 用容器宽度强制测得 `scrollWidth == 容器宽`（结果页含交棒块/超长 URL 来源卡/三按钮行）**无横向溢出**；但无头 Chrome 最小窗口宽度钳制使 `--window-size=320` 截到的是 ~480px 布局裁切图，且受控浏览器面板隐藏使 `getBoundingClientRect` 全为 0 → 像素级窄屏取证本轮未拿到 |

## 9. 费用与账本（真实数字）

- 月累计（截至记录时）：`month_cost_rmb = 0.833604`，`today_calls = 27`，上限 50/日、20 元/月
- 本轮真实开销构成：配置修复前的 2 条失败 0.055 元；修复后成功两轮 0.152 元；
  乱码批 5 条 0.47 元（其中 3 条 502 仍计费，因重试已实际调用 provider）；CORS 探测 3 条 0.027 元
- **教训**：坏 JSON 的 502 不是免费的 —— 每次重试都真实计费。测试输入必须先确认编码，
  否则钱花在乱码上。
- Founder 批准本轮冒烟上限 ¥1，已用 0.8336，**剩余 0.166 元不足以完成 Smoke 2/3/4/6 的干净重发**（约需 3–4 条 ≈ 0.25–0.35 元）→ 停在此处等追加授权。

## 10. 未决与回滚资产

未决（不阻断当前线上，但需 Founder 定）：

1. 冒烟预算追加（见 §9）
2. `www.ymai.fun` 仍 CNAME 到 GitHub Pages 旧站；`ymai.fun` 已在新站。是否一并收敛，
   以及要不要把 `https://www.ymai.fun` 加进 `WS_ALLOWED_ORIGINS`
3. `OLD_TAVILY_KEY_REVOKED` 目前只有 Founder 口头确认，agent 无法独立验证
4. 窄屏像素级取证需要一次可见视口的浏览器（受控浏览器面板隐藏时视口为 0）
5. 旧 `6e73725` release 与 GitHub Pages 全部保留，未删任何东西

回滚（已备好，未执行）：

```bash
# 入口层
rm -f /etc/nginx/sites-enabled/world-space && nginx -t && systemctl reload nginx
systemctl stop world-space.service        # 回滚前该 unit 处于 disabled+inactive
# env（本轮有两个带时间戳备份，600）
cp -a /opt/world-space/shared/env/world-space.env.bak-pre-20260914-194228 \
      /opt/world-space/shared/env/world-space.env && systemctl restart world-space.service
# 代码：current 指回旧 release
ln -sfn /opt/world-space/releases/6e7372533aeb6f557552b7488d91232336755aa8 /opt/world-space/current
```

```
# DNS：一条改值 + 三条重新启用（全部未删除，RecordId 固定）
UpdateDomainRecord 2063597443132248066  @ A 185.199.111.153
SetDomainRecordStatus 2063597443132248065 ENABLE   # 185.199.110.153
SetDomainRecordStatus 2063597443132248064 ENABLE   # 185.199.109.153
SetDomainRecordStatus 2063557090689779712 ENABLE   # 185.199.108.153
```

DNS 变更前全量快照：`dns-before.json`（本目录，6 条记录含 RecordId/TTL/Status）。
入口配置留档：`nginx-world-space.conf`（本目录，与服务器生效版一致）。

## 11. 其它产品零改动核对

`ymai.me`（MingOS 8081/3400）、`ymai.love`（Family Space 3001）、`mingos.cn`、
`self-space`、`family-os` 全程只读；切流后逐个复测 **HTTP 200**。
裸 IP 与未知 SNI 仍落 `000-ops-default-deny` 的 444 / `invalid.local` 黑洞。
监听端口面：22 / 53 / 80 / 443 / 3000 / 3001 / 3200 / 3400 / 8081 —— 除新增 3200 外无变化。
临时隔离测试实例（3909/3910/3911）已全部回收，无残留监听。
