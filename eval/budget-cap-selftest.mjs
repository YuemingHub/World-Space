/*
 * R2 预算硬上限回归 —— 本地 mock 网关，0 外网请求。
 * 证明的是"预留式准入不会被并发穿透"，不是"调完把账记准"：
 *   D1 日上限临界：账本 49/50 时并发 6 条 → 恰好 1 条到达 provider，其余 429，
 *      账本终值 = 50（旧实现：先放行后记账，4 条并发能打出 53 次付费调用）；
 *   D2 月预算临界：剩余额度恰好一次 LLM 预留时并发 4 条 → 1 条 200，其余 429 monthly_budget；
 *   429 的请求绝不允许到达 provider（网关收到的请求计数当证据——准入在调用之前）。
 */
import { spawn } from 'node:child_process';
import http from 'node:http';
import { writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { localDate, localMonth } from '../server/date.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const GOOD_TRIAGE = JSON.stringify({
  understanding: '测试意图理解', needs_clarification: false, questions: [],
  safe_next_action: '先把要做的事写下来。', recommended_path: null, resources: [],
  uncertainties: [], reality_feedback_prompt: '做完告诉我结果。', fallback_if_refused: '手工路径。',
});

let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };
const kill = c => { try { c.kill('SIGKILL'); } catch (e) { } };

/** 带延迟与请求计数的 mock 网关：count() = 实际到达 provider 的 LLM 请求数 */
function mockGateway(delayMs) {
  let hits = 0;
  const server = http.createServer((req, res) => {
    let buf = '';
    req.on('data', d => buf += d);
    req.on('end', () => {
      hits += 1;
      setTimeout(() => {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ choices: [{ message: { content: GOOD_TRIAGE } }], usage: { prompt_tokens: 10, completion_tokens: 10 } }));
      }, delayMs);
    });
  });
  server.count = () => hits;
  return server;
}

function seedState(file, { calls, cost }) {
  writeFileSync(file, JSON.stringify({ day: localDate(), month: localMonth(), calls, cost }));
}
function startWorld(port, gwPort, stateFile, extraEnv = {}) {
  return spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      WS_PROVIDER: 'openai_compatible', WS_LLM_BASE_URL: `http://127.0.0.1:${gwPort}`,
      WS_LLM_MODEL: 'mock', WS_SEARCH: 'none', WS_PORT: String(port), WS_HOST: '127.0.0.1',
      WS_STATE_FILE: stateFile, WS_DAILY_CAP: '50', WS_MONTHLY_CAP_RMB: '20',
      WS_RMB_PER_1K_IN: '0.002', WS_RMB_PER_1K_OUT: '0.008', WS_MAX_TOKENS: '1500',
      WS_RATE_LIMIT: '1000', WS_TIMEOUT_MS: '5000',
    }, extraEnv), stdio: 'ignore',
  });
}
async function worldUp(port) {
  for (let i = 0; i < 40; i++) {
    try { const r = await fetch(`http://127.0.0.1:${port}/healthz`); if (r.ok) return; } catch (e) { }
    await new Promise(r => setTimeout(r, 150));
  }
  throw new Error('world 没起来');
}
const ask = (port, intent) => fetch(`http://127.0.0.1:${port}/api/world`, {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ intent }), signal: AbortSignal.timeout(20000),
});

// ── D1：日上限临界（49/50）+ 6 并发 ──
{
  const stateFile = join(ROOT, 'var', 'cap-daily.json');
  rmSync(stateFile, { force: true });
  seedState(stateFile, { calls: 49, cost: 0 });
  const gw = mockGateway(150);
  const worldPort = 8885, gwPort = 8985;
  await new Promise(r => gw.listen(gwPort, '127.0.0.1', r));
  const child = startWorld(worldPort, gwPort, stateFile);
  await worldUp(worldPort);
  const rs = await Promise.all([1, 2, 3, 4, 5, 6].map(i => ask(worldPort, '日上限临界并发测试 ' + i)));
  const codes = rs.map(r => r.status);
  const bodies = await Promise.all(rs.map(r => r.json()));
  const ok200 = bodies.filter(b => b.meta);
  const st = JSON.parse(readFileSync(stateFile, 'utf8'));
  ok('D1: 恰好 1 条 200，其余 5 条 429', codes.filter(c => c === 200).length === 1 && codes.filter(c => c === 429).length === 5, JSON.stringify(codes));
  ok('D1: 429 是 budget_exceeded/daily_calls 且带人工降级', bodies.filter(b => b.error).every(b => b.error === 'budget_exceeded' && b.limit === 'daily_calls' && !!b.fallback_if_refused), JSON.stringify(bodies.filter(b => b.error)[0]));
  ok('D1: 被拒请求没碰到 provider（网关只收到 1 个 LLM 请求）', gw.count() === 1, `gateway hits=${gw.count()}`);
  ok('D1: 账本 = 50（不多不少，无穿透）', st.calls === 50, JSON.stringify(st));
  ok('D1: 200 响应的计量如实（llm_calls=1）', ok200.length === 1 && ok200[0].meta.llm_calls === 1, JSON.stringify(ok200.map(b => b.meta)));
  kill(child); gw.close();
}
// ── D2：月预算临界（剩余额度恰好一次 LLM 预留 0.032 元）+ 4 并发 ──
{
  const stateFile = join(ROOT, 'var', 'cap-monthly.json');
  rmSync(stateFile, { force: true });
  // 预留额 = 0.008×1500/1000 + 0.002×10000/1000 = 0.032 元；账本 cost=5，上限 5.032 → 只够 1 次
  seedState(stateFile, { calls: 0, cost: 5 });
  const gw = mockGateway(150);
  const worldPort = 8887, gwPort = 8987;
  await new Promise(r => gw.listen(gwPort, '127.0.0.1', r));
  const child = startWorld(worldPort, gwPort, stateFile, { WS_MONTHLY_CAP_RMB: '5.032' });
  await worldUp(worldPort);
  const rs = await Promise.all([1, 2, 3, 4].map(i => ask(worldPort, '月预算临界并发测试 ' + i)));
  const codes = rs.map(r => r.status);
  const bodies = await Promise.all(rs.map(r => r.json()));
  const st = JSON.parse(readFileSync(stateFile, 'utf8'));
  ok('D2: 恰好 1 条 200，其余 3 条 429', codes.filter(c => c === 200).length === 1 && codes.filter(c => c === 429).length === 3, JSON.stringify(codes));
  ok('D2: 429 是 budget_exceeded/monthly_budget', bodies.filter(b => b.error).every(b => b.error === 'budget_exceeded' && b.limit === 'monthly_budget'), JSON.stringify(bodies.filter(b => b.error)[0]));
  ok('D2: 被拒请求没碰到 provider（网关只收到 1 个 LLM 请求）', gw.count() === 1, `gateway hits=${gw.count()}`);
  ok('D2: 结算后账本费用 ≤ 月上限（预留多算的部分已退）', st.cost <= 5.032 && st.cost >= 5, JSON.stringify(st));
  ok('D2: 账本调用数 = 1', st.calls === 1, JSON.stringify(st));
  kill(child); gw.close();
}

console.log(failures ? `\n失败 ${failures} 项` : '\n预算硬上限回归全部通过（本地 mock，非真实 provider）');
process.exitCode = failures ? 1 : 0;
