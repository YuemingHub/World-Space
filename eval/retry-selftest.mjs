/*
 * F4 回归自测 —— 本地 mock 网关（127.0.0.1），0 外网请求，不是真实 provider。
 * 验证：invalid JSON → 恰好一次 schema-only 重试 → 成功；两次都失败 → fail closed 502；
 * 每次尝试都计入预算；meta.llm_retry_count 如实；不触发任何搜索。
 */
import { spawn } from 'node:child_process';
import http from 'node:http';
import { writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const GOOD_TRIAGE = JSON.stringify({
  understanding: '测试意图理解',
  needs_clarification: false,
  questions: [],
  safe_next_action: '先把要做的事写下来。',
  recommended_path: null,
  resources: [],
  uncertainties: [],
  reality_feedback_prompt: '做完告诉我结果。',
  fallback_if_refused: '手工路径。',
});
const body = JSON.stringify({ choices: [{ message: { content: GOOD_TRIAGE } }], usage: { prompt_tokens: 100, completion_tokens: 50 } });

function mockGateway(responses) {
  let n = 0;
  return http.createServer((req, res) => {
    let buf = '';
    req.on('data', d => buf += d);
    req.on('end', () => {
      const r = responses[Math.min(n, responses.length - 1)];
      n += 1;
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(typeof r === 'string' ? JSON.stringify({ choices: [{ message: { content: r } }], usage: { prompt_tokens: 10, completion_tokens: 10 } }) : body);
    });
  });
}

function startWorld(port, env) {
  const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      WS_PROVIDER: 'openai_compatible', WS_LLM_BASE_URL: `http://127.0.0.1:${port + 100}`,
      WS_LLM_MODEL: 'mock', WS_SEARCH: 'none', WS_PORT: String(port), WS_HOST: '127.0.0.1',
      WS_STATE_FILE: env.stateFile, WS_DAILY_CAP: '50', WS_TIMEOUT_MS: '5000',
    }), stdio: 'ignore',
  });
  return child;
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

let failures = 0;
const ok = (name, cond, detail) => { console.log(`${cond ? '✓' : '✗'} ${name}${cond || !detail ? '' : ' —— ' + detail}`); if (!cond) failures++; };
const kill = c => { try { c.kill('SIGKILL'); } catch (e) { } };

// 场景 A：第一次坏 JSON，第二次合法 → 200，retry_count = 1，llm_calls = 2，无搜索
{
  rmSync('var/retry-a.json', { force: true });
  const gw = mockGateway(['这不是JSON {{{', null]); // 第 1 次坏、第 2 次合法
  const worldPort = 8890, gwPort = worldPort + 100; // world 的 WS_LLM_BASE_URL = worldPort+100
  await new Promise(r => gw.listen(gwPort, '127.0.0.1', r));
  const child = startWorld(worldPort, { stateFile: join(ROOT, 'var', 'retry-a.json') });
  await worldUp(worldPort);
  const res = await ask(worldPort, '测试重试场景A，搜索不需要');
  const j = await res.json();
  ok('A: 坏→重试→200', res.status === 200, `HTTP ${res.status} ${JSON.stringify(j).slice(0, 120)}`);
  ok('A: retry_count = 1', j.meta && j.meta.llm_retry_count === 1, JSON.stringify(j.meta));
  ok('A: llm_calls = 2（重试计入预算）', j.meta && j.meta.llm_calls === 2, JSON.stringify(j.meta));
  ok('A: 不触发搜索', j.meta && j.meta.search_calls === 0, JSON.stringify(j.meta));
  kill(child); gw.close();
}
// 场景 B：两次都坏 → fail closed 502，预算计 2 次
{
  rmSync('var/retry-b.json', { force: true });
  const gw = mockGateway(['bad1 {', 'bad2 {']);
  const worldPort = 8892, gwPort = worldPort + 100;
  await new Promise(r => gw.listen(gwPort, '127.0.0.1', r));
  const child = startWorld(worldPort, { stateFile: join(ROOT, 'var', 'retry-b.json') });
  await worldUp(worldPort);
  const res = await ask(worldPort, '测试重试场景B，搜索不需要');
  const j = await res.json();
  ok('B: 两次都坏 → 502 fail closed', res.status === 502 && j.error === 'intelligence_unavailable' && j.code === 'llm_bad_json', `HTTP ${res.status} ${JSON.stringify(j).slice(0, 120)}`);
  const st = JSON.parse(readFileSync(join(ROOT, 'var', 'retry-b.json'), 'utf8'));
  ok('B: 两次尝试都计入预算（calls = 2）', st.calls === 2, JSON.stringify(st));
  kill(child); gw.close();
}

// 场景 C：并发计数竞态——带延迟的网关让 4 条请求同时在途，每次计数必须磁盘重读，
// 最终总账必须恰好 4（旧实现各自持过期副本回写会丢成 1–2）
{
  rmSync('var/retry-c.json', { force: true });
  const gw = http.createServer((req, res) => {
    let buf = '';
    req.on('data', d => buf += d);
    req.on('end', () => setTimeout(() => {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ choices: [{ message: { content: GOOD_TRIAGE } }], usage: { prompt_tokens: 10, completion_tokens: 10 } }));
    }, 150));
  });
  const worldPort = 8894, gwPort = worldPort + 100;
  await new Promise(r => gw.listen(gwPort, '127.0.0.1', r));
  const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      WS_PROVIDER: 'openai_compatible', WS_LLM_BASE_URL: `http://127.0.0.1:${gwPort}`,
      WS_LLM_MODEL: 'mock', WS_SEARCH: 'none', WS_PORT: String(worldPort), WS_HOST: '127.0.0.1',
      WS_STATE_FILE: join(ROOT, 'var', 'retry-c.json'), WS_DAILY_CAP: '50', WS_TIMEOUT_MS: '5000',
    }), stdio: 'ignore',
  });
  await worldUp(worldPort);
  const rs = await Promise.all([1, 2, 3, 4].map(i => ask(worldPort, '并发计数竞态测试 ' + i)));
  const codes = rs.map(r => r.status);
  const st = JSON.parse(readFileSync(join(ROOT, 'var', 'retry-c.json'), 'utf8'));
  ok('C: 4 条并发（在途交叠）全部 200', codes.every(c => c === 200), JSON.stringify(codes));
  ok('C: 并发下预算总账 = 4，无丢计数', st.calls === 4, JSON.stringify(st));
  kill(child); gw.close();
}

console.log(failures ? `\n失败 ${failures} 项` : '\nF4 重试回归全部通过（本地 mock，非真实 provider）');
process.exitCode = failures ? 1 : 0;
