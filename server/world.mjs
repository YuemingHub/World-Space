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
import { isIP } from 'node:net';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, normalize, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { evidenceTable, minimizeQuery, filterLive } from './evidence.mjs';
import { PROVIDERS, KNOWN } from './search.mjs';
import { guard } from './guard.mjs';
import { validate } from './validate.mjs';
import { localDate, localMonth } from './date.mjs';
import { createAuth, sessionTokenFrom } from './auth.mjs';

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
  // 部署边界：来源白名单（逗号分隔）、每 IP 每分钟请求上限、F3 链接存活检查
  liveness: process.env.WS_LIVENESS !== '0',
  rateLimitPerMin: Number(process.env.WS_RATE_LIMIT || 20),
  allowedOrigins: (process.env.WS_ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean),
  // 反向代理边界：默认只认 socket 对端地址；显式开启信任后，且对端正是配置里的受信代理时，
  // 才读代理追加的 X-Forwarded-For。只支持单层受信代理（Nginx → Node）。
  trustProxy: process.env.WS_TRUST_PROXY === '1',
  trustedProxies: (process.env.WS_TRUSTED_PROXIES || '127.0.0.1,::1').split(',').map(s => s.trim()).filter(Boolean),
  webDir: join(HERE, '..', 'web', 'v2'),
};

/* ── 访问门：谁能进入（缺省开启；显式 WS_AUTH_ENABLED=0 才关闭，且启动日志大声声明）── */
const AUTH = createAuth(process.env);

/* ── 预算：读不到就停，不静默放行 ─────────────────────────── */
let MEM = { day: localDate(), calls: 0, month: localMonth(), cost: 0 };
function roll(s) {
  if (s.day !== localDate()) { s.day = localDate(); s.calls = 0; }
  if (s.month !== localMonth()) { s.month = localMonth(); s.cost = 0; }
  return s;
}
function loadBudget() {
  try {
    const raw = existsSync(CFG.stateFile) ? JSON.parse(readFileSync(CFG.stateFile, 'utf8')) : {};
    return { state: roll(Object.assign({ day: localDate(), calls: 0, month: localMonth(), cost: 0 }, raw)), mode: 'file' };
  } catch (e) {
    if (CFG.failClosed) return { state: null, mode: 'unreadable', error: String(e.message || e).slice(0, 60) };
    if (MEM.day !== localDate()) MEM = { day: localDate(), calls: 0, month: localMonth(), cost: 0 };
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

/* ── 预留式准入：硬上限的语义在这里，不在事后的记账里 ─────────────
   计数本身每次从磁盘重读再累加（请求各自的副本会过期：真实模式下两条并发请求
   跨 await 各自回写就会丢计数，延迟网关并发回归盯住这一点）。
   admit = 检查 + 预占 + 落盘，是同步的一段代码，中间没有 await——事件循环保证
   并发请求不可能同时穿过同一次检查，所以上限 50 就是 50，临界并发穿透不了。
   调用返回后 settle 按实际用量多退少补；provider 失败全额退预留（未消费）。 */
function budgetExceeded(limit) { const e = new Error('budget_exceeded'); e.limit = limit; return e; }

/* 单次 LLM 调用的预留额：输出按 max_tokens 硬上限、输入按 1 万 token 上限估算
   （系统提示词 + 最多 8 条证据摘要的量级）。预留只可能多算，不可能少算。 */
const RESERVE_IN_TOKENS = 10000;
function llmHold() {
  return CFG.priceOutPer1k * CFG.maxTokens / 1000 + CFG.priceInPer1k * RESERVE_IN_TOKENS / 1000;
}

function admit(s, usage, hold) {
  const fresh = loadBudget();
  if (!fresh.state) throw new Error('budget_guard_unavailable');
  const st = roll(fresh.state);
  if (st.calls >= CFG.dailyCap) throw budgetExceeded('daily_calls');
  if (st.cost >= CFG.monthlyCapRmb) throw budgetExceeded('monthly_budget');
  st.calls += 1;
  st.cost = Math.round((st.cost + hold) * 1e6) / 1e6;
  if (!persist(st)) throw new Error('budget_guard_unavailable');
  s.calls = st.calls; s.cost = st.cost;
  usage.hold = hold;
}
function settle(s, usage, actual) {
  const hold = usage.hold || 0;
  usage.hold = 0;
  usage.request_cost_rmb = Math.round((usage.request_cost_rmb + actual) * 1e6) / 1e6;
  if (Math.abs(hold - actual) < 1e-9) return; // 预留即实价（搜索按次、桩零成本），无需回写
  const fresh = loadBudget();
  if (!fresh.state) throw new Error('budget_guard_unavailable');
  const st = fresh.state;
  st.cost = Math.round((st.cost - hold + actual) * 1e6) / 1e6;
  if (!persist(st)) throw new Error('budget_guard_unavailable');
  s.cost = st.cost;
}

async function llm(s, usage, system, user) {
  if (CFG.provider === 'stub') {
    admit(s, usage, 0);
    usage.llm_calls += 1;
    const fx = JSON.parse(readFileSync(join(HERE, 'fixtures', 'stub.json'), 'utf8'))[CFG.stubCase];
    if (system.indexOf('STAGE: compose') !== -1) {
      // 回执差分证据：回执真的进了模型输入时，桩才切换到"推进后"的应答——
      // 服务端漏传 receipt 的话，第二轮和第一轮输出一模一样，回归立刻抓住。
      if (user.indexOf('"receipt":{') !== -1 && fx.compose_with_receipt) return fx.compose_with_receipt;
      return fx.compose || fx.triage;
    }
    return fx.triage;
  }
  admit(s, usage, llmHold()); // 先预占，再发起付费调用；provider 失败由 settle 全额退预留
  let cost = 0, content = '';
  try {
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
    cost = ((u.prompt_tokens || 0) / 1000) * CFG.priceInPer1k + ((u.completion_tokens || 0) / 1000) * CFG.priceOutPer1k;
    content = ((j.choices && j.choices[0] && j.choices[0].message) || {}).content || '';
  } finally {
    settle(s, usage, cost);
  }
  usage.llm_calls += 1;
  return content;
}

/* F4：真实 pilot 里 6% 的响应解析失败。同一任务、同一 schema 只重试一次；
   每次尝试都照常计入预算（llm 内部 countCall），不重搜、不改意图、不新增问题。
   两次都失败就 fail closed（502），不产出"差不多能用"的答案。 */
async function llmJson(s, usage, system, user) {
  for (let attempt = 1; attempt <= 2; attempt++) {
    const out = await llm(s, usage, system, user);
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

async function runSearch(s, usage, query) {
  if (CFG.search === 'none') return { skipped: 'no_search_provider', items: [] };
  if (CFG.search === 'fixture') {
    admit(s, usage, 0);
    usage.search_calls += 1;
    return { items: JSON.parse(readFileSync(join(HERE, 'fixtures', 'search.json'), 'utf8')).items, note: 'fixture_search', liveness_dropped: 0 };
  }
  if (!CFG.searchKey) return { skipped: 'no_search_key', items: [] };
  if (!KNOWN.includes(CFG.search)) return { skipped: 'unknown_provider', items: [] };
  admit(s, usage, CFG.priceSearch); // 搜索按次计价，预留即实价；provider 失败也照计（调用已发生）
  usage.search_calls += 1;
  let items;
  try {
    items = await PROVIDERS[CFG.search](CFG, query);
  } finally {
    settle(s, usage, CFG.priceSearch);
  }
  let liveness_dropped = 0;
  if (CFG.liveness && items.length) {
    const lr = await filterLive(items);
    items = lr.items;
    liveness_dropped = lr.dropped;
  }
  return { items, liveness_dropped };
}

/* ── 提示词：只给 id，不给它复制 URL 的机会 ───────────────── */
const SHAPE = '{"understanding":string,"needs_clarification":boolean,'
  + '"questions":[{"ask":string,"why":string}],"safe_next_action":string|null,'
  + '"next_action":{"text":string,"done_when":string,"mode":"internal"|"handoff"|"human","handoff_task":string,"handoff_target":string}|null,'
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
  '9. next_action 是结果页唯一的"现在只做这一步"（优先提炼自 recommended_path.first_action 或 safe_next_action，不要是另一件事）。'
  + 'text 一句话说清今天做什么；done_when 写"怎么算做完"，必须可验证（拿到工单号/对方答复/工具给出的具体产出），不写"了解一下"这类没法验证的。'
  + 'mode 三选一：internal（在这一个页面里就能完成的分析、整理、决定）；handoff（这一步交给现成的外部通用 AI 工具明显更好——只适用于开放式的整理/改写/梳理/生成类工作，'
  + '此时 handoff_task 必须给完整任务书：用户复制→粘贴到那个工具→直接能用，handoff_target 填工具名）；human（必须本人进入现实世界：打电话、去窗口、见面、实地记录）。'
  + '查现实信息、联系机构、办事、买东西，永远不是 handoff。',
  '10. 输入里带 receipt（上一轮行动回执）时：现实已经向前推进了一轮。禁止把原始意图当新问题重新回答，禁止重复上一轮的路径；'
  + '先确认已经推进到哪一步，再基于回执里的现实新信息给下一步。回执表明原路不通（被拒、没效果、外部工具只给了套话）时，必须换下一个责任方或换方法，不维护原推荐。',
  '11. 严格遵守输出结构，不要加这个结构之外的字段，不要用数组代替对象，不要输出解释或思考过程。',
  `输出结构（${'questions 里每一项必须是对象'}）：${SHAPE}`,
].join('\n');
const TRIAGE_OUT = '输出 {"needs_search":boolean,"search_query":string,"draft":<上面的结构>}';
const COMPOSE_OUT = '只能引用给出的证据 id；按上面的结构输出完整契约，不要改变结构。可用证据里与用户下一步真正相关的，应做成 resources（最多 3 条）；确实没有相关的才留空';

/* ── Outcome Loop：全页唯一主行动 ───────────────────────────
   模型给了 next_action 就规整（截断、模式白名单），没给就从护栏处理后的
   recommended_path.first_action / safe_next_action 推导——护栏撤回路径或中性化
   动作之后，主行动自动跟随护栏结论，不会出现"路径被撤了主行动还在"的矛盾。
   handoff 必须带完整任务书：说了要交棒却给不出任务书，就降级为在这里完成的分析。 */
function ensureNextAction(out) {
  const n = (out.next_action && typeof out.next_action === 'object' && !Array.isArray(out.next_action)) ? out.next_action : {};
  const text = String(n.text || '').trim()
    || String((out.recommended_path && out.recommended_path.first_action) || '').trim()
    || String(out.safe_next_action || '').trim();
  if (!text) { out.next_action = null; return out; }
  const task = String(n.handoff_task || '').trim();
  let mode = ['internal', 'handoff', 'human'].includes(n.mode) ? n.mode : '';
  if (task && mode !== 'handoff') mode = 'handoff';       // 有任务书就是交棒（模式填错的强信号）
  if (mode === 'handoff' && !task) mode = 'internal';     // 空手交棒不成立
  out.next_action = {
    text: text.slice(0, 500),
    done_when: String(n.done_when || '').trim().slice(0, 300),
    mode,
    handoff_task: mode === 'handoff' ? task.slice(0, 2000) : '',
    handoff_target: mode === 'handoff' ? String(n.handoff_target || '').trim().slice(0, 60) : '',
  };
  return out;
}

/* ── HTTP：同源静态页 + 收费 API 的来源边界 ────────────────── */
function isLocalOrigin(o) { return /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(o); }
function corsFor(req) {
  const o = req.headers.origin || '';
  const allowed = !o || isLocalOrigin(o) || CFG.allowedOrigins.includes(o);
  const headers = allowed && o ? {
    'access-control-allow-origin': o, 'access-control-allow-headers': 'content-type',
    'access-control-allow-methods': 'POST, OPTIONS, GET', vary: 'Origin',
  } : {};
  return { allowed, headers };
}
/* 反向代理边界：限流的"客户端 IP"从哪来。
   默认（未开信任）：只认 socket 对端地址，客户端发来的 X-Forwarded-For 一律不看——
   否则任何访问者换个假头就能绕开限流。
   显式 WS_TRUST_PROXY=1 且对端在受信代理名单里（默认 127.0.0.1/::1，即 Nginx 反代本机）：
   取 X-Forwarded-For 最右一个合法 IP——受信代理把"它看见的地址"追加在最右，客户端
   伪造的头会被代理追加的真实地址顶掉。只支持单层受信代理。 */
function clientIp(req) {
  const peer = req.socket.remoteAddress || '?';
  if (CFG.trustProxy && CFG.trustedProxies.includes(peer)) {
    const parts = String(req.headers['x-forwarded-for'] || '').split(',').map(x => x.trim());
    for (let i = parts.length - 1; i >= 0; i--) if (isIP(parts[i])) return parts[i];
  }
  return peer;
}
/* 极薄滥用防护：每 IP 每分钟计数（内存，非预算账本；预算账本永远走文件 fail closed） */
const hits = new Map();
function rateLimited(req) {
  const ip = clientIp(req);
  const now = Date.now();
  if (hits.size > 10000) hits.clear();
  const h = hits.get(ip);
  if (!h || now - h.t0 > 60000) { hits.set(ip, { t0: now, n: 1 }); return false; }
  h.n += 1;
  return h.n > CFG.rateLimitPerMin;
}
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
function serveStatic(req, res, corsH) {
  let p = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  if (p === '/login') p = '/login.html'; // 干净路径给用户，磁盘上带扩展名
  const file = join(CFG.webDir, normalize(p).replace(/^([.][.][/\\])+/, ''));
  if (!file.startsWith(CFG.webDir)) return false;
  let data;
  try { data = readFileSync(file); } catch (e) { return false; }
  /* HTML 页面 no-store：退出/换账号后浏览器后退不能显示上一个人的内容 */
  const cc = extname(file) === '.html' ? 'no-store' : 'no-cache';
  res.writeHead(200, Object.assign({ 'content-type': MIME[extname(file)] || 'application/octet-stream', 'cache-control': cc }, corsH));
  res.end(req.method === 'HEAD' ? undefined : data);
  return true;
}
function json(res, code, body, corsH = {}) {
  res.writeHead(code, Object.assign({ 'content-type': 'application/json; charset=utf-8' }, corsH));
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
  const { allowed, headers: corsH } = corsFor(req);
  if (req.method === 'OPTIONS') {
    if (!allowed) { res.writeHead(403); return res.end(); }
    res.writeHead(204, corsH);
    return res.end();
  }
  if (req.url === '/healthz') {
    const b = loadBudget();
    const a = AUTH.status();
    return json(res, 200, {
      ok: true, provider: CFG.provider, search: CFG.search, model: CFG.llmModel || 'stub',
      // 只报告"配没配"，绝不回显 key
      search_configured: CFG.search === 'fixture' ? true : (CFG.search !== 'none' && !!CFG.searchKey),
      origins_configured: CFG.allowedOrigins.length > 0, rate_limit_per_min: CFG.rateLimitPerMin,
      liveness: CFG.liveness, trusted_proxy: CFG.trustProxy,
      auth: a.enabled ? (a.ready ? 'ready' : `broken:${a.reason}`) : 'off',
      budget_mode: b.mode, today_calls: b.state ? b.state.calls : null,
      month_cost_rmb: b.state ? b.state.cost : null,
      daily_cap: CFG.dailyCap, monthly_cap_rmb: CFG.monthlyCapRmb, fail_closed: CFG.failClosed,
    }, corsH);
  }
  /* 认证是明码标价的门，不是暗桩：X-Forwarded-Proto 只在对面是受信代理时才看 */
  const protoHttps = CFG.trustProxy && CFG.trustedProxies.includes(req.socket.remoteAddress || '')
    && String(req.headers['x-forwarded-proto'] || '') === 'https';
  if (req.method === 'POST' && req.url === '/api/auth/login') return handleLogin(req, res, corsH, protoHttps);
  if (req.method === 'GET' && req.url === '/api/auth/me') return handleMe(req, res, corsH);
  if (req.method === 'POST' && req.url === '/api/auth/logout') return handleLogout(req, res, corsH);
  if (req.method === 'POST' && req.url === '/api/world') {
    if (!allowed) return json(res, 403, { error: 'origin_not_allowed' });
    if (rateLimited(req)) return json(res, 429, {
      error: 'rate_limited', fallback_if_refused: '这一分钟请求太密了。等一分钟再试；期间可以先把要做的事写下来。',
    }, corsH);
    /* FAIL CLOSED：配置坏了 → 503 明确不可用（绝不放行）；没登录 → 401 */
    const sess = sessionState(req);
    if (sess.mode === 'broken') return json(res, 503, {
      error: 'auth_unavailable', reason: sess.reason,
      fallback_if_refused: '认证配置损坏时服务不开放。请运维检查用户文件与 session 密钥后重试；期间请走手工路径完成这件事。',
    }, corsH);
    if (sess.mode === 'out') return json(res, 401, { error: 'auth_required' }, corsH);
    return handleWorld(req, res, corsH, t0);
  }
  if (req.method === 'GET' || req.method === 'HEAD') {
    const p = req.url === '/' ? '/' : req.url.split('?')[0];
    const sess = sessionState(req);
    if (p === '/' || p === '/index.html') {
      /* 产品首页是受保护页面：没登录/门坏了都去登录页，登录页会如实说明状态 */
      if (sess.mode === 'out' || sess.mode === 'broken') return redirect(res, '/login');
    } else if (p === '/login' || p === '/login.html') {
      if (sess.mode === 'in' || sess.mode === 'off') return redirect(res, '/');
    }
    if (serveStatic(req, res, corsH)) return;
  }
  return json(res, 404, { error: 'only POST /api/world exists' });
});

/* ── 访问门的三个动作：进（login）、看（me）、出（logout）────────── */
function sessionState(req) {
  const st = AUTH.status();
  if (!st.enabled) return { mode: 'off' };
  if (!st.ready) return { mode: 'broken', reason: st.reason };
  const s = AUTH.sessionOf(sessionTokenFrom(req.headers.cookie, AUTH.cookieName));
  return s.ok ? { mode: 'in', uid: s.uid } : { mode: 'out' };
}
function redirect(res, loc) { res.writeHead(302, { location: loc, 'cache-control': 'no-store' }); res.end(); }

const LOGIN_FAIL_MSG = '账号或密码不正确。'; // 统一口径：不泄露账号是否存在
async function handleLogin(req, res, corsH, protoHttps) {
  const st = AUTH.status();
  if (!st.enabled) return json(res, 200, { ok: true, auth: 'off' }, corsH);
  if (!st.ready) return json(res, 503, { error: 'auth_unavailable', reason: st.reason, message: '服务没有配置好，暂时无法登录。' }, corsH);
  let body;
  try { body = await readBody(req); } catch (e) { return json(res, 400, { error: 'bad_request' }, corsH); }
  const username = typeof body.username === 'string' ? body.username.trim() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  if (!username || !password || username.length > 64 || password.length > 200) return json(res, 400, { error: 'bad_request' }, corsH);
  const ip = clientIp(req);
  const g = AUTH.loginGuard(ip);
  if (g.locked) {
    res.setHeader('retry-after', String(g.retryAfterSec));
    console.log(`${new Date().toISOString()} auth login locked ip=${ip}`);
    return json(res, 429, { error: 'login_rate_limited', message: '尝试次数太多，请等几分钟再试。' }, corsH);
  }
  const r = AUTH.login(username, password);
  if (!r.ok) {
    AUTH.loginFail(ip);
    // 只记事件与来源：用户名、密码、hash 永远不进日志
    console.log(`${new Date().toISOString()} auth login fail ip=${ip}`);
    return json(res, 401, { error: 'bad_credentials', message: LOGIN_FAIL_MSG }, corsH);
  }
  AUTH.loginPass(ip);
  res.setHeader('set-cookie', AUTH.cookieFor(r.token, protoHttps));
  console.log(`${new Date().toISOString()} auth login ok ip=${ip}`);
  return json(res, 200, { ok: true }, corsH);
}
function handleMe(req, res, corsH) {
  const st = AUTH.status();
  if (!st.enabled) return json(res, 200, { auth: 'off', user_id: 'local' }, corsH);
  if (!st.ready) return json(res, 503, { error: 'auth_unavailable', reason: st.reason }, corsH);
  const s = AUTH.sessionOf(sessionTokenFrom(req.headers.cookie, AUTH.cookieName));
  if (!s.ok) return json(res, 401, { error: 'auth_required' }, corsH);
  return json(res, 200, { user_id: s.uid }, corsH);
}
function handleLogout(req, res, corsH) {
  const st = AUTH.status();
  if (st.enabled && st.ready) {
    const s = AUTH.sessionOf(sessionTokenFrom(req.headers.cookie, AUTH.cookieName));
    if (s.ok) AUTH.revoke(s); // 服务端吊销：旧 cookie 重放也进不来
  }
  res.setHeader('set-cookie', AUTH.clearCookie());
  return json(res, 200, { ok: true }, corsH);
}

async function handleWorld(req, res, corsH, t0) {
  // 每个请求一份计数器；并发请求互不可见（并发回归自测盯住这一点）
  const usage = { llm_calls: 0, search_calls: 0, request_cost_rmb: 0, llm_retries: 0 };
  const b = loadBudget();
  if (!b.state) return json(res, 503, {
    error: 'budget_guard_unavailable', reason: b.error,
    fallback_if_refused: '预算护栏读不到状态时不产生付费调用。稍后再试，或走手工路径：把意图改写成 3 个搜索词自己去官方站点核对。',
  }, corsH);
  const s = b.state;
  const cap = overCap(s);
  if (cap) return json(res, 429, {
    error: 'budget_exceeded', limit: cap, daily_cap: CFG.dailyCap, month_cost_rmb: s.cost,
    fallback_if_refused: '今天额度用完：把这件事改写成几个关键词，优先查对应的官方机构、实际服务提供方或真实平台；仍无法判断时，再找这个领域的人工客服、专业人员或现实中的人确认。',
  }, corsH);

  let body;
  try { body = await readBody(req); } catch (e) { return json(res, 400, { error: e.message }, corsH); }
  const intent = String(body.intent || '').trim();
  if (intent.length < 2) return json(res, 400, { error: 'intent_too_short' }, corsH);
  if (intent.length > 500) return json(res, 400, { error: 'intent_too_long' }, corsH);
  /* Outcome Loop 的回执：用户带着现实结果回来（做成了/卡住了 + 可选粘贴的原文）。
     只做形状校验和截断，内容原样进模型上下文——这是"世界返回了什么"的入口，不是装饰。 */
  let receipt = null;
  if (body.receipt && typeof body.receipt === 'object' && !Array.isArray(body.receipt)) {
    const st = ['done', 'stuck', 'info'].includes(body.receipt.status) ? body.receipt.status : 'info';
    const txt = String(body.receipt.text || '').trim().slice(0, 2000);
    if (st !== 'info' || txt) receipt = { status: st, text: txt };
  }
  const ctx = JSON.stringify({ intent, answers: Array.isArray(body.answers) ? body.answers.slice(0, 4) : [], receipt, today: localDate() });

  let out;
  const sMeta = {};
  try {
    const tri = await llmJson(s, usage, `${SYSTEM}\nSTAGE: triage\n${TRIAGE_OUT}`, `输入：${ctx}`);
    out = tri.draft || tri;
    let ev = evidenceTable([]);
    const q = minimizeQuery(tri.search_query || '');
    sMeta.search_query_used = q;
    if (tri.needs_search && q) {
      const sr = await runSearch(s, usage, q);
      ev = evidenceTable(sr.items);
      sMeta.search_skipped_reason = sr.skipped || '';
      sMeta.evidence_fixture = sr.note || '';
      if (sr.liveness_dropped) sMeta.evidence_dead_links_dropped = sr.liveness_dropped;
      if (ev.size()) {
        const composed = await llmJson(s, usage, `${SYSTEM}\nSTAGE: compose\n${COMPOSE_OUT}`,
          `输入：${ctx}\n可用证据（只能按 id 引用）：${JSON.stringify(ev.forPrompt())}\n待修订草稿：${JSON.stringify(out)}`);
        out = composed.draft || composed;
      } else {
        out.uncertainties = (out.uncertainties || []).concat(['本轮需要查现实信息，但没有拿到任何可用搜索结果']);
      }
    } else {
      sMeta.search_skipped_reason = tri.needs_search ? 'empty_query' : 'not_needed';
    }
    out = guard(out, ev);
    out = ensureNextAction(out);
    out.meta = Object.assign({}, out.meta, sMeta, {
      searched: ev.size() > 0, evidence_available: ev.size(),
      llm_calls: usage.llm_calls, search_calls: usage.search_calls, llm_retry_count: usage.llm_retries,
      request_cost_rmb: usage.request_cost_rmb, month_cost_rmb: s.cost,
      budget_mode: b.mode, model: CFG.llmModel || 'stub',
      receipt_ingested: !!receipt, receipt_status: receipt ? receipt.status : '',
    });
    const errs = validate(SCHEMA, out);
    if (errs.length) return json(res, 502, {
      error: 'intelligence_contract_failure', violations: errs.slice(0, 12),
      fallback_if_refused: '智能层这轮没按契约交付，不要拿它的结果去行动。', partial: out,
    }, corsH);
    json(res, 200, out, corsH);
  } catch (e) {
    const code = String(e.message || e);
    if (e.limit) {
      return json(res, 429, {
        error: 'budget_exceeded', limit: e.limit, daily_cap: CFG.dailyCap, month_cost_rmb: s.cost,
        fallback_if_refused: '今天额度用完：把这件事改写成几个关键词，优先查对应的官方机构、实际服务提供方或真实平台；仍无法判断时，再找这个领域的人工客服、专业人员或现实中的人确认。',
      }, corsH);
    }
    if (code.indexOf('budget_guard_unavailable') === 0) {
      return json(res, 503, { error: 'budget_guard_unavailable', fallback_if_refused: '预算状态写不进去就不继续产生付费调用；请走手工路径或稍后再试。' }, corsH);
    }
    json(res, 502, { error: 'intelligence_unavailable', code: code.slice(0, 60) }, corsH);
  } finally {
    console.log(`${new Date().toISOString()} ${req.method} ${res.statusCode} ${Date.now() - t0}ms llm=${usage.llm_calls} search=${usage.search_calls} retry=${usage.llm_retries} req_cost=${usage.request_cost_rmb} month=${s.cost} calls=${s.calls}`);
  }
}
server.listen(CFG.port, CFG.host, () => {
  const a = AUTH.status();
  const authState = a.enabled ? (a.ready ? 'ready' : `FAIL_CLOSED(${a.reason})`) : 'OFF(公开访问，只用于本地离线开发)';
  console.log(`world api http://${CFG.host}:${CFG.port} provider=${CFG.provider} search=${CFG.search} caps=${CFG.dailyCap}/day ${CFG.monthlyCapRmb}RMB/month fail_closed=${CFG.failClosed} origins=${CFG.allowedOrigins.length ? 'configured' : 'local-only'} rate=${CFG.rateLimitPerMin}/min liveness=${CFG.liveness} trusted_proxy=${CFG.trustProxy ? 'on(' + CFG.trustedProxies.join('|') + ')' : 'off'} auth=${authState}`);
});
