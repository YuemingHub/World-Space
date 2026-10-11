/*
 * 公开入口回归自测 —— 未登录访客在 / 上看到什么（Issue #82 候选行为）：
 *   未登录 GET / 与 /public/index.html 给七行动入口门面页（真源 main 线，部署载体副本）；
 *   门面文件缺失时回落旧行为 302 /login（删文件即回滚，运行中即时生效）；
 *   已登录 / 仍是 v2 应用页、/login 302 回应用；broken 仍去登录页（绝不假装服务正常）；
 *   off 模式行为不变；healthz／静态资源／API 门／目录穿越防护全部无回归。
 * 测试用户/密钥都是本测试生成的 fixture，放在 var/（gitignored），不进仓库。
 */
import { spawn } from 'node:child_process';
import { rmSync, writeFileSync, renameSync, readFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { createAuth, hashPassword } from '../server/auth.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const VAR = join(ROOT, 'var');
let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };

const FACADE_TITLE = 'World Space — 你想做什么事？';   // main 线门面页判别串
const APP_TITLE = 'World Space · 你现在想做成什么';    // v2 应用页判别串（登录后首页）
const PW_A = 'frontdoor-check-2026';
mkdirSync(VAR, { recursive: true });
const usersFile = join(VAR, 'frontdoor-users.json');
const secretFile = join(VAR, 'frontdoor-secret.txt');
writeFileSync(secretFile, randomBytes(48).toString('base64') + '\n');
writeFileSync(usersFile, JSON.stringify({ users: [{ user_id: 'u-fd', username: 'frontdoor', password_hash: hashPassword(PW_A) }] }));

function start(port, extra) {
  rmSync(join(VAR, `frontdoor-${port}.json`), { force: true });
  const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      WS_PROVIDER: 'stub', WS_STUB_CASE: 'ok', WS_SEARCH: 'fixture', WS_LIVENESS: '0',
      WS_PORT: String(port), WS_HOST: '127.0.0.1', WS_STATE_FILE: join(VAR, `frontdoor-${port}.json`),
      WS_OPS_PORT: String(port + 400), WS_DAILY_CAP: '500',
      WS_AUTH_USERS_FILE: usersFile, WS_SESSION_SECRET_FILE: secretFile, WS_RATE_LIMIT: '1000',
    }, extra),
    stdio: 'ignore',
  });
  return child;
}
async function up(port) {
  for (let i = 0; i < 40; i++) {
    try { if ((await fetch(`http://127.0.0.1:${port}/healthz`)).ok) return; } catch (e) { }
    await new Promise(r => setTimeout(r, 150));
  }
  throw new Error(`world:${port} 没起来`);
}
const kill = c => { try { c.kill('SIGKILL'); } catch (e) { } };
const B = port => `http://127.0.0.1:${port}`;
const get = (port, path, cookie) => fetch(B(port) + path, { redirect: 'manual', headers: cookie ? { cookie } : {} });
const cookieOf = res => res.headers.get('set-cookie') || '';

/* ── 实例 A（8991）：配置齐全 + 门面在位 ── */
{
  const c = start(8991, {});
  try {
    await up(8991);
    const root = await get(8991, '/');
    const rootText = await root.text();
    ok('未登录 GET / → 200 门面页（不再 302 /login）', root.status === 200 && rootText.includes(FACADE_TITLE), `${root.status} ${rootText.slice(0, 80)}`);
    ok('门面页带七行动深链能力（JS hash 路由在文件里）', rootText.includes('#write #web #find #organize #photo #poster #ocr'), '');
    ok('门面页 content-type 是 HTML', (root.headers.get('content-type') || '').includes('text/html'), root.headers.get('content-type'));
    const direct = await get(8991, '/public/index.html');
    ok('未登录 GET /public/index.html → 200 同一门面', direct.status === 200 && (await direct.text()).includes(FACADE_TITLE), `${direct.status}`);
    const idx = await get(8991, '/index.html');
    ok('未登录 GET /index.html → 200 门面（与 / 同分支）', idx.status === 200 && (await idx.text()).includes(FACADE_TITLE), `${idx.status}`);

    const loginRes = await loginA(8991);
    const cookie = cookieOf(loginRes);
    ok('登录成功拿到 session（登录门没被本改动破坏）', loginRes.status === 200 && cookie.includes('='), `${loginRes.status}`);
    const appRoot = await get(8991, '/', cookie);
    const appText = await appRoot.text();
    ok('已登录 GET / → 200 v2 应用页（不是门面，登录态无回归）', appRoot.status === 200 && appText.includes(APP_TITLE) && !appText.includes(FACADE_TITLE), `${appRoot.status} ${appText.slice(0, 80)}`);
    const loginRedirect = await get(8991, '/login', cookie);
    ok('已登录 GET /login → 302 /（原行为不变）', loginRedirect.status === 302 && loginRedirect.headers.get('location') === '/', `${loginRedirect.status}`);
    const anonLogin = await get(8991, '/login');
    ok('未登录 GET /login → 200 登录页（原行为不变）', anonLogin.status === 200, `${anonLogin.status}`);

    const hz = await (await fetch(B(8991) + '/healthz')).text();
    ok('GET /healthz → {"ok":true}（公开健康探针无回归）', hz === '{"ok":true}', hz);
    for (const asset of ['/style.css', '/app.js', '/login.js']) {
      const r = await get(8991, asset);
      ok(`静态资源 ${asset} → 200（无回归）`, r.status === 200, `${r.status}`);
    }
    const api = await world401(8991);
    ok('未登录 POST /api/world → 401（API 门不变）', api.status === 401, `${api.status}`);
    const trav = await get(8991, '/../server/auth.mjs');
    ok('目录穿越仍被拒绝（不是 200）', trav.status !== 200, `${trav.status}`);
    const head = await fetch(B(8991) + '/', { method: 'HEAD', redirect: 'manual' });
    ok('HEAD / → 200 空 body（探活场景）', head.status === 200 && (await head.text()) === '', `${head.status}`);
  } finally { kill(c); }
}
function loginA(port) {
  return fetch(B(port) + '/api/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: 'frontdoor', password: PW_A }) });
}
function world401(port) {
  return fetch(B(port) + '/api/world', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ intent: '回归：未登录应 401' }) });
}

/* ── 实例 B（8992）：门面文件缺失 → 回落旧行为（可逆性）── */
{
  const c = start(8992, {});
  try {
    await up(8992);
    const facade = join(ROOT, 'web', 'v2', 'public', 'index.html');
    const backup = facade + '.selftest-bak';
    renameSync(facade, backup);
    try {
      const r = await get(8992, '/');
      ok('门面文件缺失：GET / → 302 /login（回落旧行为，删文件即回滚）', r.status === 302 && r.headers.get('location') === '/login', `${r.status}`);
      const r2 = await get(8992, '/');
      ok('回落是持续行为不是首次抖动', r2.status === 302, `${r2.status}`);
    } finally { renameSync(backup, facade); }
    const restored = await get(8992, '/');
    ok('文件恢复后（运行中，无需重启）：GET / → 200 门面（readFileSync 每次读盘）', restored.status === 200 && (await restored.text()).includes(FACADE_TITLE), `${restored.status}`);
  } finally { kill(c); }
}

/* ── 实例 C（8993）：认证配置损坏（broken）→ 绝不 serve 门面（fail-closed 红线）── */
{
  const badUsers = join(VAR, 'frontdoor-bad-users.json');
  writeFileSync(badUsers, '{ this is not json');
  const c = start(8993, { WS_AUTH_USERS_FILE: badUsers });
  try {
    await up(8993);
    const r = await get(8993, '/');
    ok('broken：GET / → 302 /login（不假装服务正常，与访问门自测同口径）', r.status === 302 && r.headers.get('location') === '/login', `${r.status}`);
    const hz = await (await fetch(B(8993) + '/healthz')).text();
    ok('broken：/healthz 仍 {"ok":true}（存活信号与配置状态分离）', hz === '{"ok":true}', hz);
  } finally { kill(c); }
}

/* ── 实例 D（8994）：认证关闭（off）→ 原行为不变 ── */
{
  const c = start(8994, { WS_AUTH_ENABLED: '0' });
  try {
    await up(8994);
    const r = await get(8994, '/');
    const t = await r.text();
    ok('off：GET / → 200 v2 应用页（无认证部署模式行为不变）', r.status === 200 && t.includes(APP_TITLE), `${r.status} ${t.slice(0, 80)}`);
  } finally { kill(c); }
}

console.log(failures === 0 ? '\n结果：全部通过' : `\n结果：${failures} 项失败`);
process.exit(failures === 0 ? 0 : 1);
