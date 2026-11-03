# GPT REVIEW R2 — World Space v2 边界修复轮

> 2026-09-13。针对 GPT 独立审核 R1–R4 的修复轮：只修边界，不改产品方向、不加功能、不部署。
> 本轮真实发现已入 Failure Ledger（L14–L17）。

## 0. Git

- base SHA：`6e7372533aeb6f557552b7488d91232336755aa8`（origin/v2，与 R1 审核基线一致，已先行核验远端）
- final SHA：见 `git log -1`（本文件随最终提交入库，branch `v2`，main 未动）

## 1. R1 · 前端 HTML 属性 / URL 安全边界

- **根因**：`web/v2/app.js` 的 `esc()` 按 text→innerHTML 设计，不转义引号，被直接用于 `data-copy="…"`、`href="…"` 属性拼接——一个 `"` 即可逃出属性注入 `onerror`/`onfocus` 等新属性。同时服务端证据表对 URL scheme 不设防，`javascript:` / `data:` 可经搜索结果变成可点击链接。"可点击 source_url 必须是 http(s)" 没有作为不变量存在于任何一层。
- **修复**（结构性，不是补 replace）：
  1. 渲染纯函数拆到 `web/v2/render.mjs`（app.js 与安全回归共用同一份代码）；
  2. `esc()` 升级为文本/属性通用转义（`& < > " '` 全转，属性逃逸不可能）；
  3. 复制文本不再进 HTML：渲染只留 `data-copy-slot` 数字槽位，原文在渲染后经 `dataset`（DOM property，不经过 HTML 解析）赋值，点击处理器读原文，废除手工反转义链；
  4. `httpUrl()` 白名单：解析失败或协议非 http/https 一律返回空串，调用方不给 `<a>`（宁可不给链接），改为显示"该来源的链接未通过安全校验，不提供点击"；
  5. 服务端同规则双保险：`server/evidence.mjs` 证据表入口只签发 http(s) URL，非 http(s) 的"搜索结果"不编号、不给模型引用机会；
  6. `index.html` 改为 `<script type="module">`，静态服务补 `.mjs` 的 JS MIME。
- **新增攻击测试**（`eval/xss-boundary-selftest.mjs`，18 项断言）：`"`、`"><img src=x onerror=…>`、`" autofocus onfocus=… autofocus="`、`"/><svg onload=…><"`、`javascript:alert(1)`、`JaVaScRiPt:`、`data:text/html,…`、协议相对 `//`、`file:`、非 URL、含 `& < > ' "` 的正常中文动作。验证方式是标签白名单 + 属性名白名单的结构审计（注入 `onerror` 会以"新属性名"出现，白名单立刻抓住，不靠子串猜），加 href 全 http(s)、复制原文往返、全链路 HTTP（xss 桩经真实管线）。
- **真实 DOM 验证**：xss 桩在受控浏览器中提交后，`window.__xss_injected` 未定义（零脚本执行）、结果区零 img/svg/script 标签、零 on* 事件属性、零链接、全部载荷以纯文本显示、复制原文完整（详见 §5）。

## 2. R2 · 并发预算硬上限

- **根因**：原 `countCall` 是"provider 调完记账"，检查（请求准入时）与调用之间存在并发窗口：账本 49/50 时 N 条并发各自通过检查再各自调用，付费调用可达 49+N 次。已证明的"4 并发 → 账本 4"只说明计数准确，不说明上限硬。
- **修复**（准入/预留语义，不是事后记准）：`admit` = 检查 + 预占 + 落盘，是同步的一段代码、中间无 await，事件循环保证并发请求不可能同时穿过同一次检查。每次付费调用前先占 1 个名额与最坏成本（LLM：max_tokens 输出 + 1 万 token 输入估算；搜索：按次实价；桩：0）；返回后 `settle` 按实际用量多退少补，provider 失败全额退预留。被拒请求得到 429 `budget_exceeded`（注明 daily_calls / monthly_budget 与人工降级路径）。未用全局大锁串行化整个请求生命周期——临界区只有 admit 内的同步段；单实例架构不变。请求中段的旧 `overCap` 快照检查移除（它读的是过期副本），准入只剩 admit 一个语义点。
- **新增攻击测试**（`eval/budget-cap-selftest.mjs`，本地 mock 延迟网关）：D1 日上限临界（种子 49/50，6 并发）→ 恰好 1 条 200、5 条 429、**网关只收到 1 个 LLM 请求**（证明被拒请求根本没碰到 provider）、账本终值=50 不多不少；D2 月预算临界（剩余恰好一次 LLM 预留 0.032 元，4 并发）→ 1 条 200、3 条 429 monthly_budget、结算后账本 ≤ 上限且调用数=1。
- **不回归**：retry-selftest 场景 C（4 并发在途交叠总账=4）、runtime-selftest 16 路并发（48 次总账）原样通过。

## 3. R3 · 日期真源统一

- **根因**：L7 只修了 world.mjs（UTC→本地），`server/guard.mjs` 的 `checked_at` 仍用 `toISOString().slice(0,10)`——仓库里存在两套"今天"，上海时区 00:30–08:00 之间同一张资源卡片的核实日期是"昨天"，与预算日切分叉。
- **修复**：新建 `server/date.mjs`（`localDate`/`localMonth`）为唯一业务日期真源；world.mjs（预算日切、模型上下文里的 today）与 guard.mjs（checked_at）一律从它取。业务日界 = 主机时区日界，全仓库一个语义。
- **新增攻击测试**（`eval/date-selftest.mjs`）：TZ=Asia/Shanghai 子进程注入四个边界时刻——00:30、07:59:59、08:00:01、23:59:59——业务日期全部是当天（2026-09-13），并以同一时刻 UTC 日期=2026-09-12 作负控（证明不是恒等断言，旧实现就会给出前一天）；TZ=UTC 主机验证语义一致；guard checked_at 与 `localDate()` 同源断言；`server/**` 静态扫描：UTC 切片 / 本地 today 函数残留 = 0。

## 4. R4 · Reverse Proxy 限流语义

- **根因**：limiter 只读 `req.socket.remoteAddress`——Nginx → Node 部署后所有访问者都是 127.0.0.1 共享一个桶；而无条件信任 X-Forwarded-For 则任何客户端可伪造头绕开限流。
- **修复**（采用审核建议的最小安全方案）：默认只认 socket 对端地址，客户端发来的 XFF 一律不看；显式 `WS_TRUST_PROXY=1` 且对端在受信代理名单（`WS_TRUSTED_PROXIES`，默认 127.0.0.1/::1）时才读 XFF，取**最右一个合法 IP**（受信代理把"它看见的地址"追加在最右，客户端伪造的头被顶掉）；XFF 缺失或全非 IP 回落对端地址。只支持单层受信代理；Node 保持默认只监听 loopback；`/healthz` 如实报告 `trusted_proxy`。
- **新增回归**（`eval/runtime-selftest.mjs` 实例 3/4）：①direct request（未开信任）——每条换伪造 XFF 仍在同一桶，第 4 条起 429（换个头绕不过）；②trusted proxy request（开信任）——同 XFF 客户端第 4 条 429、不同 XFF 客户端独立桶互不牵连、按转发 IP 限流真实生效；③spoofed X-Forwarded-For without trusted proxy——①即证：伪造头不产生独立桶。

## 5. 全量回归

全部本地/mock，0 真实 provider 请求；真实模式代码路径由 D1/D2 的 openai_compatible mock 网关覆盖。

| Gate | 结果 |
|---|---|
| runtime-isolation（生产路径 0 评测引用） | ✓ |
| authority（授权正负控 + 残留检查） | ✓ |
| adapter-shape（搜索适配层形状 + Bearer-only） | ✓ |
| admission（F1/F2 矩阵 + S2-d 复放 + 时效旗标） | ✓ |
| retry（坏 JSON 一次重试 + 并发计数 C） | ✓ |
| liveness（404/410 剔除、超时保守保留） | ✓ |
| runtime（CORS/限流/隐私/16 路并发 **+ 新增 R4 实例 3/4**） | ✓ |
| frontend-e2e（HTTP 层 + module/MIME 断言） | ✓ |
| **xss-boundary（新）** | ✓ 18 项 |
| **budget-cap（新）** | ✓ D1/D2 |
| **date（新）** | ✓ 时区边界 |
| pilot 硬门：stub ok（S5 两条 0 P0）、stub bad（裁判抓 P1）、`--pilot --dry-run`、超限 `PILOT_CASE_LIMIT_EXCEEDED`（exit 2） | ✓ |

## 6. 受控浏览器结果（内置受控浏览器，未触碰本机其他浏览器）

- **桌面 1280 全链路**：输入"我家楼下每晚有人唱歌到十二点…" → 提交 → 理解/追问/路径/资源卡渲染完整 → 追问作答"是楼下商户的音响…" → 第二轮真实发生（服务端日志 2 次 POST，预算 calls 3→6→9 如实递增）→ source link `https://jubao.mee.gov.cn/netreport/netreport/index`（target=_blank、rel=noopener noreferrer、http(s)）→ 复制按钮（dataset 原文完整）→ 反馈"做成了"再走一轮。
- **320 / 390 / 414**：三档各走一条完整链路（输入→提交→结果渲染），横向溢出 0（scrollWidth=clientWidth），来源链接与复制原文全部正常。
- **xss 对抗桩真实 DOM**：提交后 `window.__xss_injected` 未定义、结果区 0 个 img/svg/script、0 个 on* 事件属性、0 个链接、全部攻击载荷以纯文本可见、复制原文完好。
- **如实注明**：①内置浏览器输入管线中途卡死（已知环境坑），点击改经页面原生 `element.click()` 触发——走的是产品真实 onclick 处理链，交互语义不变；②该环境不授予剪贴板权限，复制按钮落到诚实失败路径（"复制失败——长按文字手动复制"，原文无损）——复制数据完整性由 dataset 原文与单元回归证明；③输入页截图成功（样式/字体/布局正常），结果页截图因 IAB guest 截图缺陷失败，以 DOM 审计数据为证。

## 7. Remaining Weaknesses（如实）

1. 预算硬上限是**单实例**语义：多进程/多机部署需要集中配额或共享锁，当前架构明确不做（部署形态 = 单实例 + 反代）。
2. LLM 预留额按 max_tokens + 1 万输入 token 估算；实际用量超过估算的极端情况由 prompt 尺寸上限兜住，但预留与结算之间存在短时账面偏高（多退少补已消除终值偏差）。
3. R4 只支持**单层受信代理**；CDN→Nginx→Node 多级链需按真实拓扑配置 `WS_TRUSTED_PROXIES` 并逐层核验。
4. 业务日期跟主机时区走：部署到非上海时区主机时，"今天"与预算日切随主机（部署约定，文档已写明）。
5. XSS 边界覆盖当前全部渲染面（纯文本渲染 + dataset 复制 + http(s) 链接）；若未来引入 markdown/富文本渲染，必须另立消毒层，本轮白名单审计不可复用于该场景。
6. 上轮遗留项不变：延迟 p50 ≈ 35–40s、裸医疗警告语过准入靠人工兜底、方舟 key 待 Founder 核对、Tavily 旧 key 待轮换（发布前必须）。

## 8. Failure Ledger

`docs/v2/FAILURE_LEDGER.md` 新增 L14（属性逃逸/危险 scheme）、L15（并发穿透上限）、L16（两个"今天"）、L17（反代限流），均含根因/最小修复/回归/剩余边界。

## 9. 状态

```text
READY_FOR_GPT_REVIEW_R2
```
