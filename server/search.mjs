/*
 * Search provider 适配层。
 * 职责只有一个：query → 内部证据格式 [{title,url,snippet,published_at}]。
 * provider 自己的响应结构绝不外泄到上层，上层也永远拿不到 key。
 * 注意：搜索只负责"找东西"；这条结果算不算官方来源，由 server/evidence.mjs 判级决定。
 */
const TIMEOUT = Number(process.env.WS_TIMEOUT_MS || 20000);

async function post(url, headers, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: Object.assign({ 'content-type': 'application/json' }, headers),
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(TIMEOUT),
  });
  if (!res.ok) throw new Error(`search_http_${res.status}`); // 错误里只带状态码，不带 key
  return res.json();
}

/** Tavily：只取 results（标题/链接/摘要/发布时间），明确不要它的 answer 生成能力 */
export async function tavily(cfg, query) {
  const j = await post(
    cfg.searchUrl || 'https://api.tavily.com/search',
    { authorization: `Bearer ${cfg.searchKey}` },
    { api_key: cfg.searchKey, query, max_results: 8, search_depth: 'basic', include_answer: false, include_raw_content: false },
  );
  return (j.results || []).map(x => ({
    title: x.title || '', url: x.url || '', snippet: x.content || '', published_at: x.published_date || '',
  }));
}

/** 博查 */
export async function bocha(cfg, query) {
  const j = await post('https://api.bochaai.com/v1/web-search', { authorization: `Bearer ${cfg.searchKey}` },
    { query, summary: true, count: 8 });
  const lst = (((j.data || {}).webPages || {}).value) || [];
  return lst.map(x => ({ title: x.name || '', url: x.url || '', snippet: x.summary || x.snippet || '', published_at: x.datePublished || '' }));
}

/** 阿里云联网搜索 */
export async function aliyun(cfg, query) {
  const j = await post(cfg.searchUrl || 'https://maasaisearchproxy.aliyuncs.com/api/web-search',
    { authorization: `Bearer ${cfg.searchKey}` }, { query, limit: 8 });
  const lst = (j.pageItems || j.items || []);
  return lst.map(x => ({ title: x.title || '', url: x.url || '', snippet: x.snippet || x.content || '', published_at: x.publishedTime || '' }));
}

/** provider 注册表：上层只按名字取，拿到的都是同一种内部格式 */
export const PROVIDERS = { tavily, bocha, aliyun };
export const KNOWN = Object.keys(PROVIDERS);
