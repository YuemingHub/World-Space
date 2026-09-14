/*
 * 访问门回归自测 —— 离线桩经真实 HTTP 管线，验证"谁能进入"：
 *   登录成功/失败口径统一、未登录 API 401、未登录页面去登录页、篡改/过期/登出后的 cookie 一律无效、
 *   认证配置缺失或损坏时 FAIL CLOSED（业务 503，绝不退化成公开访问）、登录暴力尝试锁定、
 *   cookie 只装身份不装密码、日志里没有密码/用户名/token。
 * 测试用户/密钥都是本测试生成的 fixture，放在 var/（gitignored），不进仓库。
 */
import { spawn } from 'node:child_process';
import { rmSync, writeFileSync, renameSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { createAuth, hashPassword } from '../server/auth.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const VAR = join(ROOT, 'var');
let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };

const PW_A = 'correct-horse-2026', PW_B = 'bob-secret-2026';
const usersFile = join(VAR, 'auth-users.json');
const secretFile = join(VAR, 'auth-secret.txt');
writeFileSync(secretFile, randomBytes(48).toString('base64') + '\n');
const writeUsers = list => writeFileSync(usersFile, JSON.stringify({ users: list }));
writeUsers([
  { user_id: 'u-a', username: 'alice', password_hash: hashPassword(PW_A) },
  { user_id: 'u-b', username: 'bob', password_hash: hashPassword(PW_B) },
]);

function start(port, extra, captureLogs) {
  const chunks = [];
  const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      WS_PROVIDER: 'stub', WS_STUB_CASE: 'ok', WS_SEARCH: 'fixture', WS_LIVENESS: '0',
      WS_PORT: String(port), WS_HOST: '127.0.0.1', WS_STATE_FILE: join(VAR, `auth-${port}.json`),
      WS_AUTH_USERS_FILE: usersFile, WS_SESSION_SECRET_FILE: secretFile, WS_RATE_LIMIT: '1000',
    }, extra),
    stdio: captureLogs ? ['ignore', 'pipe', 'pipe'] : 'ignore',
  });
  if (captureLogs) { child.stdout.on('data', d => chunks.push(d)); child.stderr.on('data', d => chunks.push(d)); }
  return { child, logs: () => chunks.join('') };
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
const login = (port, username, password) => fetch(B(port) + '/api/auth/login', {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username, password }),
});
const world = (port, cookie, body) => fetch(B(port) + '/api/world', {
  method: 'POST', headers: Object.assign({ 'content-type': 'application/json' }, cookie ? { cookie } : {}),
  body: JSON.stringify(body || { intent: '验证访问门：我想修好楼道的灯' }),
});
const cookieOf = res => res.headers.get('set-cookie') || '';

/* ── 实例 1（8951）：配置齐全的完整行为 ── */
const logs = start(8951, {}, true);
try {
  await up(8951);
  const hz = await (await fetch(B(8951) + '/healthz')).json();
  ok('healthz：auth=ready（不泄露任何 secret）', hz.auth === 'ready', JSON.stringify(hz));

  // 未登录：页面去登录页，API 一律 401，静态资源（纯代码）可达
  const root = await get(8951, '/');
  ok('未登录 GET / → 302 /login', root.status === 302 && root.headers.get('location') === '/login', `${root.status} ${root.headers.get('location')}`);
  const root2 = await get(8951, '/index.html');
  ok('未登录 GET /index.html → 302 /login（首页没有旁路）', root2.status === 302, String(root2.status));
  const lp = await get(8951, '/login');
  ok('登录页公开可达', lp.status === 200 && (await lp.text()).includes('账号'), String(lp.status));
  const css = await get(8951, '/style.css');
  ok('静态资源公开（只有代码，没有用户内容）', css.status === 200, String(css.status));
  const w0 = await world(8951);
  ok('未登录 POST /api/world → 401', w0.status === 401 && (await w0.json()).error === 'auth_required', String(w0.status));
  const me0 = await get(8951, '/api/auth/me');
  ok('未登录 me → 401', me0.status === 401, String(me0.status));

  // 错误口径统一：不存在账号与错误密码表现一致
  const bad1 = await login(8951, 'alice', 'wrong-password');
  const bad2 = await login(8951, 'no-such-user', 'wrong-password');
  const b1 = await bad1.json(), b2 = await bad2.json();
  ok('错误密码 → 401 统一口径', bad1.status === 401 && b1.message === '账号或密码不正确。', JSON.stringify(b1));
  ok('不存在账号与错误密码完全一致（不泄露账号存在性）', bad2.status === bad1.status && JSON.stringify(b1) === JSON.stringify(b2), JSON.stringify(b2));
  const shape = await login(8951, 'alice', '');
  ok('缺密码 → 400（参数错误，不当登录失败处理）', shape.status === 400, String(shape.status));

  // 正确登录：cookie 旗标与内容
  const good = await login(8951, 'alice', PW_A);
  const sc = cookieOf(good);
  const token = (sc.match(/ws_sess=([^;]+)/) || [])[1] || '';
  ok('正确账号 → 200 + session cookie', good.status === 200 && token.length > 20, cookieOf(good));
  ok('cookie 旗标：HttpOnly + SameSite=Lax + Path=/', /httponly/i.test(sc) && /samesite=lax/i.test(sc) && /path=\//i.test(sc), sc);
  let payload = {};
  try { payload = JSON.parse(Buffer.from(token.split('.')[0], 'base64url').toString('utf8')); } catch (e) { }
  ok('cookie 负载只有身份与时间（无密码/用户名/正文）', payload.uid === 'u-a' && payload.exp > Date.now()
    && !sc.includes('alice') && !sc.includes(PW_A) && !sc.includes('password'), JSON.stringify(payload));
  const me1 = await get(8951, '/api/auth/me', `ws_sess=${token}`);
  ok('已登录 me → user_id 来自服务端验证', me1.status === 200 && (await me1.json()).user_id === 'u-a', String(me1.status));
  const w1 = await world(8951, `ws_sess=${token}`);
  const j1 = await w1.json();
  ok('已登录 POST /api/world → 正常契约', w1.status === 200 && j1.understanding !== undefined, String(w1.status));

  // 篡改 / 过期 / 登出吊销
  const tampered = `ws_sess=${token.slice(0, -3)}abc`;
  ok('篡改 cookie → 401', (await world(8951, tampered)).status === 401, '');
  const authInst = createAuth({ WS_AUTH_USERS_FILE: usersFile, WS_SESSION_SECRET_FILE: secretFile, WS_SESSION_MAX_AGE: '604800' });
  const expired = authInst.mint('u-a', Date.now() - 8 * 24 * 3600 * 1000); // 签发时刻放在 8 天前 → 已过期
  ok('过期 cookie（签名正确）→ 401', (await world(8951, `ws_sess=${expired}`)).status === 401, '');
  const out = await fetch(B(8951) + '/api/auth/logout', { method: 'POST', headers: { cookie: `ws_sess=${token}` } });
  ok('退出 → 200 且 cookie 被清', out.status === 200 && /max-age=0/i.test(cookieOf(out)), cookieOf(out));
  ok('退出后旧 cookie 重放 → 401（服务端吊销，不是只删浏览器 cookie）', (await world(8951, `ws_sess=${token}`)).status === 401, '');

  // 多账号：bob 登录拿到的是 bob 的身份
  const gb = await login(8951, 'bob', PW_B);
  const tokenB = (cookieOf(gb).match(/ws_sess=([^;]+)/) || [])[1] || '';
  ok('第二个账号可登录，身份各自正确', gb.status === 200 && (await (await get(8951, '/api/auth/me', `ws_sess=${tokenB}`)).json()).user_id === 'u-b', '');

  // 运行中抽走用户文件 → FAIL CLOSED；恢复后原会话继续有效
  renameSync(usersFile, usersFile + '.away');
  const wBroken = await world(8951, `ws_sess=${tokenB}`);
  const jb = await wBroken.json();
  ok('用户文件消失 → 业务 503 明确不可用（绝不放行）', wBroken.status === 503 && jb.error === 'auth_unavailable', `${wBroken.status} ${JSON.stringify(jb).slice(0, 120)}`);
  ok('用户文件消失 → 登录也 503', (await login(8951, 'alice', PW_A)).status === 503, '');
  renameSync(usersFile + '.away', usersFile);
  ok('配置恢复 → 原会话继续有效', (await world(8951, `ws_sess=${tokenB}`)).status === 200, '');

  // 用户被移除 → 其 session 立即失效（手里握着的是 bob 的 cookie，移除 bob）
  writeUsers([{ user_id: 'u-a', username: 'alice', password_hash: hashPassword(PW_A) }]);
  ok('账号被移除 → 其 cookie 立即无效', (await world(8951, `ws_sess=${tokenB}`)).status === 401, '');
  writeUsers([
    { user_id: 'u-a', username: 'alice', password_hash: hashPassword(PW_A) },
    { user_id: 'u-b', username: 'bob', password_hash: hashPassword(PW_B) },
  ]);

  // 日志纪律：密码 / 用户名 / token 永远不出现
  await new Promise(r => setTimeout(r, 200));
  const L = logs.logs();
  ok('日志不含密码', !L.includes(PW_A) && !L.includes(PW_B), '');
  ok('日志不含用户名', !L.includes('alice') && !L.includes('bob'), '');
  ok('日志不含 session token', token && !L.includes(token.slice(0, 40)), '');
  ok('日志有匿名的登录成败事件', L.includes('auth login fail') && L.includes('auth login ok'), '');
} finally { kill(logs.child); }

/* ── 实例 2（8952）：认证应开而配置缺失 → FAIL CLOSED ── */
{
  const inst = start(8952, { WS_AUTH_USERS_FILE: '', WS_SESSION_SECRET_FILE: '' });
  try {
    await up(8952);
    const hz = await (await fetch(B(8952) + '/healthz')).json();
    ok('无配置：healthz 如实上报 broken', String(hz.auth).startsWith('broken:'), hz.auth);
    const root = await get(8952, '/');
    ok('无配置：首页不放行（去登录页）', root.status === 302 && root.headers.get('location') === '/login', `${root.status}`);
    ok('无配置：API 明确不可用 503，不是 401 更不是 200', (await world(8952)).status === 503, '');
    ok('无配置：登录也 503', (await login(8952, 'alice', PW_A)).status === 503, '');
  } finally { kill(inst.child); }
}
/* ── 实例 3（8953）：用户文件坏了（hash 格式非法）→ FAIL CLOSED ── */
{
  const badFile = join(VAR, 'auth-users-bad.json');
  writeFileSync(badFile, JSON.stringify({ users: [{ user_id: 'u-a', username: 'alice', password_hash: 'plaintext-secret' }] }));
  const inst = start(8953, { WS_AUTH_USERS_FILE: badFile });
  try {
    await up(8953);
    ok('坏 hash 文件：业务 503，不接受明文密码用户', (await world(8953)).status === 503, '');
    ok('坏 hash 文件：登录 503', (await login(8953, 'alice', PW_A)).status === 503, '');
  } finally { kill(inst.child); }
}
/* ── 实例 4（8954）：登录暴力尝试保护 ── */
{
  const inst = start(8954, { WS_LOGIN_MAX_ATTEMPTS: '3', WS_LOGIN_LOCK_MS: '1500' });
  try {
    await up(8954);
    let last;
    for (let i = 0; i < 3; i++) last = await login(8954, 'alice', 'guess-' + i);
    ok('连续失败 3 次内还没锁（最后一次仍 401）', last.status === 401, String(last.status));
    const locked = await login(8954, 'alice', 'guess-more');
    ok('达到上限 → 429 锁定', locked.status === 429, String(locked.status));
    const evenCorrect = await login(8954, 'alice', PW_A);
    ok('锁定期间正确密码也进不来', evenCorrect.status === 429, String(evenCorrect.status));
    await new Promise(r => setTimeout(r, 1700));
    const after = await login(8954, 'alice', PW_A);
    ok('锁定期过后正确密码恢复进入', after.status === 200, String(after.status));
  } finally { kill(inst.child); }
}
/* ── 实例 5（8955）：生产 Secure cookie 旗标 ── */
{
  const inst = start(8955, { WS_COOKIE_SECURE: '1' });
  try {
    await up(8955);
    const sc = cookieOf(await login(8955, 'alice', PW_A));
    ok('WS_COOKIE_SECURE=1 → cookie 带 Secure（生产反代 TLS 场景）', /;\s*secure/i.test(sc), sc);
  } finally { kill(inst.child); }
}

rmSync(join(VAR, 'auth-users-bad.json'), { force: true });
console.log(failures ? `\n失败 ${failures} 项` : '\n访问门自测全部通过');
process.exitCode = failures ? 1 : 0;
