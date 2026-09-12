# PRE-DEPLOY BLOCKERS（只登记，不施工）

> 2026-09-12 Search Pilot Preflight 登记。这些不是本轮的问题：本地串行 Pilot 不受影响。
> 触发条件到达之前，**不得公网部署**；也不要因为它们把 Search Pilot 变成基础设施项目。

## A. `usage` 是 process 级可变状态

`server/world.mjs` 的 `usage`（`llm_calls` / `search_calls` / `request_cost_rmb`）是模块级全局，
每个请求开头重置。本地串行压测下计数正确；**并发请求会互相覆盖计数**。

- 触发条件：任何多请求并发的生产运行之前，必须改成 request-local。
- 预算状态 `s` 本身走文件读写，不受此项影响——受影响的是单请求 meta 与日志里的调用计数。

## B. CORS 为 `*`

`server/world.mjs` 对所有响应返回 `access-control-allow-origin: *`。本机 Pilot 可接受。

公网生产之前必须重做三件事：

1. origin 限制（谁知道这个接口的存在）；
2. 滥用 / 速率防护（当前只有预算上限，没有请求方身份）；
3. API 暴露方式重新设计（是否直连、是否加一层）。

触发条件：第一次真实部署之前。
