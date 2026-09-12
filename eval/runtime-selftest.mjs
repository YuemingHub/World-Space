/*
 * 运行时边界自测 —— 全部本地（stub + fixture 搜索），0 外网、0 真实 provider。
 * 覆盖：并发 request-local 计量（PRE_DEPLOY A）、来源白名单 + 限流（PRE_DEPLOY B）、
 * 日志不含用户正文（隐私）、请求体上限。
 */
import { spawn } from 'node:child_process';
import { writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };
function start(port, extraEnv, captureLogs) {
  const chunks = [];
  const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      WS_PROVIDER: 'stub', WS_STUB_CASE: 'ok', WS_SEARCH: 'fixture', WS_LIVENESS: '0',
      WS_PORT: String(port), WS_HOST: '127.0.0.1', WS_STATE_FILE: join(ROOT, 'var', `rt-${port}.json`),
      WS_DAILY_CAP: '500',
    }, extraEnv),
    stdio: captureLogs ? ['ignore', 'pipe', 'pipe'] : 'ignore',
  });
  if (captureLogs) child.stdout.on('data', d => chunks.push(d));
  return { child, logs: () => chunks.join('') };
}
async function up(port) {
  for (let i = 0; i < 40; i++) {
    try { const r = await fetch(`http://127.0.0.1:${port}/healthz`); if (r.ok) return; } catch (e) { }
    await new Promise(r => setTimeout(r, 150));
  }
  throw new Error('server 没起来');
}
const kill = c => { try { c.kill('SIGKILL'); } catch (e) { } };

/* ── 实例 1：CORS / 限流 / 隐私 / 请求体 ── */
{
  rmSync(join(ROOT, 'var', 'rt-8871.json'), { force: true });
  const inst = start(8871, { WS_ALLOWED_ORIGINS: 'http://ok.example', WS_RATE_LIMIT: '6' }, true);
  await up(8871);
  const B = 'http://127.0.0.1:8871';
  const opt = await fetch(B + '/api/world', { method: 'OPTIONS', headers: { origin: 'http://ok.example' } });
  ok('OPTIONS 允许来源 → 204 且回显 origin', opt.status === 204 && opt.headers.get('access-control-allow-origin') === 'http://ok.example', `HTTP ${opt.status}`);
  const optEvil = await fetch(B + '/api/world', { method: 'OPTIONS', headers: { origin: 'http://evil.example' } });
  ok('OPTIONS 陌生来源 → 403', optEvil.status === 403, `HTTP ${optEvil.status}`);
  const postEvil = await fetch(B + '/api/world', { method: 'POST', headers: { 'content-type': 'application/json', origin: 'http://evil.example' }, body: '{"intent":"测试"}' });
  ok('POST 陌生来源 → 403 且无 CORS 头', postEvil.status === 403 && !postEvil.headers.get('access-control-allow-origin'), `HTTP ${postEvil.status}`);

  const MARK = '隐私标记-黎明的小区噪声';
  const p1 = await fetch(B + '/api/world', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ intent: MARK }) });
  ok('无 Origin（非浏览器）→ 放行', p1.status === 200, `HTTP ${p1.status}`);
  const big = '{"intent":"' + '长'.repeat(21000) + '"}';
  const pBig = await fetch(B + '/api/world', { method: 'POST', headers: { 'content-type': 'application/json' }, body: big }).catch(e => ({ status: 0 }));
  ok('超大请求体 → 400/连接中断，不 200', pBig.status === 400 || pBig.status === 0, `HTTP ${pBig.status}`);

  let got429 = false;
  for (let i = 0; i < 5; i++) {
    const r = await fetch(B + '/api/world', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"intent":"限流测试第' + i + '条"}' });
    if (r.status === 429) { got429 = true; const j = await r.json(); ok('超限 → 429 rate_limited 且给诚实降级', j.error === 'rate_limited' && !!j.fallback_if_refused); break; }
  }
  if (!got429) ok('超限 → 429 rate_limited 且给诚实降级', false, '6+/min 后未触发');
  await new Promise(r => setTimeout(r, 300));
  ok('日志不含用户正文（隐私标记未出现）', !inst.logs().includes(MARK));
  kill(inst.child);
}

/* ── 实例 2：并发 request-local 计量（stub ok + fixture = 每请求固定 2 LLM + 1 搜索）── */
{
  rmSync(join(ROOT, 'var', 'rt-8872.json'), { force: true });
  const inst = start(8872, { WS_RATE_LIMIT: '1000' });
  await up(8872);
  const B = 'http://127.0.0.1:8872/api/world';
  const rs = await Promise.all(Array.from({ length: 16 }, (_, i) =>
    fetch(B, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ intent: '并发请求 ' + i + ' 号，测试计数隔离' }) })));
  const js = await Promise.all(rs.map(r => r.json()));
  const badCounts = js.filter(j => j.meta && (j.meta.llm_calls !== 2 || j.meta.search_calls !== 1));
  ok('16 路并发：每个请求的调用计数都是自己的（2 LLM + 1 搜索）', rs.every(r => r.status === 200) && badCounts.length === 0, badCounts.length ? JSON.stringify(badCounts[0].meta) : '');
  const st = JSON.parse(readFileSync(join(ROOT, 'var', 'rt-8872.json'), 'utf8'));
  ok('预算总账 = 48 次（16×3），无漏记重记', st.calls === 48, JSON.stringify(st));
  const page = await fetch('http://127.0.0.1:8872/');
  const html = await page.text();
  ok('静态页可访问且是真实入口（标题+第三方披露）', page.status === 200 && html.includes('你现在想做成什么') && html.includes('第三方 AI 与搜索服务'));
  kill(inst.child);
}

console.log(failures ? `\n失败 ${failures} 项` : '\n运行时边界全部通过');
process.exitCode = failures ? 1 : 0;
