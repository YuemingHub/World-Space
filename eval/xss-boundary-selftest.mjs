/*
 * R1 前端 HTML 属性 / URL 安全边界回归。
 * 攻击面：模型 / 搜索返回的内容经 web/v2/render.mjs 拼成结果页 HTML。
 * 与受控浏览器旅程双保险，本文件自动验证：
 *   - 属性逃逸类载荷只显示文本：输出元素标签 / 属性名都在白名单里（注入 onerror、
 *     autofocus 之类会以"新属性名"出现，白名单立刻抓住——不靠子串猜）；
 *   - javascript: / data: / 协议相对 / 坏 URL 不成为可点击链接（href 只许 http(s)）；
 *   - 复制功能原文往返完整：载荷原文进 copies 数组（dataset 赋值），不经 HTML 属性；
 *   - 服务端证据表同规则：非 http(s) 的"结果"不签发证据 id，引用它的资源被删；
 *   - 全链路：stub xss 桩经真实 HTTP 管线返回对抗契约，前端渲染函数守住每一条。
 */
import { spawn } from 'node:child_process';
import { rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { esc, attr, httpUrl, buildResultHtml } from '../web/v2/render.mjs';
import { evidenceTable } from '../server/evidence.mjs';
import { guard } from '../server/guard.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };

/* ── 攻击载荷（要求清单全覆盖）── */
const A = {
  quote: '"',
  imgOnerror: '"><img src=x onerror=window.__xss=1>',
  autofocusOnfocus: '" autofocus onfocus=window.__xss=2 autofocus="',
  jsUrl: 'javascript:alert(1)',
  dataUrl: 'data:text/html,<b>x</b>',
  svgOnload: '"/><svg onload=window.__xss=3><"',
  normalChinese: '带 & < > \' " 引号的正常中文动作：先打 "110" 登记，再查 <医院> 名单 & 记录',
};

// ── 1. esc/attr 单元：文本与属性通用的转义（引号必须转）──
{
  let bad = [];
  for (const [k, v] of Object.entries(A)) {
    const e = esc(v);
    if (/["'<>]/.test(e)) bad.push(`${k}: ${e}`);
  }
  ok('esc 后无裸引号/尖括号（属性逃逸不可能）', bad.length === 0, bad.join(' | '));
  ok('attr 与 esc 同一转义', attr(A.imgOnerror) === esc(A.imgOnerror));
}
// ── 2. httpUrl 单元：可点击 URL 白名单 ──
{
  const deny = [A.jsUrl, 'JaVaScRiPt:alert(1)', A.dataUrl, '//protocol-relative.example/x', 'not a url', A.imgOnerror, 'file:///C:/Windows/system32', ''];
  ok('危险/畸形 URL 一律不给链接', deny.every(u => httpUrl(u) === ''), deny.filter(u => httpUrl(u) !== '').join(' | '));
  const h = httpUrl('https://例子.example/路径"onerror=x?a=1');
  ok('合法 https 保留且引号被百分号编码（不可逃出 href）', h.startsWith('https://') && !h.includes('"'), h);
  ok('http 保留', httpUrl('http://example.gov.cn/a').startsWith('http://'));
}
// ── 3. buildResultHtml 对抗渲染：标签/属性白名单 + href 白名单 + 复制原文往返 ──
const ALLOWED_TAGS = ['div', 'strong', 'span', 'h2', 'p', 'button', 'a', 'ul', 'li'];
const ALLOWED_ATTRS = ['class', 'href', 'target', 'rel', 'id', 'data-copy-slot', 'hidden', 'rows'];
function structuralAudit(html) {
  const tags = [...html.matchAll(/<([a-zA-Z][a-zA-Z0-9]*)/g)].map(m => m[1]);
  const badTags = [...new Set(tags.filter(t => !ALLOWED_TAGS.includes(t)))];
  const attrs = [...html.matchAll(/\s([a-zA-Z-]+)="[^"]*"/g)].map(m => m[1]);
  const badAttrs = [...new Set(attrs.filter(t => !ALLOWED_ATTRS.includes(t)))];
  const hrefs = [...html.matchAll(/href="([^"]*)"/g)].map(m => m[1]);
  const badHrefs = hrefs.filter(h => !/^https?:\/\//.test(h));
  return { badTags, badAttrs, badHrefs, hrefs };
}
{
  // 每个字段都换成攻击载荷的完整契约
  const adv = {
    understanding: A.imgOnerror, needs_clarification: true,
    questions: [{ ask: A.autofocusOnfocus, why: A.svgOnload }],
    safe_next_action: A.imgOnerror,
    recommended_path: { summary: A.svgOnload, why: A.autofocusOnfocus, first_action: A.quote, evidence_ids: [] },
    resources: [{
      name: A.imgOnerror, type: 'government', why: A.svgOnload, claim: A.autofocusOnfocus,
      source_url: A.jsUrl, source_title: A.imgOnerror, source_type: 'official_primary',
      checked_at: '2026-09-13', confidence: 'high',
    }, {
      name: '数据链接资源', type: 'other', why: 'w', claim: 'c',
      source_url: A.dataUrl, source_title: 't', source_type: 'unverified',
      checked_at: '2026-09-13', confidence: 'low',
    }],
    uncertainties: [A.jsUrl, A.dataUrl, A.imgOnerror],
    reality_feedback_prompt: A.imgOnerror, fallback_if_refused: A.normalChinese,
  };
  const { html, copies } = buildResultHtml(adv);
  const a = structuralAudit(html);
  ok('无白名单外的元素标签（img/script/svg 注入被转义成文本）', a.badTags.length === 0, a.badTags.join(','));
  ok('无白名单外的属性（onerror/onfocus/autofocus 若逃逸会在此出现）', a.badAttrs.length === 0, a.badAttrs.join(','));
  ok('全部 href 都是 http(s)', a.badHrefs.length === 0, a.badHrefs.join(' | '));
  ok('javascript:/data: 来源不给 <a>（宁可不给链接）',
    !html.includes(`href="${A.jsUrl}`) && (html.match(/<a /g) || []).length === a.hrefs.length && html.includes('未通过安全校验'),
    `a 数=${(html.match(/<a /g) || []).length} href 数=${a.hrefs.length}`);
  ok('复制原文进 copies（不经 HTML 属性），旧 data-copy=" 形态已消失',
    copies.length === 1 && copies[0] === A.imgOnerror && !/\bdata-copy="/.test(html),
    JSON.stringify(copies));
  // 正常中文动作（含 & < > ' "）：解码往返 = 原文，且复制原文完整
  const dec = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
  ok('正常中文动作（& < > \\\' "）解码往返完整', dec(esc(A.normalChinese)) === A.normalChinese, dec(esc(A.normalChinese)));
  const { html: h2, copies: c2 } = buildResultHtml({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: A.normalChinese, recommended_path: null, resources: [], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' });
  const a2 = structuralAudit(h2);
  ok('正常中文动作渲染无注入且复制原文完整', a2.badTags.length === 0 && a2.badAttrs.length === 0 && c2[0] === A.normalChinese, JSON.stringify([a2.badTags, a2.badAttrs, c2]));
}
// ── 4. 服务端不变量：证据表只签发 http(s) ──
{
  const ev = evidenceTable([
    { title: 'js', url: 'javascript:alert(1)' },
    { title: 'data', url: 'data:text/html,<b>x</b>' },
    { title: 'escape', url: '"><img src=x onerror=1>' },
    { title: 'relative', url: '//no-scheme.example/x' },
    { title: '真来源', url: 'https://synthetic-xss-test.gov.cn/ok' },
  ]);
  ok('非 http(s) 的"结果"不签发证据 id', ev.size() === 1 && ev.has('e1') && ev.get('e1').url === 'https://synthetic-xss-test.gov.cn/ok', JSON.stringify([...ev.forPrompt()]));
  const g = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null,
    resources: [
      { name: '合法资源', type: 'government', why: 'w', claim: '该平台受理噪声类投诉举报', evidence_id: 'e1', confidence: 'high' },
      { name: '引用被删证据', type: 'other', why: 'w', claim: 'c', evidence_id: 'e2', confidence: 'high' },
    ], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, ev);
  ok('引用合法证据 → source_url 是 http(s)；引用失效 id → 资源删除',
    g.resources.length === 1 && g.resources[0].source_url.startsWith('https://') && g.meta.dropped_claims.some(d => d.includes('引用了本轮不存在的证据')),
    JSON.stringify(g.resources.map(r => r.source_url)));
}
// ── 5. 全链路：stub xss 桩经真实 HTTP 管线 ──
{
  rmSync(join(ROOT, 'var', 'xss-e2e.json'), { force: true });
  const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      WS_PROVIDER: 'stub', WS_STUB_CASE: 'xss', WS_SEARCH: 'none', WS_LIVENESS: '0',
      WS_PORT: '8889', WS_HOST: '127.0.0.1', WS_STATE_FILE: join(ROOT, 'var', 'xss-e2e.json'), WS_RATE_LIMIT: '100',
    }), stdio: 'ignore',
  });
  try {
    let up = false;
    for (let i = 0; i < 40 && !up; i++) {
      try { up = (await fetch('http://127.0.0.1:8889/healthz')).ok; } catch (e) { }
      if (!up) await new Promise(r => setTimeout(r, 150));
    }
    if (!up) throw new Error('world 没起来');
    const res = await fetch('http://127.0.0.1:8889/api/world', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ intent: '对抗样本桩：验证前端边界' }),
    });
    const j = await res.json();
    const STUB_UNDERSTANDING = '"><img src=x onerror=window.__xss_injected=1>'; // 与 server/fixtures/stub.json 的 xss 桩原文一致
    ok('xss 桩 200 且对抗内容穿过服务端管线（作为文本）', res.status === 200 && j.understanding === STUB_UNDERSTANDING, JSON.stringify(j).slice(0, 200));
    const { html, copies } = buildResultHtml(j);
    const a = structuralAudit(html);
    ok('全链路：无白名单外标签/属性', a.badTags.length === 0 && a.badAttrs.length === 0, [...a.badTags, ...a.badAttrs].join(','));
    ok('全链路：全部 href 都是 http(s)，桩里的 javascript:/data: 只以文本出现', a.badHrefs.length === 0, a.badHrefs.join(' | '));
    ok('全链路：复制原文 = 桩里的立即动作原文', copies[0] === j.safe_next_action && j.safe_next_action.includes('12345'), JSON.stringify(copies[0]));
  } finally {
    try { child.kill('SIGKILL'); } catch (e) { }
  }
}

console.log(failures ? `\n失败 ${failures} 项` : '\nR1 前端属性/URL 安全边界回归全部通过');
process.exitCode = failures ? 1 : 0;
