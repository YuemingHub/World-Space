/*
 * World Space — 极薄智能层：只有 1 个业务接口 POST /api/world
 *
 * 认知链在这一层发生（不是 autonomous agent）：
 *   用户上下文 → 一次 LLM 判断关键缺口 / 是否需要访问现实 → （最多一次）搜索
 *   → 一次 LLM 基于搜索结果产出结构化契约 → 证据纪律校验 → JSON
 *
 * 硬边界（见 docs/v2/NORTH_STAR.md §4.3）：无数据库、无服务端会话、无用户系统、
 * 无队列、无缓存平台、不循环调用工具、1 个 LLM provider + 1 个 Search provider。
 * 唯一写盘的是预算计数（次数与金额，绝不含用户正文）。
 */
import http from 'node:http';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const CFG = {
  host: process.env.WS_HOST || '127.0.0.1',
  port: Number(process.env.WS_PORT || 8787),
  provider: process.env.WS_PROVIDER || 'stub', // stub | openai_compatible
  llmBase: (process.env.WS_LLM_BASE_URL || '').replace(/\/$/, ''),
  llmKey: process.env.WS_LLM_KEY || '',
  llmModel: process.env.WS_LLM_MODEL || '',
  search: process.env.WS_SEARCH || 'none', // none | bocha | aliyun
  searchKey: process.env.WS_SEARCH_KEY || '',
  searchUrl: process.env.WS_SEARCH_URL || '',
  dailyCap: Number(process.env.WS_DAILY_CAP || 50),
  monthlyCapRmb: Number(process.env.WS_MONTHLY_CAP_RMB || 20),
  priceSearch: Number(process.env.WS_RMB_PER_SEARCH || 0.012),
  priceInPer1k: Number(process.env.WS_RMB_PER_1K_IN || 0.002),
  priceOutPer1k: Number(process.env.WS_RMB_PER_1K_OUT || 0.008),
  timeoutMs: Number(process.env.WS_TIMEOUT_MS || 20000),
  stubCase: process.env.WS_STUB_CASE || 'ok',
  stateFile: process.env.WS_STATE_FILE || join(HERE, '..', 'var', 'budget.json'),
};

const HIGH_RISK = ['法', '条例', '政策', '规定', '医保', '保险', '报销', '补贴', '资格', '证书', '职业标准',
  '备案', '许可', '价格', '收费', '免费额度', '部门', '热线', '医院', '护理', '药品', '名单', '官方', '定点'];
const SOURCE_TYPES = ['official_primary', 'trusted_secondary', 'third_party', 'unverified'];
const RESOURCE_TYPES = ['government', 'institution', 'company', 'service', 'place', 'person',
  'community', 'document', 'dataset', 'open_source', 'software', 'ai_tool', 'product', 'other'];

/* ── 预算：只有计数，没有正文 ─────────────────────────────── */
function today() { const d = new Date(); return d.toISOString().slice(0, 10); }
function thisMonth() { return today().slice(0, 7); }
function loadBudget() {
  let s = { day: today(), calls: 0, month: thisMonth(), cost: 0 };
  try { if (existsSync(CFG.stateFile)) s = Object.assign(s, JSON.parse(readFileSync(CFG.stateFile, 'utf8'))); } catch (e) { /* 计数损坏就当归零 */ }
  if (s.day !== today()) { s.day = today(); s.calls = 0; }
  if (s.month !== thisMonth()) { s.month = thisMonth(); s.cost = 0; }
  return s;
}
function saveBudget(s) {
  try { const dir = dirname(CFG.stateFile); if (!existsSync(dir)) mkdirSync(dir, { recursive: true }); writeFileSync(CFG.stateFile, JSON.stringify(s)); } catch (e) { /* 计数写不进就放行，不拿这个卡住用户 */ }
}
function spend(s, cost) { s.calls += 1; s.cost = Math.round((s.cost + cost) * 1000) / 1000; saveBudget(s); }
function overCap(s) {
  if (s.calls >= CFG.dailyCap) return 'daily_calls';
  if (s.cost >= CFG.monthlyCapRmb) return 'monthly_budget';
  return null;
}

/* ── provider：LLM ────────────────────────────────────────── */
async function llm(s, system, user) {
  if (CFG.provider === 'stub') { const out = await stubModel(user); spend(s, 0); return out; }
  const res = await fetch(`${CFG.llmBase}/chat/completions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${CFG.llmKey}` },
    body: JSON.stringify({
      model: CFG.llmModel, temperature: 0.2, response_format: { type: 'json_object' },
      messages: [{ role: 'system', content: system }, { role: 'user', content: user }],
    }),
    signal: AbortSignal.timeout(CFG.timeoutMs),
  });
  if (!res.ok) throw new Error(`llm_http_${res.status}`);
  const j = await res.json();
  const u = j.usage || {};
  spend(s, ((u.prompt_tokens || 0) / 1000) * CFG.priceInPer1k + ((u.completion_tokens || 0) / 1000) * CFG.priceOutPer1k);
  const txt = (j.choices && j.choices[0] && j.choices[0].message.content) || '';
  try { return JSON.parse(txt); } catch (e) { throw new Error('llm_bad_json'); }
}

/* 离线桩：只用于验证契约、证据纪律与预算护栏，不代表智能水平 */
async function stubModel(user) {
  const fx = JSON.parse(readFileSync(join(HERE, 'fixtures', 'stub.json'), 'utf8'))[CFG.stubCase];
  return (user.indexOf('STAGE: compose') === 0) ? fx.compose : fx.triage;
}

/* ── provider：搜索（结果只是候选证据） ───────────────────── */
async function search(s, query) {
  if (CFG.search === 'none' || !CFG.searchKey) return { skipped: 'no_search_provider', items: [] };
  spend(s, CFG.priceSearch);
  if (CFG.search === 'bocha') {
    const res = await fetch('https://api.bochaai.com/v1/web-search', {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${CFG.searchKey}` },
      body: JSON.stringify({ query, summary: true, count: 8 }),
      signal: AbortSignal.timeout(CFG.timeoutMs),
    });
    if (!res.ok) throw new Error(`search_http_${res.status}`);
    const j = await res.json();
    const lst = (((j.data || {}).webPages || {}).value) || [];
    return { items: lst.map(x => ({ title: x.name, url: x.url, snippet: x.summary || x.snippet, published_at: x.datePublished || '' })) };
  }
  if (CFG.search === 'aliyun') {
    const res = await fetch(CFG.searchUrl || 'https://maasaisearchproxy.aliyuncs.com/api/web-search', {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${CFG.searchKey}` },
      body: JSON.stringify({ query, limit: 8 }),
      signal: AbortSignal.timeout(CFG.timeoutMs),
    });
    if (!res.ok) throw new Error(`search_http_${res.status}`);
    const j = await res.json();
    const lst = (j.pageItems || j.items || []);
    return { items: lst.map(x => ({ title: x.title, url: x.url, snippet: x.snippet || x.content, published_at: x.publishedTime || '' })) };
  }
  throw new Error('search_provider_unknown');
}

/* ── 提示词（契约 + 证据纪律 + 不假装知道）───────────────── */
const SYSTEM = [
  '你是 World Space 的智能层：帮一个普通人把"想做的一件事"变成今天能做的下一步。',
  '规则：',
  '1. 只追问会实质改变下一步行动的关键事实，最多 2 个；存在安全低成本不会误导的立即动作时，先给动作再追问。禁止问卷化。',
  '2. 资源不等于 AI 工具：政府机构、企业、医院、学校、服务商、地点、人与社区、文档、开源、商品服务都算。不要只给软件。',
  '3. 每条资源都要有 claim / source_url / source_title / source_type / confidence。source_type 只能是 official_primary、trusted_secondary、third_party、unverified。',
  '4. 法律、医疗、政策、价格、资格、公共服务等高风险与时效性事实：有官方原始来源必须用官方原始来源；第三方不得单独支撑确定结论；不确定就把 claim 的 confidence 设为 low 或写进 uncertainties。',
  '5. 绝不编造机构、政策、热线、平台或链接。不知道是合法输出：recommended_path 给 null，并把原因写进 uncertainties。',
  '6. 第一步必须是今天能做的动作（打谁的电话、去哪个页面、记录什么），不是研究报告。',
  '7. 只输出 JSON，不加解释文字。',
].join('\n');

const TRIAGE_SCHEMA = '输出 {"needs_search":true/false,"search_query":"最多1条，不需要则空串","draft":{...契约...}}';
const COMPOSE_SCHEMA = '基于给出的搜索结果修订 draft，输出完整契约 JSON（字段同上）';

/* ── 证据纪律校验：不合格的高风险结论主动删除 ───────────── */
function enforce(c) {
  const dropped = [];
  const out = JSON.parse(JSON.stringify(c || {}));
  out.questions = Array.isArray(out.questions) ? out.questions.slice(0, 2) : [];
  if (Array.isArray(out.questions) && out.questions.length > 2) dropped.push('questions_over_2');
  out.needs_clarification = !!out.needs_clarification;
  out.resources = (Array.isArray(out.resources) ? out.resources : []).slice(0, 3).map(r => {
    const x = Object.assign({}, r);
    if (!SOURCE_TYPES.includes(x.source_type)) { x.source_type = 'unverified'; }
    if (!RESOURCE_TYPES.includes(x.type)) x.type = 'other';
    if (!['low', 'medium', 'high'].includes(x.confidence)) x.confidence = 'low';
    const text = `${x.claim || ''} ${x.why || ''} ${x.name || ''}`;
    x.high_risk = HIGH_RISK.some(k => text.indexOf(k) !== -1);
    if (x.high_risk && !x.source_url) x.source_type = 'unverified';
    return x;
  });
  out.resources = out.resources.filter(r => {
    const weak = r.high_risk && (r.source_type === 'third_party' || r.source_type === 'unverified' || !r.source_url);
    if (weak) {
      dropped.push(`${r.name || '未命名资源'}：高风险结论缺少官方来源，已删除，转为待确认`);
      return false;
    }
    return true;
  });
  out.uncertainties = Array.isArray(out.uncertainties) ? out.uncertainties : [];
  if (dropped.length) out.uncertainties = out.uncertainties.concat(dropped);
  if (!out.recommended_path && !out.safe_next_action && !out.questions.length && !out.uncertainties.length) {
    out.uncertainties.push('这一轮没有给出可靠路径，也没有可立即做的安全动作——属于失败输出，请换人工搜索路径');
  }
  out.meta = Object.assign({}, out.meta, { dropped_claims: dropped });
  return out;
}

/* ── HTTP ─────────────────────────────────────────────────── */
function json(res, code, body) {
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'content-type',
    'access-control-allow-methods': 'POST, OPTIONS, GET',
  });
  res.end(JSON.stringify(body));
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    let buf = '';
    req.on('data', d => { buf += d; if (buf.length > 20000) { reject(new Error('body_too_large')); req.destroy(); } });
    req.on('end', () => { try { resolve(buf ? JSON.parse(buf) : {}); } catch (e) { reject(new Error('body_bad_json')); } });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  const t0 = Date.now();
  if (req.method === 'OPTIONS') return json(res, 204, {});
  if (req.url === '/healthz') { const s = loadBudget(); return json(res, 200, { ok: true, provider: CFG.provider, search: CFG.search, model: CFG.llmModel || 'stub', today_calls: s.calls, month_cost_rmb: s.cost, daily_cap: CFG.dailyCap, monthly_cap_rmb: CFG.monthlyCapRmb }); }
  if (req.method !== 'POST' || req.url !== '/api/world') return json(res, 404, { error: 'only POST /api/world exists' });

  const s = loadBudget();
  const cap = overCap(s);
  if (cap) return json(res, 429, { error: 'budget_exceeded', limit: cap, fallback_if_refused: '用页面上的手工搜索路径：把意图改写成 3 个搜索词，自己去官方站点核对' });

  let body;
  try { body = await readBody(req); } catch (e) { return json(res, 400, { error: e.message }); }
  const intent = String(body.intent || '').trim();
  if (intent.length < 2) return json(res, 400, { error: 'intent_too_short' });
  if (intent.length > 500) return json(res, 400, { error: 'intent_too_long' });
  const answers = Array.isArray(body.answers) ? body.answers.slice(0, 4) : [];

  const ctx = JSON.stringify({ intent, answers, today: today() });
  try {
    const tri = await llm(s, `${SYSTEM}\nSTAGE: triage\n${TRIAGE_SCHEMA}`, `输入：${ctx}`);
    let contract = tri.draft || tri;
    const q = String(tri.search_query || '').trim();
    let evid = { skipped: 'not_needed', items: [] };
    if (tri.needs_search && q) {
      const cap2 = overCap(s);
      if (cap2) return json(res, 429, { error: 'budget_exceeded', limit: cap2 });
      evid = await search(s, q);
      if (evid.items.length) {
        const composed = await llm(s, `${SYSTEM}\nSTAGE: compose\n${COMPOSE_SCHEMA}`, `输入：${ctx}\n搜索结果（仅作候选证据，有 URL 不等于可信）：${JSON.stringify(evid.items.slice(0, 6))}\n待修订草稿：${JSON.stringify(contract)}`);
        contract = composed.draft || composed;
      }
    }
    const out = enforce(contract);
    out.meta = Object.assign({ searched: evid.items.length > 0, search_skipped_reason: evid.skipped, llm_calls: CFG.provider === 'stub' ? 2 : (evid.items.length ? 2 : 1), search_calls: evid.items.length ? 1 : 0, est_cost_rmb: s.cost, model: CFG.llmModel || 'stub' }, out.meta || {});
    json(res, 200, out);
  } catch (e) {
    json(res, 502, { error: 'intelligence_unavailable', code: String(e.message || e).slice(0, 60) });
  } finally {
    console.log(`${new Date().toISOString()} ${req.method} ${req.url} ${res.statusCode} ${Date.now() - t0}ms calls=${s.calls} cost=${s.cost}`);
  }
});
server.listen(CFG.port, CFG.host, () => console.log(`world api on http://${CFG.host}:${CFG.port} provider=${CFG.provider} search=${CFG.search} caps=${CFG.dailyCap}/day ${CFG.monthlyCapRmb}RMB/month`));
