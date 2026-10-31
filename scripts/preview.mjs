#!/usr/bin/env node
/*
 * World Space · 静态站点本地预览服务（零依赖，只为「让它跑起来」）
 *
 * 它不改变产品形态：站点仍是纯静态文件；这个脚本只是把目录按两层静态根同时暴露，
 * 便于验证「无论部署根是 /web/ 还是 /ai/，站内相对链接都成立」。
 *
 * 用法：
 *   node scripts/preview.mjs                 # 默认端口 4173
 *   PORT=8080 node scripts/preview.mjs
 *
 * 打开的地址：
 *   http://127.0.0.1:4173/ai/                  ← 类似 ymai.fun 静态根 = web/
 *   http://127.0.0.1:4173/web/ai/              ← 类似 ymai.fun 静态根 = 仓库根
 *   http://127.0.0.1:4173/                     ← 旧站根入口（index.html → web/index.html）
 */
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { join, extname, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT || 4173);
const HOST = process.env.HOST || '127.0.0.1';

const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.md': 'text/markdown; charset=utf-8'
};

// 两层静态根：真实文件在 ROOT 下；额外把 /ai/* 映射到 ROOT/web/ai/*，模拟「静态根=web/」的部署
async function resolvePath(urlPath) {
  const p = decodeURIComponent(urlPath.split('?')[0]);
  const candidates = [join(ROOT, p)];
  if (p.startsWith('/ai/') || p === '/ai') candidates.push(join(ROOT, 'web', p));
  for (const c of candidates) {
    let file = c;
    try {
      const s = await stat(file);
      if (s.isDirectory()) file = join(file, 'index.html');
      await stat(file);
      if (!resolve(file).startsWith(ROOT)) continue;
      return file;
    } catch { /* 试下一个候选 */ }
  }
  return null;
}

const server = createServer(async (req, res) => {
  const file = await resolvePath(req.url || '/');
  if (!file) {
    res.writeHead(404, { 'content-type': 'text/html; charset=utf-8' });
    res.end(`<meta charset="utf-8"><h1>404 · 这里没有页面</h1><p><a href="/ai/">去 AI 从零开始</a> · <a href="/">回 World Space</a></p>`);
    return;
  }
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': MIME[extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' });
    res.end(body);
  } catch {
    res.writeHead(500); res.end('500');
  }
});

server.listen(PORT, HOST, () => {
  console.log(`World Space 预览已启动（纯静态，零依赖）`);
  console.log(`  AI 从零开始（静态根=web/）:  http://${HOST}:${PORT}/ai/`);
  console.log(`  AI 从零开始（静态根=仓库根）: http://${HOST}:${PORT}/web/ai/`);
  console.log(`  现有主站入口:                http://${HOST}:${PORT}/`);
  console.log(`  停止：Ctrl+C`);
});
