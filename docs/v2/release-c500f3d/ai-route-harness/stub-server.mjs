// Stub of the production Node entry (world.mjs) for nginx route-isolation testing.
// It does not implement the app; it reproduces only the statuses the deploy plan's
// A1-A6 baseline asserts, so nginx behaviour is what is being measured.
import http from 'node:http';

const PUB = Number(process.env.STUB_PORT || 3200);

http.createServer((req, res) => {
  const p = (req.url || '').split('?')[0];
  const method = req.method || 'GET';
  const send = (code, body, type = 'application/json', extra = {}) => {
    res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store', ...extra });
    res.end(body);
  };
  if (p === '/') {
    res.writeHead(302, { location: '/login', 'cache-control': 'no-store' });
    return res.end();
  }
  if (p === '/login' && method === 'GET') {
    return send(200, '<html><body>进入你的空间 · 登录</body></html>', 'text/html; charset=utf-8');
  }
  if (p === '/healthz') return send(200, '{"ok":true}');
  if (p === '/api/world' && method === 'POST') {
    req.resume();
    return send(401, '{"error":"auth_required"}');
  }
  if (p === '/api/auth/me') return send(401, '{"error":"auth_required"}');
  return send(404, '{"error":"not_found"}');
}).listen(PUB, '0.0.0.0', () => console.log('STUB_READY ' + PUB));
