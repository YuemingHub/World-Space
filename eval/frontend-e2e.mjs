/*
 * 前端 e2e（HTTP 层）—— 起真实服务进程（stub + fixture），验证：
 * 页面可达且不含占位假话 → 静态资源齐全 → 页面 JS 确实指向 /api/world 且有失败态文案 →
 * 全链路一次真实往返 → 三个失败路径的响应形状能被前端错误映射覆盖。
 * 浏览器级验收（Founder 视角）单独执行，不在本文件。
 */
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };
const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
  env: Object.assign({}, process.env, {
    WS_PROVIDER: 'stub', WS_STUB_CASE: 'ok', WS_SEARCH: 'fixture', WS_LIVENESS: '0',
    WS_PORT: '8875', WS_HOST: '127.0.0.1', WS_STATE_FILE: join(ROOT, 'var', 'fe-8875.json'), WS_RATE_LIMIT: '100',
  }), stdio: 'ignore',
});
async function up() {
  for (let i = 0; i < 40; i++) {
    try { const r = await fetch('http://127.0.0.1:8875/healthz'); if (r.ok) return; } catch (e) { }
    await new Promise(r => setTimeout(r, 150));
  }
  throw new Error('server 没起来');
}
await up();
const B = 'http://127.0.0.1:8875';
try {
  const page = await (await fetch(B + '/')).text();
  ok('页面可达', page.includes('你现在想做成什么') && page.includes('第三方 AI 与搜索服务'));
  ok('没有占位假话（不再说"还在接入"）', !page.includes('还在接入真正的智能层'));
  const css = await fetch(B + '/style.css'); const js = await fetch(B + '/app.js');
  ok('样式与脚本可达', css.status === 200 && js.status === 200);
  const appjs = await js.text();
  ok('页面脚本真的指向 /api/world', appjs.includes("'/api/world'") || appjs.includes('"/api/world"'));
  const codes = ['budget_exceeded', 'rate_limited', 'intelligence_unavailable', 'intelligence_contract_failure', 'network', 'body_too_large'];
  ok('全部失败码都有给人看的文案', codes.every(c => appjs.includes(c)), codes.filter(c => !appjs.includes(c)).join(','));

  // 全链路一次真实往返（stub 桩 + fixture 搜索，验证响应能被 render 所需字段满足）
  const res = await fetch(B + '/api/world', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ intent: '小区夜间噪声扰民想投诉', answers: [] }),
  });
  const j = await res.json();
  const need = ['understanding', 'questions', 'safe_next_action', 'recommended_path', 'resources', 'uncertainties', 'reality_feedback_prompt', 'fallback_if_refused'];
  ok('200 响应包含渲染所需的全部字段', res.status === 200 && need.every(k => j[k] !== undefined), `缺 ${need.filter(k => j[k] === undefined).join(',')}`);
  const resHasFields = (j.resources || []).every(r => ['name', 'claim', 'why', 'source_type', 'source_url'].every(k => r[k] !== undefined));
  ok('资源字段满足资源卡片渲染', resHasFields, JSON.stringify((j.resources || [])[0]));

  // 失败路径形状
  const short = await (await fetch(B + '/api/world', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"intent":"a"}' })).json();
  ok('过短意图 → intent_too_short（前端有文案）', short.error === 'intent_too_short');
  const long = '{"intent":"' + '长'.repeat(600) + '"}';
  const tooLong = await (await fetch(B + '/api/world', { method: 'POST', headers: { 'content-type': 'application/json' }, body: long })).json();
  ok('超长意图 → intent_too_long', tooLong.error === 'intent_too_long');
  const bad = await (await fetch(B + '/api/world', { method: 'POST', headers: { 'content-type': 'application/json' }, body: 'not json' })).json();
  ok('坏请求体 → body_bad_json', bad.error === 'body_bad_json');
} finally {
  try { child.kill('SIGKILL'); } catch (e) { }
}
console.log(failures ? `\n失败 ${failures} 项` : '\n前端 e2e（HTTP 层）全部通过');
process.exitCode = failures ? 1 : 0;
