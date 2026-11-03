/*
 * 统一管理台的 World Space 侧回归（离线桩 + 真实 HTTP 管线）：
 *   ops 面双门（loopback 由绑定保证 + Bearer）、账号增改停与强制下线（session_epoch 语义）、
 *   模型凭据掩码/校验/落盘/重启后仍在、任何响应与日志都不含密码哈希或密钥原文。
 * 夹具全在 var/（gitignored）。端口每个实例独占，绝不与默认 3201 相撞。
 */
import { spawn } from 'node:child_process';
import { rmSync, mkdirSync, writeFileSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';
import { hashPassword } from '../server/auth.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const VAR = join(ROOT, 'var');
mkdirSync(VAR, { recursive: true });

let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };

const SUFFIX = process.pid + '-' + randomBytes(4).toString('hex');
const TOKEN = 'console-token-' + randomBytes(12).toString('hex');
const PW_A = 'alice-password-2026', PW_B = 'bob-password-2026';
const PW_CAROL = 'carol-password-2026', PW_CAROL2 = 'carol-password-2027';
const ENV_KEY = 'ws-env-key-' + randomBytes(12).toString('hex');
const NEW_KEY = 'ws-new-key-' + randomBytes(12).toString('hex');

const usersFile = join(VAR, `console-users-${SUFFIX}.json`);
const secretFile = join(VAR, `console-secret-${SUFFIX}.txt`);
const runtimeFile = join(VAR, `console-runtime-${SUFFIX}.json`);
const stateFile = join(VAR, `console-state-${SUFFIX}.json`);
writeFileSync(secretFile, randomBytes(48).toString('base64') + '\n');
writeFileSync(usersFile, JSON.stringify({
  users: [
    { user_id: 'u-alice', username: 'alice', password_hash: hashPassword(PW_A) },
    { user_id: 'u-bob', username: 'bob', password_hash: hashPassword(PW_B) },
  ],
}, null, 2));

function start(port, extra = {}, capture = true) {
  const chunks = [];
  rmSync(stateFile, { force: true }); // 预算状态不跨运行累计
  const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
    env: Object.assign({}, process.env, {
      WS_PROVIDER: 'stub', WS_STUB_CASE: 'ok', WS_SEARCH: 'fixture', WS_LIVENESS: '0',
      WS_PORT: String(port), WS_HOST: '127.0.0.1',
      WS_OPS_PORT: String(port + 400),
      WS_STATE_FILE: stateFile,
      WS_RUNTIME_CONFIG_FILE: runtimeFile,
      WS_DAILY_CAP: '500',
      WS_AUTH_USERS_FILE: usersFile,
      WS_SESSION_SECRET_FILE: secretFile,
      WS_RATE_LIMIT: '1000',
      WS_LOGIN_MAX_ATTEMPTS: '100',
      WS_LOGIN_LOCK_MS: '1000',
      WS_MANAGEMENT_TOKEN: TOKEN,
      WS_LLM_BASE_URL: 'https://env.example.com/v1',
      WS_LLM_MODEL: 'env-model',
      WS_LLM_KEY: ENV_KEY,
    }, extra),
    stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'ignore',
  });
  if (capture) { child.stdout.on('data', d => chunks.push(d)); child.stderr.on('data', d => chunks.push(d)); }
  return { child, logs: () => chunks.join('') };
}

async function up(port) {
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(`http://127.0.0.1:${port}/healthz`)).ok) return; } catch (_) { /* 还没起 */ }
    await new Promise(r => setTimeout(r, 150));
  }
  throw new Error(`world:${port} 没起来`);
}
const kill = (c) => { try { c.kill('SIGKILL'); } catch (_) { /* 已退出 */ } };
const B = (port) => `http://127.0.0.1:${port}`;
const OPS = (port) => `http://127.0.0.1:${port + 400}`;

function ops(method, port, path, body, token) {
  return fetch(OPS(port) + path, {
    method,
    headers: Object.assign(
      body === undefined ? {} : { 'content-type': 'application/json' },
      token === undefined ? {} : { authorization: 'Bearer ' + token },
    ),
    body: body === undefined ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)),
  });
}
const login = (port, username, password) => fetch(B(port) + '/api/auth/login', {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ username, password }),
});
const me = (port, cookie) => fetch(B(port) + '/api/auth/me', { headers: cookie ? { cookie } : {} });
const cookieOf = (res) => res.headers.get('set-cookie') || '';
const tokenOf = (res) => {
  const sc = cookieOf(res);
  return (sc.match(/ws_sess=([^;]+)/) || [])[1] || '';
};

let logs = null;
try {
  logs = start(8961);
  await up(8961);

  /* ── 门禁 ── */
  ok('ops 面：无 token → 401', (await ops('GET', 8961, '/api/ops/roster')).status === 401, '');
  ok('ops 面：错 token → 401', (await ops('GET', 8961, '/api/ops/roster', undefined, TOKEN + 'x')).status === 401, '');
  ok('ops 面：未知路径 → 404（不是把整个面当静态服务器）', (await ops('GET', 8961, '/api/ops/nope', undefined, TOKEN)).status === 404, '');
  ok('ops 面：业务页不可达', (await fetch(OPS(8961) + '/login')).status === 404, '');
  ok('ops 面：/healthz 仍开放', (await fetch(OPS(8961) + '/healthz')).status === 200, '');
  ok('ops 面：超过 32KB 的请求体被拒', (await ops('POST', 8961, '/api/ops/users/create', 'x'.repeat(40000), TOKEN)).status === 400, '');

  /* ── 花名册：有账号、无哈希 ── */
  const rosterRes = await ops('GET', 8961, '/api/ops/roster', undefined, TOKEN);
  const rosterText = await rosterRes.text();
  const roster = JSON.parse(rosterText);
  ok('花名册 200 且门禁 ready', rosterRes.status === 200 && roster.gate.status === 'ready', rosterText.slice(0, 160));
  ok('花名册列出两个账号', Array.isArray(roster.gate.users) && roster.gate.users.length === 2, JSON.stringify(roster.gate.users));
  ok('花名册不含密码哈希／密码原文', !/\$2[aby]\$/.test(rosterText) && !rosterText.includes(PW_A), rosterText.slice(0, 200));

  /* ── 新建账号 ── */
  const weak = await ops('POST', 8961, '/api/ops/users/create', { username: 'carol', password: 'short' }, TOKEN);
  const weakText = await weak.text();
  ok('弱密码 → 400 weak_password', weak.status === 400 && JSON.parse(weakText).error === 'weak_password', weakText);
  const badName = await ops('POST', 8961, '/api/ops/users/create', { username: 'bad\nname', password: PW_CAROL }, TOKEN);
  const badNameText = await badName.text();
  ok('非法用户名 → 400 invalid_username', badName.status === 400 && JSON.parse(badNameText).error === 'invalid_username', badNameText);
  const createdRes = await ops('POST', 8961, '/api/ops/users/create', { username: 'carol', password: PW_CAROL }, TOKEN);
  const createdText = await createdRes.text();
  const created = JSON.parse(createdText);
  ok('新建账号 200，返回 user_id 与用户名', createdRes.status === 200 && /^[0-9a-f]{24}$/.test(created.user && created.user.user_id), createdText);
  ok('新建响应不含密码或哈希', !createdText.includes(PW_CAROL) && !/\$2[aby]\$/.test(createdText), createdText);
  const dup = await ops('POST', 8961, '/api/ops/users/create', { username: 'carol', password: PW_CAROL }, TOKEN);
  const dupText = await dup.text();
  ok('重名 → 409 username_taken', dup.status === 409 && JSON.parse(dupText).error === 'username_taken', dupText);
  const carolLogin = await login(8961, 'carol', PW_CAROL);
  const carolToken = tokenOf(carolLogin);
  ok('新账号可登录，身份正确', carolLogin.status === 200 && (await (await me(8961, `ws_sess=${carolToken}`)).json()).user_id === created.user.user_id, '');

  /* ── 改密码：旧 cookie 立即失效，新密码生效 ── */
  const resetRes = await ops('POST', 8961, '/api/ops/users/password', { username: 'carol', password: PW_CAROL2 }, TOKEN);
  const resetText = await resetRes.text();
  ok('改密码 200 且不回显密码', resetRes.status === 200 && !resetText.includes(PW_CAROL2), resetText);
  ok('改密码后旧 cookie → 401', (await me(8961, `ws_sess=${carolToken}`)).status === 401, '');
  ok('改密码后旧密码 → 401', (await login(8961, 'carol', PW_CAROL)).status === 401, '');
  const carolLogin2 = await login(8961, 'carol', PW_CAROL2);
  const carolToken2 = tokenOf(carolLogin2);
  ok('改密码后新密码可登录', carolLogin2.status === 200 && carolToken2.length > 20, String(carolLogin2.status));

  /* ── 停用／启用：旧会话不复活 ── */
  const off = await ops('POST', 8961, '/api/ops/users/disabled', { username: 'carol', disabled: true }, TOKEN);
  const offText = await off.text();
  ok('停用 200', off.status === 200 && JSON.parse(offText).user.disabled === true, offText);
  ok('停用后旧 cookie → 401', (await me(8961, `ws_sess=${carolToken2}`)).status === 401, '');
  ok('停用后登录 → 401（统一口径，不泄露停用原因）', (await login(8961, 'carol', PW_CAROL2)).status === 401, '');
  const on = await ops('POST', 8961, '/api/ops/users/disabled', { username: 'carol', disabled: false }, TOKEN);
  const onText = await on.text();
  ok('启用 200', on.status === 200 && JSON.parse(onText).user.disabled === false, onText);
  ok('启用后旧 cookie 仍无效（不是"复活"）', (await me(8961, `ws_sess=${carolToken2}`)).status === 401, '');
  const carolLogin3 = await login(8961, 'carol', PW_CAROL2);
  const carolToken3 = tokenOf(carolLogin3);
  ok('启用后可重新登录', carolLogin3.status === 200 && carolToken3.length > 20, String(carolLogin3.status));

  /* ── 强制下线 ── */
  const out = await ops('POST', 8961, '/api/ops/users/logout', { username: 'carol' }, TOKEN);
  ok('强制下线 200', out.status === 200, await out.text());
  ok('下线后旧 cookie → 401', (await me(8961, `ws_sess=${carolToken3}`)).status === 401, '');
  ok('下线不影响再次登录', (await login(8961, 'carol', PW_CAROL2)).status === 200, '');
  ok('对不存在账号改密 → 404', (await ops('POST', 8961, '/api/ops/users/password', { username: 'nobody', password: PW_CAROL }, TOKEN)).status === 404, '');

  /* ── 模型凭据：视图掩码、校验、即时生效、落盘 ── */
  const llmRes = await ops('GET', 8961, '/api/ops/llm', undefined, TOKEN);
  const llmText = await llmRes.text();
  const llm = JSON.parse(llmText);
  ok('llm 视图来自 env 且给指纹', llmRes.status === 200 && llm.llm.source === 'env'
    && llm.llm.key_fingerprint === createHash('sha256').update(ENV_KEY).digest('hex').slice(0, 10), llmText);
  ok('llm 视图不含密钥原文', !llmText.includes(ENV_KEY), llmText);

  for (const [patch, error] of [
    [{ base_url: 'nope' }, 'base_url_invalid'],
    [{ base_url: 'https://u:p@example.com' }, 'base_url_must_not_embed_credentials'],
    [{ api_key: 'has space' }, 'api_key_must_not_contain_whitespace'],
    [{}, 'nothing_to_update'],
  ]) {
    const r = await ops('PUT', 8961, '/api/ops/llm', patch, TOKEN);
    ok(`llm 校验 ${JSON.stringify(patch)} → 400 ${error}`, r.status === 400 && (await r.json()).error === error, String(r.status));
  }

  const putRes = await ops('PUT', 8961, '/api/ops/llm', {
    base_url: 'https://new.example.com/v1/',
    model: 'new-model',
    api_key: NEW_KEY,
  }, TOKEN);
  const putText = await putRes.text();
  const put = JSON.parse(putText);
  ok('llm 更新 200 且掩码/指纹正确', putRes.status === 200 && put.llm.source === 'override'
    && put.llm.base_url === 'https://new.example.com/v1' && put.llm.model === 'new-model'
    && put.llm.key_fingerprint === createHash('sha256').update(NEW_KEY).digest('hex').slice(0, 10), putText);
  ok('llm 更新响应不含密钥原文', !putText.includes(NEW_KEY), putText);

  const health = await (await fetch(OPS(8961) + '/healthz')).json();
  ok('更新后进程内配置立即生效（诊断面 model=new-model）', health.model === 'new-model', JSON.stringify(health).slice(0, 160));

  ok('覆盖层已落盘', existsSync(runtimeFile), runtimeFile);
  const saved = JSON.parse(readFileSync(runtimeFile, 'utf8'));
  ok('覆盖层内容完整', saved.llm && saved.llm.api_key === NEW_KEY && saved.llm.model === 'new-model' && saved.llm.updated_at, JSON.stringify(saved).slice(0, 160));
  if (process.platform !== 'win32') {
    ok('覆盖层权限 0600', (statSync(runtimeFile).mode & 0o777) === 0o600, (statSync(runtimeFile).mode & 0o777).toString(8));
  }

  /* ── 日志纪律 ── */
  await new Promise(r => setTimeout(r, 250));
  const L1 = logs.logs();
  ok('日志不含任何密码原文', ![PW_A, PW_B, PW_CAROL, PW_CAROL2].some(p => L1.includes(p)), '');
  ok('日志不含密钥原文', !L1.includes(ENV_KEY) && !L1.includes(NEW_KEY), '');
  ok('日志不含 session token', carolToken3.length > 0 && !L1.includes(carolToken3.slice(0, 40)), '');
  ok('ops 操作留下了审计行（动作+结果）', /ops users\.create result=ok/.test(L1) && /ops llm\.update result=ok/.test(L1), '');

  /* ── 重启：账号与覆盖层都还在 ── */
  kill(logs.child);
  await new Promise(r => setTimeout(r, 300));
  const restarted = start(8961);
  logs = restarted;
  try {
    await up(8961);
    const llm2 = await (await ops('GET', 8961, '/api/ops/llm', undefined, TOKEN)).json();
    ok('重启后 llm 仍是覆盖值', llm2.llm.source === 'override' && llm2.llm.model === 'new-model'
      && llm2.llm.key_fingerprint === createHash('sha256').update(NEW_KEY).digest('hex').slice(0, 10), JSON.stringify(llm2.llm));
    ok('重启后新账号仍可登录', (await login(8961, 'carol', PW_CAROL2)).status === 200, '');
    const roster2 = await (await ops('GET', 8961, '/api/ops/roster', undefined, TOKEN)).json();
    ok('重启后花名册含三个账号且无哈希', roster2.gate.users.length === 3 && !/\$2[aby]\$/.test(JSON.stringify(roster2)), JSON.stringify(roster2.gate.users));
  } finally {
    kill(restarted.child);
    await new Promise(r => setTimeout(r, 300));
  }
} finally {
  kill(logs && logs.child);
}

/* ── 未配置管理 token：端点等于不存在，业务不受影响 ── */
{
  const inst = start(8962, { WS_MANAGEMENT_TOKEN: '' });
  try {
    await up(8962);
    ok('未配 token：ops 账号端点 404（不是 401——等于没有这条路由）',
      (await ops('GET', 8962, '/api/ops/roster', undefined, TOKEN)).status === 404, '');
    ok('未配 token：业务登录照常', (await login(8962, 'alice', PW_A)).status === 200, '');
    ok('未配 token：公网 /healthz 仍只有 {ok:true}',
      (await (await fetch(B(8962) + '/healthz')).text()) === '{"ok":true}', '');
  } finally { kill(inst.child); }
}

rmSync(usersFile, { force: true });
rmSync(secretFile, { force: true });
rmSync(runtimeFile, { force: true });
rmSync(stateFile, { force: true });
console.log(failures ? `\n失败 ${failures} 项` : '\n统一管理台（World Space 侧）自测全部通过');
process.exitCode = failures ? 1 : 0;
