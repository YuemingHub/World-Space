# PRE-DEPLOY HANDOFF — World Space v2 智能层

> 2026-09-13。交给本地主运维的唯一未竟动作：**真实部署 + 生产 smoke**。
> 本文是部署前最后一份文档；所有 Gate 状态见 §9。

## 1. Git

| 项 | 值 |
|---|---|
| branch | `v2`（唯一智能层分支；`main` 未动，仍是线上静态站） |
| final SHA | 见推送后 `git log -1`（本文随最终提交写入） |
| origin/v2 | 已同步（`git status -sb` 显示无 ahead/behind） |
| working tree | clean |

## 2. Product

**真实用户旅程**：打开页面（同源 `GET /`）→ 看到「你现在想做成什么？」+ 第三方披露 →
输入一句真实的话 → 诚实 loading（20–60s，有秒数提示）→ 结果页按序呈现：
理解（可改）→ 该问的问题（可作答回炉）→ 建议路径 → 世界上已有什么（来源+授权徽章+核实日期+外链）
→ 还没把握的事（黄区）→ 现在只做的一步（可复制）→ 做成了/卡住了（带话反馈重想）。

**已验证场景**（真实 model + Tavily，0 P0）：AI 求职×5、带老人旅行×5、夜间噪声×6、
教育变现×5、养老照护×5、个人建站×5、模糊方向/路灯报修/情绪包裹/地域差异/最新政策×5。
亮点证据：路灯题把人导向报修编号而非 AI；政策题引用红线文件但不断言能与不能；
医疗风险全部交还医生；未经授权来源的高风险结论被实时删除；2019 年旧证据被自动标注时效。

**已知边界**：p50 延迟 38s（前端有诚实 loading）；理解正文偶尔引用常识性数值不走资源绑定
（观察项）；无量词的裸医疗警告语仍可能以 normal 过准入（靠人工复核兜底）；反馈回路目前单轮。

## 3. Architecture

```
浏览器 ── GET / (web/v2 静态页，同进程托管)
       ── POST /api/world {intent, answers[]}
            1. 来源白名单 + 每 IP 限流 + 请求体 ≤20KB
            2. 预算 fail closed（文件账本，每次计数磁盘重读）
            3. LLM triage（坏 JSON 同任务重试 1 次，逐次计费）
            4. 搜索词最小化 → Tavily（Bearer-only）→ 链接存活检查（404/410 剔除）
            5. 服务端签发 e1..eN（模型只见 id）
            6. LLM compose（只引 id）→ guard（风险×授权 admission / 路径 backing 统一 /
               时效旗标 / 高风险撤回 / 中性兜底）→ 契约校验（不过 502）
       ── GET /healthz（只报配没配，不回显 key）
```

- model provider：OpenAI 兼容网关（现用 deepseek-flash）
- search provider：Tavily（仅取 results；answer 能力固定关闭）
- 状态：唯一写盘 = 预算账本 JSON（计数与金额，无用户正文）；无数据库/会话/队列

## 4. Security / Privacy

- CORS：`WS_ALLOWED_ORIGINS` 白名单（逗号分隔）；本机来源（localhost/127.0.0.1）默认放行；
  陌生来源 403 且无 CORS 头；OPTIONS 正确应答
- 滥用：`WS_RATE_LIMIT`（默认 20 次/分/IP，超限 429 + 诚实降级文案）
- 日志：仅状态码/耗时/调用计数/金额——**不含 intent 正文**（有自测断言）
- key：只在 `var/.env.local`（已 gitignore）；错误信息只带状态码（有自测断言）
- **部署前必做**：Tavily 旧 key 已进过聊天记录 → 控制台 **rotate/revoke** → 新 key 写入本机
  `var/.env.local`（运维自行执行，不经对话）

## 5. Cost

- 上限：50 次 provider 调用/天、20 元/月，超限 429 + 手工降级路径；真实 provider 下
  账本不可读写即 503 fail closed；单请求 provider 调用硬上限 ≤5（2 LLM 阶段 × (1+1 重试) + 1 搜索）
- 实测：Pilot 12 replay 0.6442 元/12 条；S7 压力批 0.2912 元/5 条；单条 0.012–0.104 元；
  本月累计 <2 元 / 20 元

## 6. Tests（全部命令与最近结果）

```
node eval/runtime-isolation-selftest.mjs   ✓ 生产路径对评测数据引用=0（违规即 PRODUCTION_RUNTIME_REFERENCES_EVAL_DATA）
node eval/authority-selftest.mjs           ✓ 域名授权正负控+旧白名单残留
node eval/adapter-shape-selftest.mjs       ✓ 搜索适配层响应/请求形状（Bearer-only、无 answer）
node eval/admission-selftest.mjs           ✓ 风险×授权矩阵 + S2-d 复放 + 时效旗标 + action/fact 边界（17 项）
node eval/retry-selftest.mjs               ✓ 坏 JSON 一次重试 + 并发计数竞态（8 项）
node eval/liveness-selftest.mjs            ✓ 链接存活：404/410 剔除、超时保守保留
node eval/runtime-selftest.mjs             ✓ 并发隔离/来源白名单/限流/日志隐私/请求体/静态页（10 项）
node eval/frontend-e2e.mjs                 ✓ 页面可达/无占位假话/失败码文案/全链路往返（10 项）
node eval/run.mjs --pilot eval/pilot12.json --max 12 --dry-run   ✓ 恰好 12 条（硬门）
```

真实验证：Pilot 12 Replay + S7 压力批（2026-09-13 凌晨，0 P0）——逐条复核见
`docs/v2/PILOT12_REPLAY_REVIEW.md`；浏览器实测（用户桌面 Edge 截图 + 内置浏览器 320px
全流程）通过；320/390/414/桌面无横向溢出（320 实测，其余为同布局推定+桌面实测）。

## 7. Manual Acceptance（部署后由 Founder/主运维执行的 8 条生产 smoke）

1. 打开站点：看到标题、副文案、第三方披露；无 JS 环境有如实提示
2. 提交「我们小区晚上有人制造噪音，想真正解决」：等 loading（有秒数），结果页五段齐全，
   资源带官方徽章与核实日期，点开来源可达
3. 提交「楼下路灯坏了半个月想让人修」：答案以物业/市政/报修编号为主线，AI 不是主角
4. 故意超短输入 → 得到可理解的提示；20KB+ 输入 → 不白屏
5. 陌生网站跨域调用接口 → 403；同源正常
6. `WS_DAILY_CAP` 临时调小自测 → 429 + 手工降级文案（测完改回 50）
7. 断网/停 LLM 网关提交 → 诚实错误 + 现实下一步，无假答案
8. `GET /healthz`：search_configured=true、fail_closed=true、today_calls 在涨、月成本在涨

## 8. Deployment Inputs（只列变量名；值由运维本机填写）

```
WS_PROVIDER WS_LLM_BASE_URL WS_LLM_KEY WS_LLM_MODEL WS_LLM_JSON_MODE WS_LLM_EXTRA_HEADERS
WS_MAX_TOKENS WS_TIMEOUT_MS
WS_SEARCH WS_SEARCH_KEY WS_SEARCH_URL
WS_DAILY_CAP WS_MONTHLY_CAP_RMB WS_RMB_PER_SEARCH WS_RMB_PER_1K_IN WS_RMB_PER_1K_OUT
WS_HOST WS_PORT WS_STATE_FILE WS_BUDGET_FAIL_CLOSED
WS_ALLOWED_ORIGINS WS_RATE_LIMIT WS_LIVENESS
```

启动：`set -a && . var/.env.local && set +a && node server/world.mjs`（同源托管页面与接口）。
若前端改走独立域名（如 GitHub Pages），必须设 `WS_ALLOWED_ORIGINS=https://<域名>`。

## 9. Gates 状态

| Gate | 结论 |
|---|---|
| 1 World Reality | **PASS** —— 17 条真实搜索压测 0 P0、0 未授权高风险、0 假官方入口、0 地域泛化、0 失效当现行 |
| 2 Product Experience | **PASS** —— 浏览器实测连续旅程成立；路灯/政策/模糊三题证明"不是搜索引擎/工具站" |
| 3 Deployment Readiness | **PASS** —— 上述测试全绿、隔离/CORS/预算/隐私/前端 e2e/构建（无构建系统，静态即产物）/env 契约/healthz/回滚/工作树 clean |

反方攻击后修复：真实模式并发丢计数竞态（延迟网关 4 并发回归盯住）。

## 10. Rollback

- 进程级：停 node 进程即回到纯静态站（ymai.fun 不受影响，无共享状态）
- 代码级：`git checkout <上一个可用 SHA> -- server/ web/` 后重启；近三个可用点：
  本次最终 SHA → `e7fb06c` → `5bda2bc`
- 触发条件：生产 smoke 第 2/7 条失败、月成本异常增速、或出现任何"错误把人带入现实"的报告
- 预算账本损坏自动 fail closed（503），不静默放行

## 11. Known Non-Blockers（发布后观察，不伪装成完成）

1. p50 ≈38s 延迟（模型+搜索+探活；前端已诚实提示；后续可做阶段化耗时展示）
2. 链接失活率若在真实使用中成模式 → 考虑 `created_at/last_verified` 与过期重搜（PRE_DEPLOY_BLOCKERS §C）
3. 理解正文引用常识数值未走绑定（如海拔 3300 米）
4. 反馈回路单轮；多轮追问深度未压测
5. 评测候选池中 17 条 uncertain 未逐条裁决（不阻断部署）
6. usage 计数与限流为单进程内存/文件方案；多实例部署前需重做（当前无此计划）
```
