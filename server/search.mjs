/*
 * Search provider 适配层。
 * 职责只有一个：query → 内部证据格式 [{title,url,snippet,published_at}]。
 * provider 自己的响应结构绝不外泄到上层，上层也永远拿不到 key。
 * 注意：搜索只负责"找东西"；这条结果算不算官方来源，由 server/evidence.mjs 判级决定。
 *
 * 钥匙可以配多把（Founder 要求：一把不行就自动换另一把）。换的判断条件刻意收得很窄：
 *   只有"这把钥匙本身不行"才换 —— 401/403 无效或已被撤销、429 配额耗尽；
 *   网络断开、超时、provider 5xx **不换钥匙直接抛**，因为换一把也一样失败，
 *   换了反而会把真正的故障（断网、服务挂了）伪装成"我们已经自愈了"。
 */
const TIMEOUT = Number(process.env.WS_TIMEOUT_MS || 20000);

/** 钥匙候选：支持 WS_SEARCH_KEY 逗号分隔多把，也支持 WS_SEARCH_KEY_2 这种更好写的配法。
 *  顺序即优先级；去重，避免同一把被连试两次浪费一次配额。 */
export function searchKeys(cfg) {
  const out = [];
  for (const raw of [cfg.searchKey, cfg.searchKey2]) {
    if (!raw) continue;
    for (const piece of String(raw).split(',')) {
      const k = piece.trim();
      if (k && !out.includes(k)) out.push(k);
    }
  }
  return out;
}

/* 换钥匙的触发条件：钥匙级别被拒（无效/撤销/配额）。其余错误不换。 */
const KEY_REJECTED = new Set([401, 403, 429]);

async function tryOneKey(url, key, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(TIMEOUT),
  });
  if (!res.ok) {
    // 错误里只带状态码，绝不带 key
    const err = new Error(`search_http_${res.status}`);
    err.status = res.status;
    err.keyRejected = KEY_REJECTED.has(res.status);
    throw err;
  }
  return res.json();
}

/** 依次试每一把钥匙；只有上一把是"钥匙级被拒"才继续，否则立刻抛出真实故障。 */
async function post(url, cfg, body) {
  const keys = searchKeys(cfg);
  if (!keys.length) throw new Error('search_no_key');
  let lastErr = null;
  for (let i = 0; i < keys.length; i++) {
    try {
      const json = await tryOneKey(url, keys[i], body);
      if (i > 0) console.log(`search fallback ok provider=${cfg.search || '?'} used_key=${i + 1}/${keys.length}`);
      return json;
    } catch (e) {
      lastErr = e;
      const rejectable = Boolean(e && e.keyRejected);
      if (rejectable && i < keys.length - 1) {
        console.log(`search key ${i + 1}/${keys.length} rejected(${e.message}) → 换下一把`);
        continue;
      }
      throw e;
    }
  }
  throw lastErr || new Error('search_no_key');
}

/** Tavily：只取 results（标题/链接/摘要/发布时间），明确不要它的 answer 生成能力。
 *  认证只走 Authorization: Bearer，key 不进请求体；body 里只有搜索参数。 */
export async function tavily(cfg, query) {
  const j = await post(
    cfg.searchUrl || 'https://api.tavily.com/search', cfg,
    { query, max_results: 8, search_depth: 'basic', include_answer: false, include_raw_content: false },
  );
  return (j.results || []).map(x => ({
    title: x.title || '', url: x.url || '', snippet: x.content || '', published_at: x.published_date || '',
  }));
}

/** 博查 */
export async function bocha(cfg, query) {
  const j = await post('https://api.bochaai.com/v1/web-search', cfg, { query, summary: true, count: 8 });
  const lst = (((j.data || {}).webPages || {}).value) || [];
  return lst.map(x => ({ title: x.name || '', url: x.url || '', snippet: x.summary || x.snippet || '', published_at: x.datePublished || '' }));
}

/** 阿里云联网搜索 */
export async function aliyun(cfg, query) {
  const j = await post(cfg.searchUrl || 'https://maasaisearchproxy.aliyuncs.com/api/web-search', cfg, { query, limit: 8 });
  const lst = (j.pageItems || j.items || []);
  return lst.map(x => ({ title: x.title || '', url: x.url || '', snippet: x.snippet || x.content || '', published_at: x.publishedTime || '' }));
}

/** provider 注册表：上层只按名字取，拿到的都是同一种内部格式 */
export const PROVIDERS = { tavily, bocha, aliyun };
export const KNOWN = Object.keys(PROVIDERS);
