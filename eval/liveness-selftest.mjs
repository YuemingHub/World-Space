/*
 * F3 链接存活检查自测 —— 本地 mock 服务器，0 外网请求。
 * 404/410 → 剔除；200 → 保留；超时/非 URL → 保守保留（宁可漏放，不误删）。
 */
import http from 'node:http';
import { filterLive } from '../server/evidence.mjs';

const srv = http.createServer((req, res) => {
  if (req.url === '/gone') { res.writeHead(404); return res.end(); }
  if (req.url === '/removed') { res.writeHead(410); return res.end(); }
  if (req.url === '/slow') { setTimeout(() => { res.writeHead(200); res.end(); }, 1200); return; }
  res.writeHead(200); res.end();
});
await new Promise(r => srv.listen(8899, '127.0.0.1', r));

const out = await filterLive([
  { title: '活页', url: 'http://127.0.0.1:8899/ok' },
  { title: '已删页', url: 'http://127.0.0.1:8899/gone' },
  { title: '已迁移', url: 'http://127.0.0.1:8899/removed' },
  { title: '慢站', url: 'http://127.0.0.1:8899/slow' },
  { title: '非URL', url: 'not a url' },
], { max: 6, timeoutMs: 300 });

let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };
ok('404/410 剔除 2 条', out.dropped === 2, JSON.stringify(out));
ok('保留 3 条', out.items.length === 3 && out.items.some(x => x.title === '活页') && out.items.some(x => x.title === '慢站') && out.items.some(x => x.title === '非URL'), JSON.stringify(out.items.map(x => x.title)));
ok('检查数如实（4 条有 URL）', out.checked === 4);

srv.close();
console.log(failures ? `失败 ${failures} 项` : '链接存活检查全部通过');
process.exitCode = failures ? 1 : 0;
