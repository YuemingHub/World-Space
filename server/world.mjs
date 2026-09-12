/*
 * World Space — 极薄智能层：只有 1 个业务接口 POST /api/world
 *
 * Slice 1.1 的立场：GUARD BEFORE INTELLIGENCE。
 * 这一层的认知链（不循环、不是 autonomous agent）：
 *   用户上下文
 *   → 一次 LLM 判断关键缺口 / 生成搜索意图（搜索词先做最小化）
 *   → 最多一次搜索 → 服务端给结果编号签发 evidence id
 *   → 一次 LLM 只能引用 id 产出契约草稿
 *   → 护栏（证据绑定 / 授权判定 / 高风险无证据则撤回确定路径）
 *   → 契约 schema 真校验 → JSON
 *
 * 三条不变量：
 *   1. 证据身份由服务端掌握：模型自报的 URL 与 source_type 一律作废；
 *   2. 没有有效证据的资源不进答案，高风险判断没有证据就不给确定路径；
 *   3. 预算 fail closed：状态读不到或写不进就停止付费调用，不把硬上限变成软提示。
 *
 * 硬边界见仓库文档区的"北极星"文件 §4.3。唯一写盘的是预算计数（次数与金额，不含用户正文）。
 */
import http from 'node:http';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { evidenceTable, minimizeQuery } from './evidence.mjs';
import { PROVIDERS, KNOWN } from './search.mjs';
import { guard } from './guard.mjs';
import { validate } from './validate.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SCHEMA = JSON.parse(readFileSync(join(HERE, '..', 'contracts', 'world.schema.json'), 'utf8'));

const CFG = {
  host: process.env.WS_HOST || '127.0.0.1',
  port: Number(process.env.WS_PORT || 8787),
  provider: process.env.WS_PROVIDER || 'stub', // stub | openai_compatible
  llmBase: (process.env.WS_LLM_BASE_URL || '').replace(/\/$/, ''),
  llmKey: process.env.WS_LLM_KEY || '',
  llmModel: process.env.WS_LLM_MODEL || '',
  // 有的网关不支持 response_format（会返回空内容），有的需要额外请求头；都做成配置
  jsonMode: process.env.WS_LLM_JSON_MODE !== '0',
  extraHeaders: (() => { try { return JSON.parse(process.env.WS_LLM_EXTRA_HEADERS || '{}'); } catch (e) { return {}; } })(),
  maxTokens: Number(process.env.WS_MAX_TOKENS || 1500),
  debug: process.env.WS_DEBUG_LLM === '1',
  search: process.env.WS_SEARCH || 'none', // none | fixture | tavily | bocha | aliyun
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
  // 真实 provider 模式必须 fail closed；桩/fixture 模式成本为 0，允许内存兜底以便回归
  failClosed: process.env.WS_BUDGET_FAIL_CLOSED ? process.env.WS_BUDGET_FAIL_CLOSED === '1'
    : (process.env.WS_PROVIDER || 'stub') !== 'stub',
};

/* ── 预算：读不到就停，不静默放行 ─────────────────────────── */
let MEM = { day: today(), calls: 0, month: thisMonth(), cost: 0 };
function today() { return new Date().toISOString().slice(0, 10); }
function thisMonth() { return today().slice(0, 7); }
function roll(s) {
  if (s.day !== today()) { s.day = today(); s.calls = 0; }
  if (s.month !== thisMonth()) { s.month = thisMonth(); s.cost = 0; }
  return s;
}
function loadBudget() {
  try {
    const raw = existsSync(CFG.stateFile) ? JSON.parse(readFileSync(CFG.stateFile, 'utf8')) : {};
    return { state: roll(Object.assign({ day: today(), calls: 0, month: thisMonth(), cost: 0 }, raw)), mode: 'file' };
  } catch (e) {
    if (CFG.failClosed) return { state: null, mode: 'unreadable', error: String(e.message || e).slice(0, 60) };
    if (MEM.day !== today()) MEM = { day: today(), calls: 0, month: thisMonth(), cost: 0 };
    return { state: MEM, mode: 'memory' };
  }
}
function persist(s) {
  try {
    const dir = dirname(CFG.stateFile);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    writeFileSync(CFG.stateFile, JSON.stringify(s));
    return true;
  } catch (e) {
    if (CFG.failClosed) return false;
    MEM = s;
    return true;
  }
}
function overCap(s) {
  if (s.calls >= CFG.dailyCap) return 'daily_calls';
  if (s.cost >= CFG.monthlyCapRmb) return 'monthly_budget';
  return null;
}

/* ── 本轮调用计量（真实次数与真实成本，分开记）───────────── */
const usage = { llm_calls: 0, search_calls: 0, request_cost_rmb: 0, llm_retries: 0 };
function countCall(s, cost) {
  s.calls += 1;
  s.cost = Math.round((s.cost + cost) * 1e6) / 1e6;
  usage.request_cost_rmb = Math.round((usage.request_cost_rmb + cost) * 1e6) / 1e6;
  if (!persist(s)) throw new Error('budget_guard_unavailable');
}

async function llm(s, system, user) {
  if (CFG.provider === 'stub') {
    countCall(s, 0);
    usage.llm_calls += 1;
    const fx = JSON.parse(readFileSync(join(HERE, 'fixtures', 'stub.json'), 'utf8'))[CFG.stubCase];
    return system.indexOf('STAGE: compose') !== -1 ? (fx.compose || fx.triage) : fx.triage;
  }
  const res = await fetch(`${CFG.llmBase}/chat/completions`, {
    method: 'POST',
    headers: Object.assign({ 'content-type': 'application/json', authorization: `Bearer ${CFG.llmKey}` }, CFG.extraHeaders),
    body: JSON.stringify(Object.assign({
      model: CFG.llmModel, temperature: 0.2, max_tokens: CFG.maxTokens,
      messages: [{ role: 'system', content: system }, { role: 'user', content: user }],
    }, CFG.jsonMode ? { response_format: { type: 'json_object' } } : {})),
    signal: AbortSignal.timeout(CFG.timeoutMs),
  });
  if (!res.ok) throw new Error(`llm_http_${res.status}`);
  const j = await res.json();
  const u = j.usage || {};
  countCall(s, ((u.prompt_tokens || 0) / 1000) * CFG.priceInPer1k + ((u.completion_tokens || 0) / 1000) * CFG.priceOutPer1k);
  usage.llm_calls += 1;
  return ((j.choices && j.choices[0] && j.choices[0].message) || {}).content || '';
}

/* F4：真实 pilot 里 6% 的响应解析失败。同一任务、同一 schema 只重试一次；
   每次尝试都照常计入预算（llm 内部 countCall），不重搜、不改意图、不新增问题。
   两次都失败就 fail closed（502），不产出"差不多能用"的答案。 */
async function llmJson(s, system, user) {
  for (let attempt = 1; attempt <= 2; attempt++) {
    const out = await llm(s, system, user);
    if (out && typeof out === 'object') return out; // 桩模式直接返回对象
    try { return parseJsonLoose(out); }
    catch (e) {
      usage.llm_retries = attempt;
      if (CFG.debug) console.log(`[debug] llm_bad_json attempt=${attempt}/1 len=${String(out).length} head=${JSON.stringify(String(out).slice(0, 120))}`);
      if (attempt === 2) throw new Error('llm_bad_json');
    }
  }
}

/** 有的网关在被要求 JSON 模式时返回空串，有的会包一层代码围栏：都按同一套宽松解析处理 */
function parseJsonLoose(txt) {
  const s = String(txt || '').trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
  try { return JSON.parse(s); } catch (e) { /* 继续尝试截取 */ }
  const a = s.indexOf('{'), b = s.lastIndexOf('}');
  if (a >= 0 && b > a) { try { return JSON.parse(s.slice(a, b + 1)); } catch (e) { /* 下一个 */ } }
  throw new Error('llm_bad_json');
}

async function runSearch(s, query) {
  if (CFG.search === 'none') return { skipped: 'no_search_provider', items: [] };
  if (CFG.search === 'fixture') {
    countCall(s, 0);
    usage.search_calls += 1;
    return { items: JSON.parse(readFileSync(join(HERE, 'fixtures', 'search.json'), 'utf8')).items, note: 'fixture_search' };
  }
  if (!CFG.searchKey) return { skipped: 'no_search_key', items: [] };
  if (!KNOWN.includes(CFG.search)) return { skipped: 'unknown_provider', items: [] };
  countCall(s, CFG.priceSearch);
  usage.search_calls += 1;
  return { items: await PROVIDERS[CFG.search](CFG, query) };
}

/* ── 提示词：只给 id，不给它复制 URL 的机会 ───────────────── */
const SHAPE = '{"understanding":string,"needs_clarification":boolean,'
  + '"questions":[{"ask":string,"why":string}],"safe_next_action":string|null,'
  + '"recommended_path":{"summary":string,"why":string,"first_action":string,"evidence_ids":[string]}|null,'
  + '"resources":[{"name":string,"type":string,"why":string,"claim":string,"evidence_id":string,"confidence":"low"|"medium"|"high"}],'
  + '"uncertainties":[string],"reality_feedback_prompt":string,"fallback_if_refused":string}';

const SYSTEM = [
  '你是 World Space 的智能层：帮一个普通人把"想做的一件事"变成今天能做的下一步。',
  '规则：',
  '1. 只追问会实质改变下一步行动的关键事实，最多 2 个；有安全、低成本、不会误导的立即动作时先给动作再追问。禁止问卷化。',
  '2. 资源不等于 AI 工具：政府机构、企业、医院、学校、服务商、地点、人与社区、文档、开源、商品服务都算。',
  '3. 你不能自己写链接，也不能自己声明来源可信度。要引用现实依据，只能引用服务端给出的证据 id（形如 e1）。没有证据就别写进 resources。',
  '4. 法律、医疗、政策、价格、资格、公共服务等高风险判断，没有证据 id 支撑时不要写成确定结论；写进 uncertainties，或把 recommended_path 设为 null。',
  '5. 绝不编造机构、政策、热线、平台。"不知道"是合法输出，比猜一个答案好。',
  '6. 第一步必须是今天能做的动作（打谁的电话、去哪个页面、记录什么），不是研究报告。',
  '7. 需要查现实信息时才给搜索意图；不需要就留空。',
  '8. 搜索意图只保留解决问题所需的事实，不要带姓名、手机号、身份证号、精确住址等个人标识。',
  '9. 严格遵守输出结构，不要加这个结构之外的字段，不要用数组代替对象，不要输出解释或思考过程。',
  `输出结构（${'questions 里每一项必须是对象'}）：${SHAPE}`,
].join('\n');
const TRIAGE_OUT = '输出 {"needs_search":boolean,"search_query":string,"draft":<上面的结构>}';
const COMPOSE_OUT = '只能引用给出的证据 id；按上面的结构输出完整契约，不要改变结构';

/* ── HTTP ─────────────────────────────────────────────────── */
function json(res, code, body) {
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type',
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
  if (req.url === '/healthz') {
    const b = loadBudget();
    return json(res, 200, {
      ok: true, provider: CFG.provider, search: CFG.search, model: CFG.llmModel || 'stub',
      // 只报告"配没配"，绝不回显 key
      search_configured: CFG.search === 'fixture' ? true : (CFG.search !== 'none' && !!CFG.searchKey),
      budget_mode: b.mode, today_calls: b.state ? b.state.calls : null,
      month_cost_rmb: b.state ? b.state.cost : null,
      daily_cap: CFG.dailyCap, monthly_cap_rmb: CFG.monthlyCapRmb, fail_closed: CFG.failClosed,
    });
  }
  if (req.method !== 'POST' || req.url !== '/api/world') return json(res, 404, { error: 'only POST /api/world exists' });

  usage.llm_calls = 0; usage.search_calls = 0; usage.request_cost_rmb = 0; usage.llm_retries = 0;
  const b = loadBudget();
  if (!b.state) return json(res, 503, {
    error: 'budget_guard_unavailable', reason: b.error,
    fallback_if_refused: '预算护栏读不到状态时不产生付费调用。稍后再试，或走手工路径：把意图改写成 3 个搜索词自己去官方站点核对。',
  });
  const s = b.state;
  const cap = overCap(s);
  if (cap) return json(res, 429, {
    error: 'budget_exceeded', limit: cap, daily_cap: CFG.dailyCap, month_cost_rmb: s.cost,
    fallback_if_refused: '今天额度用完：把这件事改写成几个关键词，优先查对应的官方机构、实际服务提供方或真实平台；仍无法判断时，再找这个领域的人工客服、专业人员或现实中的人确认。',
  });

  let body;
  try { body = await readBody(req); } catch (e) { return json(res, 400, { error: e.message }); }
  const intent = String(body.intent || '').trim();
  if (intent.length < 2) return json(res, 400, { error: 'intent_too_short' });
  if (intent.length > 500) return json(res, 400, { error: 'intent_too_long' });
  const ctx = JSON.stringify({ intent, answers: Array.isArray(body.answers) ? body.answers.slice(0, 4) : [], today: today() });

  let out;
  const sMeta = {};
  try {
    const tri = await llmJson(s, `${SYSTEM}\nSTAGE: triage\n${TRIAGE_OUT}`, `输入：${ctx}`);
    out = tri.draft || tri;
    let ev = evidenceTable([]);
    const q = minimizeQuery(tri.search_query || '');
    sMeta.search_query_used = q;
    if (tri.needs_search && q) {
      if (overCap(s)) return json(res, 429, { error: 'budget_exceeded', limit: overCap(s) });
      const sr = await runSearch(s, q);
      ev = evidenceTable(sr.items);
      sMeta.search_skipped_reason = sr.skipped || '';
      sMeta.evidence_fixture = sr.note || '';
      if (ev.size()) {
        const composed = await llmJson(s, `${SYSTEM}\nSTAGE: compose\n${COMPOSE_OUT}`,
          `输入：${ctx}\n可用证据（只能按 id 引用）：${JSON.stringify(ev.forPrompt())}\n待修订草稿：${JSON.stringify(out)}`);
        out = composed.draft || composed;
      } else {
        out.uncertainties = (out.uncertainties || []).concat(['本轮需要查现实信息，但没有拿到任何可用搜索结果']);
      }
    } else {
      sMeta.search_skipped_reason = tri.needs_search ? 'empty_query' : 'not_needed';
    }
    out = guard(out, ev);
    out.meta = Object.assign({}, out.meta, sMeta, {
      searched: ev.size() > 0, evidence_available: ev.size(),
      llm_calls: usage.llm_calls, search_calls: usage.search_calls, llm_retry_count: usage.llm_retries,
      request_cost_rmb: usage.request_cost_rmb, month_cost_rmb: s.cost,
      budget_mode: b.mode, model: CFG.llmModel || 'stub',
    });
    const errs = validate(SCHEMA, out);
    if (errs.length) return json(res, 502, {
      error: 'intelligence_contract_failure', violations: errs.slice(0, 12),
      fallback_if_refused: '智能层这轮没按契约交付，不要拿它的结果去行动。', partial: out,
    });
    json(res, 200, out);
  } catch (e) {
    const code = String(e.message || e);
    if (code.indexOf('budget_guard_unavailable') === 0) {
      return json(res, 503, { error: 'budget_guard_unavailable', fallback_if_refused: '预算状态写不进去就不继续产生付费调用；请走手工路径或稍后再试。' });
    }
    json(res, 502, { error: 'intelligence_unavailable', code: code.slice(0, 60) });
  } finally {
    console.log(`${new Date().toISOString()} ${req.method} ${res.statusCode} ${Date.now() - t0}ms llm=${usage.llm_calls} search=${usage.search_calls} req_cost=${usage.request_cost_rmb} month=${s.cost} calls=${s.calls}`);
  }
});
server.listen(CFG.port, CFG.host, () => console.log(`world api http://${CFG.host}:${CFG.port} provider=${CFG.provider} search=${CFG.search} caps=${CFG.dailyCap}/day ${CFG.monthlyCapRmb}RMB/month fail_closed=${CFG.failClosed}`));
