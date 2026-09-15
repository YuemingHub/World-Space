/*
 * 搜索多把钥匙自动切换自测 —— 全程离线合成，**不发任何真实请求、不调任何 API、0 花费**。
 * 它要证明的是 Founder 要的那句话："一个跑不通再跑另一个"，
 * 以及一句她没说要、但必须守住的："换钥匙不许把真正的故障藏起来"。
 *
 * 合成 key 一律用 SYNTHETIC- 前缀，测试顺带断言它们不会出现在任何输出/错误信息里。
 */
import { tavily, searchKeys } from '../server/search.mjs';

const K1 = 'SYNTHETIC-KEY-ONE-NOT-REAL';
const K2 = 'SYNTHETIC-KEY-TWO-NOT-REAL';
const PAYLOAD = { results: [{ title: '合成样本', url: 'https://example-synthetic.invalid/a', content: '摘要', published_date: '2026-01-02' }] };

let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };

const realFetch = globalThis.fetch;
let calls = [];
/** statuses: 每把钥匙依次返回什么；'reject' 表示连接级失败 */
function mock(statuses) {
  calls = [];
  globalThis.fetch = async (url, opts) => {
    const i = calls.length;
    calls.push((opts.headers || {}).authorization || '');
    const st = statuses[Math.min(i, statuses.length - 1)];
    if (st === 'reject') { const e = new Error('SYNTHETIC network failure'); e.cause = 'offline'; throw e; }
    return { ok: st === 200, status: st, json: async () => PAYLOAD };
  };
}
async function run(cfg) {
  try { return { items: await tavily(cfg, 'q'), err: null }; }
  catch (e) { return { items: null, err: e }; }
}

/* ---- 1. searchKeys 解析规则 ---- */
ok('单把钥匙 → 1 把', searchKeys({ searchKey: K1 }).length === 1);
ok('逗号分隔多把 → 按顺序 2 把', searchKeys({ searchKey: `${K1},${K2}` }).join('|') === `${K1}|${K2}`);
ok('第二变量 WS_SEARCH_KEY_2 → 2 把且顺序为主先备后',
  searchKeys({ searchKey: K1, searchKey2: K2 }).join('|') === `${K1}|${K2}`);
ok('两行写成同一把 → 去重成 1 把（不浪费一次配额）',
  searchKeys({ searchKey: `${K1},${K1}`, searchKey2: K1 }).length === 1);
ok('首尾空格与空段被清掉', searchKeys({ searchKey: ` ${K1} , ,${K2} ` }).join('|') === `${K1}|${K2}`);
ok('完全没配 → 0 把', searchKeys({ searchKey: '', searchKey2: '' }).length === 0);
ok('只配了备用那一把，也算"配了钥匙"（不会静默跳过搜索）',
  searchKeys({ searchKey: '', searchKey2: K2 }).join('|') === K2);

/* ---- 2. 主钥匙能用：不该碰第二把 ---- */
mock([200, 200]);
let r = await run({ searchKey: K1, searchKey2: K2, search: 'tavily' });
ok('主钥匙能用 → 只发 1 次请求', calls.length === 1 && !r.err, `发了 ${calls.length} 次`);
ok('主钥匙能用 → 用的就是第 1 把', calls[0] === `Bearer ${K1}`, calls[0]);
ok('主钥匙能用 → 拿到内部格式的条目', Array.isArray(r.items) && r.items.length === 1 && r.items[0].title === '合成样本');

/* ---- 3. 主钥匙被拒 → 自动换第二把 ---- */
for (const [st, name] of [[401, '无效/已撤销'], [403, '被禁止'], [429, '配额耗尽']]) {
  mock([st, 200]);
  r = await run({ searchKey: K1, searchKey2: K2, search: 'tavily' });
  ok(`主钥匙 ${st}（${name}）→ 自动换第二把并成功`,
    calls.length === 2 && !r.err && r.items.length === 1 && calls[1] === `Bearer ${K2}`,
    `请求 ${calls.length} 次 err=${r.err && r.err.message}`);
}

/* ---- 4. 两把都不行 → 报错，绝不假装成功 ---- */
mock([401, 401]);
r = await run({ searchKey: K1, searchKey2: K2, search: 'tavily' });
ok('两把都被拒 → 抛错而不是返回空结果装成"搜到了但没结果"',
  !!r.err && r.items === null && /search_http_401/.test(r.err.message), r.err && r.err.message);

/* ---- 5. 换钥匙不许掩盖真实故障 ---- */
mock(['reject', 'reject']);
r = await run({ searchKey: K1, searchKey2: K2, search: 'tavily' });
ok('网络断了 → **不换**第二把，直接把真实故障抛出（换一把也一样断）',
  calls.length === 1 && !!r.err && !/search_http_/.test(r.err.message), `请求 ${calls.length} 次`);

mock([500, 200]);
r = await run({ searchKey: K1, searchKey2: K2, search: 'tavily' });
ok('provider 500 → 不换钥匙（这是服务坏了，不是钥匙坏了）',
  calls.length === 1 && !!r.err && /search_http_500/.test(r.err.message), `请求 ${calls.length} 次`);

mock([503, 200]);
r = await run({ searchKey: K1, searchKey2: K2, search: 'tavily' });
ok('provider 503 → 同样不换钥匙', calls.length === 1 && !!r.err && /search_http_503/.test(r.err.message));

/* ---- 6. 一把都没有 → 明确报没配钥匙，不发请求 ---- */
mock([200]);
r = await run({ searchKey: '', searchKey2: '', search: 'tavily' });
ok('没配任何钥匙 → 不发请求，报 search_no_key',
  calls.length === 0 && !!r.err && /search_no_key/.test(r.err.message), r.err && r.err.message);

/* ---- 7. 三把依次试到第三把 ---- */
mock([401, 401, 200]);
r = await run({ searchKey: `${K1},SYNTHETIC-KEY-MID-NOT-REAL`, searchKey2: K2, search: 'tavily' });
ok('三把时依次试到第 3 把才成功',
  calls.length === 3 && !r.err && calls[2] === `Bearer ${K2}`, `请求 ${calls.length} 次`);

/* ---- 8. 任何输出与错误里都不许出现钥匙明文 ---- */
let leak = '';
try {
  mock([401, 401]);
  await tavily({ searchKey: K1, searchKey2: K2, search: 'tavily' }, 'q');
} catch (e) { leak = e.message + ' ' + JSON.stringify(e); }
ok('错误对象里不含任何一把钥匙明文', leak.indexOf(K1) === -1 && leak.indexOf(K2) === -1, leak.slice(0, 80));
const sentAuth = calls.join(',');
ok('钥匙只出现在 Authorization 头，不进 URL 也不进请求体',
  !/api[_-]?key/i.test(sentAuth) && calls.every(c => /^Bearer SYNTHETIC-KEY/.test(c)), sentAuth.slice(0, 60));

globalThis.fetch = realFetch;
console.log(`\n合成钥匙：${K1.slice(0, 9)}… / ${K2.slice(0, 9)}… —— 全程离线，未发出任何真实请求。`);
console.log(failures ? `失败 ${failures} 项` : '全部通过');
process.exitCode = failures ? 1 : 0;
