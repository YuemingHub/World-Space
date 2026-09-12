/*
 * Search adapter 形状自测 —— 合成样本，**不是搜索结果，不构成证据，不进入任何 pilot 报告**。
 * 它只验证一件事：provider 的响应形状能被正确翻译成内部格式，且外层拿不到 provider 私有字段。
 * 不联网、不调用任何 API、不产生 evidence id。
 */
import { tavily, bocha, aliyun } from '../server/search.mjs';

const SYNTHETIC_TAVILY = {
  query: 'SYNTHETIC-QUERY',
  answer: 'SYNTHETIC-ANSWER-MUST-BE-IGNORED',
  results: [
    { title: '合成样本一', url: 'https://example-synthetic.invalid/a', content: '摘要一', score: 0.9, published_date: '2026-01-02' },
    { title: '合成样本二', url: 'https://example-synthetic.invalid/b', content: '摘要二' },
  ],
};
const SYNTHETIC_BOCHA = { data: { webPages: { value: [{ name: '合成', url: 'https://example-synthetic.invalid/c', summary: '摘要', datePublished: '2026-02-03' }] } } };
const SYNTHETIC_ALIYUN = { pageItems: [{ title: '合成', url: 'https://example-synthetic.invalid/d', snippet: '摘要', publishedTime: '2026-03-04' }] };

const realFetch = globalThis.fetch;
let failures = 0;

async function check(name, fn, payload, expect) {
  globalThis.fetch = async () => ({ ok: true, status: 200, json: async () => payload });
  let out;
  try { out = await fn({ searchKey: 'SYNTHETIC-KEY-NOT-REAL', searchUrl: '' }, 'q'); }
  catch (e) { console.log(`✗ ${name}: 抛错 ${e.message}`); failures++; return; }
  const keysOk = out.every(x => Object.keys(x).every(k => ['title', 'url', 'snippet', 'published_at'].includes(k)));
  const ok = out.length === expect.length && keysOk;
  console.log(`${ok ? '✓' : '✗'} ${name}: 条目 ${out.length}（期望 ${expect.length}），字段只含内部格式=${keysOk}`);
  if (!ok) failures++;
}
await check('tavily', tavily, SYNTHETIC_TAVILY, [1, 2]);
await check('bocha', bocha, SYNTHETIC_BOCHA, [1]);
await check('aliyun', aliyun, SYNTHETIC_ALIYUN, [1]);

// 请求形状：认证只走 Authorization: Bearer，key 不进任何请求体；Tavily 的 answer 能力保持关闭
const realFetch2 = globalThis.fetch;
{
  const KEY = 'SYNTHETIC-KEY-NOT-REAL';
  let captured = null;
  globalThis.fetch = async (url, opts) => {
    captured = { url, headers: opts.headers || {}, body: JSON.parse(opts.body || '{}') };
    return { ok: true, status: 200, json: async () => SYNTHETIC_TAVILY };
  };
  await tavily({ searchKey: KEY, searchUrl: '' }, 'q');
  const checks = {
    'Authorization=Bearer': captured.headers.authorization === `Bearer ${KEY}`,
    'body 无 api_key 字段': !('api_key' in captured.body),
    'body 全文无 key': JSON.stringify(captured.body).indexOf(KEY) === -1,
    'include_answer=false': captured.body.include_answer === false,
    'include_raw_content=false': captured.body.include_raw_content === false,
    '只带搜索参数': ['query', 'max_results', 'search_depth', 'include_answer', 'include_raw_content']
      .every(k => k in captured.body) && Object.keys(captured.body).length === 5,
  };
  Object.entries(checks).forEach(([k, ok]) => { console.log(`${ok ? '✓' : '✗'} tavily 请求形状：${k}`); if (!ok) failures++; });
}
globalThis.fetch = realFetch2;

// 出错时不能把 key 带进错误信息
globalThis.fetch = async () => ({ ok: false, status: 401, json: async () => ({}) });
let msg = '';
try { await tavily({ searchKey: 'SYNTHETIC-KEY-NOT-REAL', searchUrl: '' }, 'q'); } catch (e) { msg = e.message; }
const leaks = msg.indexOf('SYNTHETIC-KEY-NOT-REAL') !== -1;
console.log(`${msg && !leaks ? '✓' : '✗'} 出错信息只带状态码且不含 key：${JSON.stringify(msg)}`);
if (!msg || leaks) failures++;

globalThis.fetch = realFetch;
console.log('\nSYNTHETIC SHAPE TEST —— 合成样本，不是搜索结果，不得当作证据或 pilot 数据。');
console.log(failures ? `失败 ${failures} 项` : '全部通过');
process.exitCode = failures ? 1 : 0;
