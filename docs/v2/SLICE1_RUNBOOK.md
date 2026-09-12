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

## 3. 预算与轮次（她定的硬上限已在代码里强制）

- 每日 50 次智能/搜索请求、每月 20 元，超了就 429 并返回人工降级提示，**不静默跳过**。
- 全量 37 条一轮 ≈ 37–74 次 LLM + ≤37 次搜索 ⇒ **会顶到每日 50 的上限**，需要分两天跑或临时提上限（她定）。
- 粗估一轮真实成本：搜索 ≈ 0.44 元（12 元/千次口径）+ 模型走免费额度 ≈ 0 元。

## 4. 跑完之后的判定顺序

1. 先看 P0（`eval/run.mjs` 会把可疑项连原始 JSON 一起写进报告）；
2. P0 清零后才看 P1（问卷化、只给 AI 工具、第一步不可执行、没有反馈问题）；
3. 通过标准不是"回答很多"，而是**尽量少打扰地给出一个真实、安全、可执行、可追溯的下一步**；
4. **智能层不过关就不接 UI**（MISSION 5 暂缓，`web/index.html` 不动）。
