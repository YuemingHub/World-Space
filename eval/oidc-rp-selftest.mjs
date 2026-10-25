/* B3 统一身份 RP 自测（真实 IdP 子进程 × 真实 world.mjs 子进程，全 HTTP 驱动）。
 *
 * 覆盖：统一登录 start → IdP 交互登录 → callback → 绑定（门禁账号密码证明）→
 *       门禁会话可用（/api/auth/me）→ 链接落盘（sub→user_id，participant 语义同源）→
 *       SSO 直通免绑定 → 错密码绑定 401 → 旧登录路径不破坏。
 *
 * 跑法：node eval/oidc-rp-selftest.mjs
 * 依赖：本测试的 IdP 夹具需要 oidc-provider（仅测试用；服务运行时保持零依赖）。
 *       未安装时如实 SKIP，不假装通过：node install 前先 `npm i oidc-provider@8 --no-save`。
 * 端口：IdP 24420 / world 24655（全部 loopback）。
 */
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import http from 'node:http';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..');
const IDP_PORT = 24420;
const WS_PORT = 24655;
const IDP = `http://127.0.0.1:${IDP_PORT}`;
const WS = `http://127.0.0.1:${WS_PORT}`;

let oidcProvider;
try { oidcProvider = (await import('oidc-provider')).Provider; } catch {
  console.error('SKIP: oidc-provider 未安装（npm i oidc-provider@8 --no-save 后重跑）。零依赖运行时不受影响。');
  process.exit(0);
}

/* ---- IdP 夹具（持久化 adapter 同 B1/B2 形态） ---- */
const idpData = mkdtempSync(path.join(tmpdir(), 'ws-oidc-idp-'));
const CLIENTS = [{
  client_id: 'world-space-rp', client_secret: 'test-secret-ws',
  redirect_uris: [`${WS}/api/oidc/callback`],
  grant_types: ['authorization_code'], response_types: ['code'],
  token_endpoint_auth_method: 'client_secret_basic',
}];

class FileAdapter {
  constructor(name) { this.name = name; }
  key(id) { return `${this.name}:${id}`; }
  fileFor(key) { return path.join(idpData, 'records', encodeURIComponent(key) + '.json'); }
  async upsert(id, payload, expiresIn) {
    const { mkdirSync, writeFileSync } = await import('node:fs');
    mkdirSync(path.join(idpData, 'records'), { recursive: true });
    writeFileSync(this.fileFor(this.key(id)), JSON.stringify({ payload, exp: expiresIn ? Date.now() + expiresIn * 1000 : null }));
    if (payload && payload.uid) {
      mkdirSync(path.join(idpData, 'uid'), { recursive: true });
      writeFileSync(path.join(idpData, 'uid', encodeURIComponent(`${this.name}:${payload.uid}`)), JSON.stringify({ id }));
    }
  }
  async find(id) {
    if (this.name === 'Client') return CLIENTS.find(c => c.client_id === String(id)) || undefined;
    const f = this.fileFor(this.key(id));
    if (!existsSync(f)) return undefined;
    const rec = JSON.parse(readFileSync(f, 'utf8'));
    if (rec.exp && rec.exp < Date.now()) { rmSync(f); return undefined; }
    return rec.payload;
  }
  async findByUid(uid) {
    const f = path.join(idpData, 'uid', encodeURIComponent(`${this.name}:${String(uid)}`));
    if (!existsSync(f)) return undefined;
    return this.find(JSON.parse(readFileSync(f, 'utf8')).id);
  }
  async consume(id) { try { rmSync(this.fileFor(this.key(id))); } catch {} }
  async destroy(id) { try { rmSync(this.fileFor(this.key(id))); } catch {} }
  async revokeByGrantId(grantId) {
    const dir = path.join(idpData, 'records');
    if (!existsSync(dir)) return;
    const { readdirSync, unlinkSync } = await import('node:fs');
    for (const f of readdirSync(dir)) {
      const rec = JSON.parse(readFileSync(path.join(dir, f), 'utf8'));
      if (rec.payload && rec.payload.grantId === grantId) unlinkSync(path.join(dir, f));
    }
  }
}

const provider = new oidcProvider(IDP, {
  adapter: (name) => new FileAdapter(name),
  ...{
    clients: CLIENTS,
    claims: { profile: ['name'] },
    features: { devInteractions: { enabled: true } },
    findAccount: async (ctx, id) => (id === 'id_test_founder'
      ? { accountId: id, claims: async () => ({ sub: id, name: '测试统一身份' }) }
      : undefined),
    pkce: { required: () => true },
  },
});
await new Promise((res) => http.createServer(provider.callback()).listen(IDP_PORT, '127.0.0.1', res));
console.log('idp up', IDP);

/* ---- 门禁用户文件 + 启动 world.mjs ---- */
const wsState = mkdtempSync(path.join(tmpdir(), 'ws-oidc-state-'));
const usersFile = path.join(wsState, 'users.json');
// 花名册形状按 auth.mjs 读取约定：{ users: { <user_id>: { password: scrypt 形状 } } }
// 密码哈希用 auth.mjs 自己的 hashPassword 生成（同进程内 import，保证形状一致）
const { hashPassword } = await import(pathToFileURL(path.join(ROOT, 'server', 'auth.mjs')).href);
writeFileSync(usersFile, JSON.stringify({
  users: [{ user_id: 'gateuser', username: 'gateuser', password_hash: hashPassword('gate-pass-12345') }],
}));

const server = spawn(process.execPath, ['server/world.mjs'], {
  cwd: ROOT,
  env: {
    ...process.env,
    WS_PORT: String(WS_PORT),
    WS_OPS_PORT: '0',
    WS_AUTH_ENABLED: '1',
    WS_AUTH_USERS_FILE: usersFile,
    WS_SESSION_SECRET_FILE: (() => { const f = path.join(wsState, 'secret'); writeFileSync(f, 'x'.repeat(64)); return f; })(),
    WS_OIDC_ENABLED: '1',
    WS_OIDC_ISSUER: IDP,
    WS_OIDC_CLIENT_ID: 'world-space-rp',
    WS_OIDC_CLIENT_SECRET: 'test-secret-ws',
    WS_OIDC_REDIRECT_URI: `${WS}/api/oidc/callback`,
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let serverLog = '';
server.stdout.on('data', d => { serverLog += String(d); });
server.stderr.on('data', d => { serverLog += String(d); });
await new Promise((res, rej) => {
  const t = setTimeout(() => rej(new Error('world.mjs 启动超时: ' + serverLog.slice(-300))), 15000);
  const on = (d) => { if (String(d).includes('world api')) { clearTimeout(t); server.stdout.off('data', on); res(); } };
  server.stdout.on('data', on); server.stderr.on('data', on);
});

const jar = [];
const absorb = (r) => { for (const c of (r.headers.getSetCookie ? r.headers.getSetCookie() : [])) { const pair = c.split(';')[0]; const n = pair.split('=')[0]; const i = jar.findIndex(x => x.startsWith(n + '=')); if (i >= 0) jar[i] = pair; else jar.push(pair); } };
async function req(url, { method = 'GET', body = null, fresh = false } = {}) {
  const res = await fetch(url, {
    method,
    headers: { cookie: fresh ? '' : jar.join('; '), ...(body ? { 'content-type': 'application/x-www-form-urlencoded' } : {}) },
    body: body ? new URLSearchParams(body).toString() : undefined,
    redirect: 'manual', signal: AbortSignal.timeout(8000),
  });
  absorb(res);
  return { status: res.status, location: res.headers.get('location'), text: [301, 302, 303].includes(res.status) ? '' : await res.text() };
}
const parseForm = (html) => {
  const action = (html.match(/<form[^>]*action="([^"]*)"/) || [])[1];
  const fields = {};
  for (const m of html.matchAll(/<input[^>]*name="([^"]*)"(?:[^>]*value="([^"]*)")?[^>]*>/g)) fields[m[1]] = m[2] || '';
  return { action, fields };
};
async function driveFlow() {
  let r = await req(`${WS}/api/oidc/start`, { fresh: true });
  if (r.status !== 302) throw new Error('start 失败: ' + r.status + r.text.slice(0, 100));
  let url = r.location;
  let callbackUrl = null;
  for (let hop = 0; hop < 8 && !callbackUrl; hop++) {
    r = await req(url);
    if (r.location && r.location.includes('code=')) { callbackUrl = r.location.startsWith('http') ? r.location : WS + r.location; break; }
    if ((r.status === 302 || r.status === 303) && r.location) { url = new URL(r.location, url).toString(); continue; }
    const { action: raw, fields } = parseForm(r.text);
    if (!raw) throw new Error('无表单: ' + r.text.slice(0, 100));
    const action = new URL(raw, url).toString();
    const body = { ...fields };
    if (fields.prompt === 'login') { body.login = 'id_test_founder'; body.password = 'x'; }
    r = await req(action, { method: 'POST', body });
    if (r.location && r.location.includes('code=')) { callbackUrl = r.location.startsWith('http') ? r.location : WS + r.location; break; }
    if ((r.status === 302 || r.status === 303) && r.location) { url = new URL(r.location, action).toString(); continue; }
  }
  if (!callbackUrl) throw new Error('未拿到回调');
  return callbackUrl;
}

let failed = 0;
const t = async (name, fn) => {
  try { await fn(); console.log('✅', name); }
  catch (e) { failed++; console.error('❌', name, '\n  ', e.message); }
};

/* 1) 绑定流 */
await t('统一登录 → IdP → callback → 绑定页', async () => {
  const cb = await driveFlow();
  const r = await req(cb);
  if (r.status !== 302 || !r.location.startsWith('/oidc/bind')) throw new Error('应去绑定页: ' + r.status + ' ' + (r.location || r.text.slice(0, 100)));
  const page = await req(WS + r.location);
  if (page.status !== 200 || !page.text.includes('绑定你的空间')) throw new Error('绑定页渲染失败');
});
await t('错密码绑定 → 401', async () => {
  const bindToken = jar.length ? jar.find(c => c.startsWith('_')) : null; void bindToken;
  // 重新走一遍拿新 bindToken（上面那次已消费 pending）
  const cb = await driveFlow();
  const r = await req(cb);
  const token = r.location.split('bind=')[1];
  const res2 = await req(`${WS}/api/oidc/bind`, { method: 'POST', body: { bind: token, username: 'gateuser', password: 'wrong-pass' } });
  if (res2.status !== 401) throw new Error('应 401: ' + res2.status + ' ' + res2.text.slice(0, 100));
});
await t('正确绑定 → 门禁会话 → /api/auth/me 可用', async () => {
  const cb = await driveFlow();
  const r = await req(cb);
  const token = r.location.split('bind=')[1];
  const res2 = await req(`${WS}/api/oidc/bind`, { method: 'POST', body: { bind: token, username: 'gateuser', password: 'gate-pass-12345' } });
  if (res2.status !== 302) throw new Error('绑定应 302 进空间: ' + res2.status + ' ' + res2.text.slice(0, 120));
  const me = await req(`${WS}/api/auth/me`);
  if (me.status !== 200 || !JSON.parse(me.text).user_id) throw new Error('门禁会话不可用: ' + me.status);
});
await t('链接落盘：sub → user_id', async () => {
  const linksFile = usersFile.replace('users.json', 'oidc-links.json');
  if (!existsSync(linksFile)) throw new Error('链接文件不存在');
  const links = JSON.parse(readFileSync(linksFile, 'utf8'));
  if (links.id_test_founder?.user_id !== 'gateuser') throw new Error('链接内容不符: ' + JSON.stringify(links));
});
await t('SSO 直通：已绑定身份再次登录免绑定', async () => {
  jar.length = 0; // 只清 WS 会话，保留 IdP 会话
  const cb = await driveFlow();
  const r = await req(cb);
  if (r.status !== 302 || r.location !== '/') throw new Error('应直接进空间: ' + r.status + ' ' + (r.location || ''));
  const me = await req(`${WS}/api/auth/me`);
  if (me.status !== 200) throw new Error('SSO 后会话不可用');
});
await t('旧登录路径不破坏：/api/auth/login 照常', async () => {
  jar.length = 0;
  const res = await fetch(`${WS}/api/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: 'gateuser', password: 'gate-pass-12345' }), signal: AbortSignal.timeout(8000) });
  const r = { status: res.status, text: await res.text() };
  if (r.status !== 200) throw new Error('旧登录应 200: ' + r.status + ' ' + r.text.slice(0, 100));
});

server.kill();
if (failed > 0) { console.error(`B3 自测失败：${failed} 项红`); process.exit(1); }
console.log('B3-RP-SELFTEST-ALL-PASS');
process.exit(0);
