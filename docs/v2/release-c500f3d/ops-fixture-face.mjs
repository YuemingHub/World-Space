#!/usr/bin/env node
// 双面 healthz 的假面 fixture —— 只服务于 ops-selftest.sh，不是产品代码，不接真实 provider。
//
// 它存在的理由：切流工具的判据从来没被人跑红过（没有测试），于是"它会误关一次正确部署"
// 这件事只能等到真上线时才被发现。有了可编排的假面，每一条判据都能当场判红一次给看。
//
// 环境变量：
//   PUB_PORT   公网面端口（必填）
//   OPS_PORT   诊断面端口，0 = 不监听（模拟新版 3201 没起来）
//   MODE       dual | legacy
//   APP_PORT   诊断面自报的 app_port（默认等于 PUB_PORT；改小写错即模拟串台）
//   PID        诊断面自报 pid
//   DROP       逗号分隔：从诊断面响应里删掉的字段（模拟字段不完整）
//   DETAIL     公网 /healthz/detail 的状态码（默认 404；给 200 即模拟细节外露）
//   API        未登录 POST /api/world 的状态码（默认 401）
//   ROOT       未登录 GET / 的行为：302（默认）| 200
//   LOGIN_MARK 登录页是否含「进入你的空间」（默认 1）
import http from 'node:http';

const E = process.env;
const pub = Number(E.PUB_PORT || 0);
const ops = Number(E.OPS_PORT || 0);
const mode = E.MODE || 'dual';
const drop = new Set((E.DROP || '').split(',').filter(Boolean));
const detail = Number(E.DETAIL || 404);
const apiCode = Number(E.API || 401);
const rootMode = E.ROOT || '302';
const loginMark = E.LOGIN_MARK === '0' ? 0 : 1;

const FIELDS = {
  ok: true, auth: 'ready', provider: 'openai_compatible', model: 'fixture-not-real',
  search: 'fixture', search_configured: true, search_keys: 2,
  today_calls: 0, daily_cap: 50, month_cost_rmb: 0.001, monthly_cap_rmb: 20,
  budget_mode: 'fixture', fail_closed: true, liveness: true,
  rate_limit_per_min: 20, origins_configured: true, trusted_proxy: 'off(0)',
};
const pick = (keys, extra = {}) => {
  const o = {};
  for (const k of keys) if (!drop.has(k)) o[k] = FIELDS[k];
  return { ...o, ...extra };
};
const pubBody = () => (mode === 'dual' ? { ok: true } : pick(Object.keys(FIELDS)));
const opsBody = () => pick(Object.keys(FIELDS), { app_port: Number(E.APP_PORT || pub), pid: Number(E.PID || 4242) });

const send = (res, code, obj, hdr = {}) => {
  res.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store', ...hdr });
  res.end(typeof obj === 'string' ? obj : JSON.stringify(obj));
};
function face(handler) {
  const s = http.createServer(handler);
  s.on('error', (e) => { console.log('FIXTURE_FAIL ' + (e.code || e.message)); process.exit(1); });
  return s;
}

face((req, res) => {
  const p = (req.url || '').split('?')[0];
  if (p === '/healthz') return send(res, 200, pubBody());
  if (p === '/healthz/detail') return send(res, detail, detail === 404 ? { error: 'not_found' } : pubBody());
  if (p === '/login' && req.method === 'GET') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    return res.end(loginMark ? '<html>进入你的空间 · 登录</html>' : '<html>空白页</html>');
  }
  if (p === '/') {
    if (rootMode === '200') return send(res, 200, '<html>门失效了</html>');
    res.writeHead(302, { location: '/login' });
    return res.end();
  }
  if (p === '/api/world' && req.method === 'POST') {
    req.resume();
    return send(res, apiCode, apiCode === 401 ? { error: 'auth_required' } : { intent: 'leaked' });
  }
  return send(res, 404, { error: 'not_found' });
}).listen(pub, '127.0.0.1', () => console.log('FIXTURE_READY pub=' + pub));

if (ops > 0) {
  face((req, res) => {
    const p = (req.url || '').split('?')[0];
    if (p === '/healthz') return send(res, 200, opsBody());
    return send(res, 404, { error: 'not_found' });
  }).listen(ops, '127.0.0.1', () => console.log('FIXTURE_READY ops=' + ops));
}
