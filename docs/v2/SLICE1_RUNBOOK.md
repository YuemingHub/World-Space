# SLICE 1 RUNBOOK — 怎么跑这一轮（以及还缺什么）

> 2026-09-12。**本轮不部署、不 merge main**；接口只监听 `127.0.0.1`，只在本机跑。

## 1. 现在就能跑（离线桩，0 元、0 外网请求）

```bash
cd D:/服务器/repos/World-Space

# 契约 + 证据纪律 + 预算护栏的自检（"ok" 是合格答案，"bad" 是故意做坏的假答案）
WS_PROVIDER=stub WS_STUB_CASE=bad WS_PORT=8794 WS_DAILY_CAP=2 node server/world.mjs
node eval/run.mjs --base http://127.0.0.1:8794 --limit 2 --only S5
curl http://127.0.0.1:8794/healthz
```

桩只证明四件事真的生效：问题被截到 2 条、缺官方来源的高风险结论被删除并留痕、
伪造的官方域名被压测器抓成 P0、每日上限一到就 429 并给出人工降级路径。
**桩的输出不得当作智能结果汇报。**

每次动过 `server/**` 之后，五个静态/单元 Gate 必须全绿（详见 `SEARCH_PILOT_PREFLIGHT.md` §7）：

```bash
node eval/runtime-isolation-selftest.mjs   # 生产路径对评测数据的引用必须为 0，违规输出 PRODUCTION_RUNTIME_REFERENCES_EVAL_DATA
node eval/authority-selftest.mjs           # 授权判定的正负控 + 旧白名单残留检查
node eval/adapter-shape-selftest.mjs       # 搜索适配层响应形状 + Bearer-only 请求形状
node eval/admission-selftest.mjs           # F1/F2 admission：风险×授权矩阵、S2-d 复放、action/fact 边界
node eval/retry-selftest.mjs               # F4：坏 JSON 一次重试（本地 mock 网关，0 外网请求）
```

## 2. 接真实智能层还缺两把钥匙（Founder 提供）

| 需要的 | 备选 | 现状 |
|---|---|---|
| 1 个 LLM provider | 阿里云百炼（OpenAI 兼容，北京地域每模型约 100 万 Token 免费、90 天）/ DeepSeek 官方 API | 需她在控制台开通并建 Key |
| 1 个 Search provider | 阿里云联网搜索（极速版 12 元/千次）/ 博查（约 0.036 元/次，官方价目未核到） | 阿里云侧**需主账号在控制台开通**，`fs-ops` 这把降权 AK 办不到 |

**密钥不要贴在聊天里。** 让她在本机执行（一次即可，我不读内容）：

```bash
cd D:/服务器/repos/World-Space && cat > var/.env.local <<'EOF'
WS_PROVIDER=openai_compatible
WS_LLM_BASE_URL=<百炼 compatible-mode 地址>
WS_LLM_KEY=<粘贴你的 Key>
WS_LLM_MODEL=qwen-plus
WS_SEARCH=aliyun
WS_SEARCH_KEY=<搜索 Key>
WS_RMB_PER_SEARCH=0.012
EOF
```

随后由她在**本机**启动（key 不进聊天记录）：

```bash
cd D:/服务器/repos/World-Space && set -a && . var/.env.local && set +a && node server/world.mjs
```

## 3.5 接真实搜索（PHASE 1，等 Founder 给 Key）

Key 纪律：**只存在 `var/.env.local`（已 gitignored）**；不打印、不进报告、不进 eval 输出、不进异常堆栈、不进 Git。
只允许验证"配没配"：`/healthz` 的 `search_configured` 字段（不回显 key）。

她要在本机执行（一次即可）：

```bash
cd D:/服务器/repos/World-Space && printf 'WS_SEARCH=tavily\nWS_SEARCH_KEY=<粘贴 Tavily key>\n' >> var/.env.local
```

Tavily 只作 Search Provider：`query → results`。**不用它的 answer 生成能力**（请求里已写死 `include_answer:false`）。
它返回的网页**不等于**官方来源：判级仍由 `server/evidence.mjs` 按真实 URL 决定（找东西与判定证据是两种权力，不合并）。

顺序**不可跳过**：

1. 先跑一条**必须触发搜索**的 smoke（建议 S5-a 或 S3），确认链条完整：
   triage → `needs_search=true` → 最小化后的 query → Tavily 真实请求 → ≥1 条结果 → 服务端签发 e1…
   → compose → 模型引用 evidence_id → 服务端解析回 URL → 授权判级 → guard → validate → 200。
   **compose 没触发就停**，先查原因，不要直接跑 12 条。
2. 人工打开最终引用的 URL，逐条核对：URL 真存在、标题大体一致、snippet 没截反语义、
   claim 真由该 source 支撑、authority 判级正确、模型引用的是本轮 evidence 而不是自造 URL。
   每条按**两个独立字段**记录（authority 本轮只回答"这是谁的网站"，不回答"有没有资格支撑这个 claim"）：
   - `domain_authority_correct`：系统有没有认对"这是谁的网站"（government / trusted media / unverified）；
   - `claim_source_role_correct`：这个具体网页是否真有资格支撑这个具体 claim
     （例：政府网站转载新华社文章 → domain=government，不自动等于这是一手政府结论）。
   两字段分开记，先靠 pilot 暴露问题，不提前开发 Claim Verification Engine。
3. 全部成立后，才用**完全相同的 12 条**跑 Pilot 12（`eval/pilot12.json`），
   产物写 `docs/v2/SEARCH_EVIDENCE_PILOT12.md` + raw evidence。

## 3.6 预算（不变）

`WS_DAILY_CAP=50`、月上限 20 元，**不调高**。注意 50 是 **provider 调用次数**，不是 `/api/world` 请求数：
有搜索的 case 最坏是 `2 LLM + 1 Search = 3` 次。12 条全触发搜索 = 36 次，仍在 50 以内。


- 每日 50 次 provider 调用、每月 20 元，超了就 429 并返回人工降级提示，**不静默跳过**。
- 全量 37 条一轮 ≈ 37–74 次 LLM + ≤37 次搜索 ⇒ **会顶到每日 50 的上限**，需要分两天跑或由她决定是否提上限。
- 粗估一轮真实成本：搜索 ≈ 0.44 元（12 元/千次口径）+ 模型按网关实际计费。

## 4. 跑完之后的判定顺序

1. 先看 P0（`eval/run.mjs` 会把可疑项连原始 JSON 一起写进报告）；
2. P0 清零后才看 P1（问卷化、只给 AI 工具、第一步不可执行、没有反馈问题）；
3. 通过标准不是"回答很多"，而是**尽量少打扰地给出一个真实、安全、可执行、可追溯的下一步**；
4. **智能层不过关就不接 UI**（MISSION 5 暂缓，`web/index.html` 不动）。
