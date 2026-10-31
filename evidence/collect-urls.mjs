// Real-URL evidence collector (no button poking). Usage: node evidence/collect-urls.mjs > evidence/urls.json
import fs from 'node:fs';

const catalog = JSON.parse(fs.readFileSync('catalog/resources.json', 'utf8'));
const urls = new Map();
for (const r of catalog.resources) {
  for (const u of [r.official_url, ...(r.source_urls || [])]) if (u) urls.set(u, r.id);
}
// Non-catalog destinations the pages send people to (must be checked too)
const extra = [
  'https://www.doubao.com/chat/create-image',
  'https://support.apple.com/zh-cn/104964',
  'https://support.apple.com/zh-cn/guide/iphone/iphcb2a4b2b/ios',
  'https://www.doubao.com/chat/',
  'https://kimi.moonshot.cn',
  'https://chat.qwen.ai',
  'https://tongyi.aliyun.com',
  'https://www.canva.cn',
  'https://www.stirling.com',
  'https://apps.apple.com/cn/app/id1467852587',
  'https://apps.apple.com/cn/app/id1500526240'
];
for (const u of extra) if (!urls.has(u)) urls.set(u, 'extra');

const out = [];
for (const [url, rid] of urls) {
  const started = Date.now();
  const rec = { url, resource: rid, checked_at: new Date().toISOString() };
  try {
    const res = await fetch(url, {
      redirect: 'follow',
      signal: AbortSignal.timeout(25000),
      headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36', 'accept-language': 'zh-CN,zh;q=0.9' }
    });
    rec.status = res.status;
    rec.final_url = res.url;
    rec.ms = Date.now() - started;
    const text = await res.text();
    rec.bytes = Buffer.byteLength(text);
    rec.title = (text.match(/<title[^>]*>([\s\S]{0,200}?)<\/title>/i) || [, ''])[1].replace(/\s+/g, ' ').trim();
  } catch (e) {
    rec.error = e.name + ': ' + e.message;
    rec.ms = Date.now() - started;
  }
  out.push(rec);
  console.log(`${rec.status ?? rec.error}\t${rec.ms}ms\t${url}\t${rec.final_url ?? ''}`);
}
fs.writeFileSync('evidence/urls.json', JSON.stringify({ collected_at: new Date().toISOString(), results: out }, null, 2));
