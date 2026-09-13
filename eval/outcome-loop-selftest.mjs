/*
 * Outcome Loop 回归自测 —— 离线桩（stub）经真实 HTTP 管线，不是搜索结果，不进 pilot 报告。
 * 证明四件事：
 *   1. 回执真的进了模型上下文：同一意图，带 receipt 的第二轮，桩切换到"推进后"应答。
 *      桩按输入里 "receipt":{ 的存在性切换应答——服务端若漏传 receipt，两轮输出一模一样，这里立刻抓住。
 *      meta 如实标记 receipt_ingested / receipt_status。
 *   2. 回执的形状边界：非对象 / 无内容无状态 / 超长文本——分别被忽略、规范化、截断；对抗载荷过管线后渲染仍是纯文本。
 *   3. 交棒契约：mode=handoff 必须带任务书，空手交棒降级 internal；
 *      前端渲染出复制任务书 + 跳转链接，链接只来自前端白名单（DeepSeek），模型给的目标名匹配不上就不给链接。
 *   4. 唯一主行动推导链：模型缺省 next_action 时从护栏结论推导——路径被撤→回退立即动作，不出现"路径撤了主行动还在"。
 */
import { spawn } from 'node:child_process';
import { rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildResultHtml } from '../web/v2/render.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };

function startWorld(port, stubCase, extra) {
  return spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      // compose 阶段只在拿到证据时发生：统一用 fixture 搜索让桩的 compose / compose_with_receipt 被触发
      WS_PROVIDER: 'stub', WS_STUB_CASE: stubCase, WS_SEARCH: 'fixture', WS_LIVENESS: '0',
      WS_PORT: String(port), WS_HOST: '127.0.0.1', WS_STATE_FILE: join(ROOT, 'var', `loop-${port}.json`), WS_RATE_LIMIT: '100',
    }, extra || {}), stdio: 'ignore',
  });
}
async function up(port) {
  for (let i = 0; i < 40; i++) {
    try { if ((await fetch(`http://127.0.0.1:${port}/healthz`)).ok) return; } catch (e) { }
    await new Promise(r => setTimeout(r, 150));
  }
  throw new Error(`world:${port} 没起来`);
}
const ask = (port, body) => fetch(`http://127.0.0.1:${port}/api/world`, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
});
const kill = c => { try { c.kill('SIGKILL'); } catch (e) { } };
function audit(html) {
  const TAGS = ['div', 'strong', 'span', 'h2', 'p', 'button', 'a', 'ul', 'li'];
  const ATTRS = ['class', 'href', 'target', 'rel', 'id', 'data-copy-slot', 'hidden', 'rows'];
  const tags = [...html.matchAll(/<([a-zA-Z][a-zA-Z0-9]*)/g)].map(m => m[1]).filter(t => !TAGS.includes(t));
  const attrs = [...html.matchAll(/\s([a-zA-Z-]+)="[^"]*"/g)].map(m => m[1]).filter(t => !ATTRS.includes(t));
  const hrefs = [...html.matchAll(/href="([^"]*)"/g)].map(m => m[1]);
  return { tags, attrs, hrefs };
}

/* ── 1. 回执差分：receipt 进模型上下文并改变输出 ── */
{
  rmSync(join(ROOT, 'var', 'loop-8895.json'), { force: true });
  const child = startWorld(8895, 'receipt');
  try {
    await up(8895);
    const INTENT = '我们小区里的路灯坏了两个星期了';
    const r1 = await ask(8895, { intent: INTENT });
    const j1 = await r1.json();
    ok('第一轮 200 且主行动是"物业报修"', r1.status === 200 && j1.next_action && j1.next_action.text.indexOf('物业') !== -1, JSON.stringify(j1.next_action));
    ok('第一轮主行动模式 = human（现实世界动作）', j1.next_action.mode === 'human', j1.next_action.mode);
    ok('第一轮 meta 如实：receipt_ingested = false', j1.meta.receipt_ingested === false && j1.meta.receipt_status === '', JSON.stringify(j1.meta));
    ok('第一轮 done_when 可验证（工单号/修复时间）', j1.next_action.done_when.indexOf('工单号') !== -1 || j1.next_action.done_when.indexOf('修复时间') !== -1, j1.next_action.done_when);

    const r2 = await ask(8895, { intent: INTENT, receipt: { status: 'stuck', text: '物业说这两盏灯不归他们管，让我们找别家' } });
    const j2 = await r2.json();
    ok('第二轮 200 且 meta 如实：receipt_ingested = true / stuck', r2.status === 200 && j2.meta.receipt_ingested === true && j2.meta.receipt_status === 'stuck', JSON.stringify(j2.meta));
    ok('回执改变了输出：理解承认"不归"（不是重答）', j2.understanding.indexOf('不归') !== -1 && j2.understanding !== j1.understanding, j2.understanding);
    ok('回执改变了下一步：推进到居委会（不维护原推荐）', j2.next_action.text.indexOf('居委会') !== -1 && j2.next_action.text !== j1.next_action.text, j2.next_action.text);

    // 回执形状边界
    const rBad1 = await ask(8895, { intent: INTENT, receipt: '物业说不归他们管' });
    const jBad1 = await rBad1.json();
    ok('字符串形态的 receipt 被忽略（不进上下文）', jBad1.meta.receipt_ingested === false && jBad1.understanding === j1.understanding, JSON.stringify(jBad1.meta));
    const rBad2 = await ask(8895, { intent: INTENT, receipt: { status: 'weird', text: '   ' } });
    const jBad2 = await rBad2.json();
    ok('无内容无合法状态的 receipt 规范化为不进', jBad2.meta.receipt_ingested === false, JSON.stringify(jBad2.meta));
    const longText = '长'.repeat(3000) + '"><img src=x onerror=window.__xss_loop=1>';
    const rBad3 = await ask(8895, { intent: INTENT, receipt: { status: 'done', text: longText } });
    const jBad3 = await rBad3.json();
    ok('超长回执截断且对抗载荷过管线后渲染为纯文本', rBad3.status === 200 && jBad3.meta.receipt_ingested === true,
      JSON.stringify({ s: rBad3.status, m: jBad3.meta }));
    const { html: hBad3 } = buildResultHtml(jBad3);
    const a3 = audit(hBad3);
    ok('对抗回执后的渲染无注入', a3.tags.length === 0 && a3.attrs.length === 0, [...a3.tags, ...a3.attrs].join(','));
  } finally { kill(child); }
}

/* ── 2. 交棒契约与渲染 ── */
{
  rmSync(join(ROOT, 'var', 'loop-8897.json'), { force: true });
  const child = startWorld(8897, 'handoff');
  try {
    await up(8897);
    const r = await ask(8897, { intent: '我不是程序员，但想找一份能大量使用 AI 的工作' });
    const j = await r.json();
    ok('交棒主行动：mode=handoff 且任务书完整', j.next_action.mode === 'handoff' && j.next_action.handoff_task.indexOf('我不是程序员') !== -1, JSON.stringify(j.next_action).slice(0, 200));
    ok('done_when 可验证（至少 3 个方向）', j.next_action.done_when.indexOf('3 个') !== -1, j.next_action.done_when);
    const { html, copies } = buildResultHtml(j);
    const a = audit(html);
    ok('交棒渲染结构干净', a.tags.length === 0 && a.attrs.length === 0, [...a.tags, ...a.attrs].join(','));
    ok('跳转链接来自前端白名单（DeepSeek 官方入口，非模型 URL）', a.hrefs.filter(h => h === 'https://chat.deepseek.com/').length === 1 && a.hrefs.length === 1, a.hrefs.join(' | '));
    ok('任务书原文进复制槽位（不经 HTML 属性）', copies.includes(j.next_action.handoff_task) && copies.includes(j.next_action.text), `copies=${copies.length}`);

    const jUnknown = JSON.parse(JSON.stringify(j));
    jUnknown.next_action.handoff_target = '某个没听过的工具';
    const hUnknown = buildResultHtml(jUnknown).html;
    ok('白名单外的目标不给跳转链接，明说去哪复制', (hUnknown.match(/<a /g) || []).length === 0 && hUnknown.indexOf('没有预置') !== -1, '');
    const jEvil = JSON.parse(JSON.stringify(j));
    jEvil.next_action.handoff_target = 'javascript:alert(1)';
    const hEvil = buildResultHtml(jEvil).html;
    ok('危险目标名同样不给链接', (hEvil.match(/<a /g) || []).length === 0, hEvil.match(/href="[^"]*"/g) === null ? '' : hEvil.match(/href="[^"]*"/g).join(' | '));
  } finally { kill(child); }
}

/* ── 3. 空手交棒降级 ── */
{
  rmSync(join(ROOT, 'var', 'loop-8899.json'), { force: true });
  const child = startWorld(8899, 'handoff_notask');
  try {
    await up(8899);
    const j = await (await ask(8899, { intent: '测试空手交棒' })).json();
    ok('宣称 handoff 却没有任务书 → 降级 internal，任务书为空', j.next_action.mode === 'internal' && j.next_action.handoff_task === '', JSON.stringify(j.next_action));
    const { html } = buildResultHtml(j);
    ok('降级后不渲染交棒块', html.indexOf('handoff') === -1 && html.indexOf('任务书') === -1, '');
  } finally { kill(child); }
}

/* ── 4. 唯一主行动推导链（模型缺省 next_action）── */
{
  // D1：ok 桩 + fixture 证据 → compose 走完，护栏后路径仍在 → 主行动 = 路径第一步
  rmSync(join(ROOT, 'var', 'loop-8903.json'), { force: true });
  const child = startWorld(8903, 'ok');
  try {
    await up(8903);
    const j = await (await ask(8903, { intent: '楼上夜里装修太吵，我想真正解决' })).json();
    ok('D1 前提：护栏后路径仍在（证据已授权）', j.recommended_path !== null, JSON.stringify(j.meta.guard_actions));
    ok('D1 主行动 = 路径第一步（模型缺省时推导，不给人两个行动）', j.next_action && j.next_action.text === j.recommended_path.first_action && j.next_action.mode === '', JSON.stringify(j.next_action));
  } finally { kill(child); }
  // D2：ok 桩 + 无搜索 → compose 不发生，triage 草稿无路径无动作 → 护栏兜底动作成为主行动
  rmSync(join(ROOT, 'var', 'loop-8905.json'), { force: true });
  const child2 = startWorld(8905, 'ok', { WS_SEARCH: 'none' });
  try {
    await up(8905);
    const j = await (await ask(8905, { intent: '楼上夜里装修太吵，我想真正解决' })).json();
    ok('D2 前提：无证据轮次路径缺席', j.recommended_path === null, JSON.stringify(j.meta.search_skipped_reason || ''));
    ok('D2 护栏兜底动作传导为主行动（不晾着人）', j.next_action && j.next_action.text === j.safe_next_action && j.next_action.mode === '', JSON.stringify(j.next_action));
  } finally { kill(child2); }
}

console.log(failures ? `\n失败 ${failures} 项` : '\nOutcome Loop 回归全部通过（离线桩，非真实 provider）');
process.exitCode = failures ? 1 : 0;
