/*
 * World Space 访问门（Access Gate）—— 只回答"谁能进入"，不做账号系统。
 *
 * 边界立场：
 *   1. FAIL CLOSED 是第一性质：认证应开而配置缺失/损坏（用户文件读不到、hash 格式坏、
 *      secret 不存在）时，业务一律"明确不可用"，绝不自动退化成公开访问。
 *      要公开必须显式 WS_AUTH_ENABLED=0（本地离线开发/回归用），启动日志会大声声明。
 *   2. 密码只存 scrypt+salt 的 hash，在服务器私有文件里（仓库外、.gitignore 之外的存在方式，
 *      由部署清单约定）；验证用恒时比较；账号不存在也走一次等价 scrypt（decoy），不给枚举计时信号。
 *   3. Session 是最薄的签名 cookie：负载只有 user_id / 签发 / 过期 / 版本，HMAC-SHA256 签名，
 *      客户端无法伪造；不含密码、不含用户正文。登出用服务端吊销表（单实例语义，与预算准入一致）。
 *   4. 登录暴力尝试：每 IP 连续失败达上限即锁定一段时间（内存，非持久），不引入验证码/Redis。
 *
 * 日志纪律：这里只输出事件与 ip，绝不输出 username、密码、hash、token。
 */
import { createHash, createHmac, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';

const DEFAULT_MAX_AGE = 7 * 24 * 3600;      // 与本机行动回路的 7 天保持同一量级
const MIN_MAX_AGE = 10 * 60;                // 短于这个的配置多半是配错了
const MAX_MAX_AGE = 90 * 24 * 3600;
const COOKIE = 'ws_sess';

export function hashPassword(pw) {
  const salt = randomBytes(16);
  const key = scryptSync(String(pw), salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$16384$8$1$${salt.toString('base64')}$${key.toString('base64')}`;
}

/* hash 解析同时是安全闸：参数异常（N 过大→登录时吃内存，过小→强度不足）一律视为坏 hash */
function parseHash(h) {
  const m = /^scrypt\$(\d+)\$(\d+)\$(\d+)\$([A-Za-z0-9+/=]+)\$([A-Za-z0-9+/=]+)$/.exec(String(h || ''));
  if (!m) return null;
  const N = Number(m[1]), r = Number(m[2]), p = Number(m[3]);
  if (N < 4096 || N > 65536 || r < 4 || r > 16 || p < 1 || p > 8) return null;
  const salt = Buffer.from(m[4], 'base64'), key = Buffer.from(m[5], 'base64');
  if (salt.length < 8 || key.length < 32) return null;
  return { N, r, p, salt, key };
}

function checkPassword(pw, stored) {
  const p = parseHash(stored);
  if (!p) return false;
  const got = scryptSync(String(pw), p.salt, p.key.length, { N: p.N, r: p.r, p: p.p, maxmem: 256 * 1024 * 1024 });
  return got.length === p.key.length && timingSafeEqual(got, p.key);
}

const b64u = s => Buffer.from(s).toString('base64url');
const uidRe = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,31}$/; // user_id 会进 localStorage 键名，字符集必须安全

export function createAuth(env) {
  const enabled = env.WS_AUTH_ENABLED !== '0'; // 缺省开启：忘了配变量 ≠ 全网公开
  const usersFile = env.WS_AUTH_USERS_FILE || '';
  const secretFile = env.WS_SESSION_SECRET_FILE || '';
  const maxAge = Math.min(MAX_MAX_AGE, Math.max(MIN_MAX_AGE, Number(env.WS_SESSION_MAX_AGE) || DEFAULT_MAX_AGE));
  const maxFails = Math.max(3, Number(env.WS_LOGIN_MAX_ATTEMPTS) || 5);
  const lockMs = Math.max(1000, Number(env.WS_LOGIN_LOCK_MS) || 600000);
  const cookieSecureEnv = env.WS_COOKIE_SECURE; // '1' 强制开 / '0' 强制关 / 缺省按反代 proto 自动

  // 账号不存在时也烧一次等价 scrypt：让"没这个账号"和"密码错"在计时上无法区分
  const DECOY_HASH = hashPassword(randomBytes(18).toString('base64'));
  const revoked = new Set(); // 吊销的是 token 本身的哈希（登出后旧 cookie 重放无效；重启即清，单实例语义）
  const tokenKey = t => createHash('sha256').update(String(t)).digest('hex');

  function readSecret() {
    if (!secretFile) return { err: 'secret_not_configured' };
    let raw;
    try { raw = readFileSync(secretFile, 'utf8'); } catch (e) { return { err: 'secret_unreadable' }; }
    const s = raw.trim();
    if (s.length < 32) return { err: 'secret_too_short' };
    return { secret: s };
  }

  function readUsers() {
    if (!usersFile) return { err: 'users_not_configured' };
    let j;
    try { j = JSON.parse(readFileSync(usersFile, 'utf8')); } catch (e) { return { err: 'users_unreadable_or_bad_json' }; }
    const list = Array.isArray(j && j.users) ? j.users : null;
    if (!list || list.length === 0) return { err: 'users_empty' };
    const byName = new Map(), byId = new Map();
    for (const u of list) {
      if (!u || typeof u !== 'object') return { err: 'users_bad_entry' };
      const uid = String(u.user_id || ''), name = String(u.username || '');
      if (!uidRe.test(uid)) return { err: 'users_bad_uid' };
      if (!name || name.length > 64) return { err: 'users_bad_name' };
      if (!parseHash(u.password_hash)) return { err: 'users_bad_hash' };
      if (byName.has(name) || byId.has(uid)) return { err: 'users_duplicate' };
      byName.set(name, u); byId.set(uid, u);
    }
    return { byName, byId };
  }

  /* 每次调用都重读文件：运行中删配置 / 改配置立刻生效，坏了立刻 fail closed */
  function status() {
    if (!enabled) return { enabled: false, ready: false, reason: 'auth_off' };
    const s = readSecret();
    if (s.err) return { enabled: true, ready: false, reason: s.err };
    const u = readUsers();
    if (u.err) return { enabled: true, ready: false, reason: u.err };
    return { enabled: true, ready: true, reason: '', secret: s.secret, users: u };
  }

  function mint(uid, now = Date.now()) {
    const st = status();
    if (!st.ready) throw new Error('auth_not_ready');
    const payload = b64u(JSON.stringify({ uid, iat: now, exp: now + maxAge * 1000, v: 1 }));
    const sig = createHmac('sha256', st.secret).update(payload).digest('base64url');
    return `${payload}.${sig}`;
  }

  /* 验证：签名恒时比较 → 未过期 → 用户仍存在 → 未被登出吊销。任何一步不过都不放行。 */
  function sessionOf(token, now = Date.now()) {
    const st = status();
    if (!st.ready) return { ok: false, reason: 'auth_broken' };
    const t = String(token || '');
    const dot = t.indexOf('.');
    if (dot <= 0) return { ok: false, reason: 'malformed' };
    const payload = t.slice(0, dot), sig = t.slice(dot + 1);
    const want = createHmac('sha256', st.secret).update(payload).digest();
    let got;
    try { got = Buffer.from(sig, 'base64url'); } catch (e) { return { ok: false, reason: 'malformed' }; }
    if (got.length !== want.length || !timingSafeEqual(got, want)) return { ok: false, reason: 'bad_signature' };
    let j;
    try { j = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')); } catch (e) { return { ok: false, reason: 'malformed' }; }
    if (!j || j.v !== 1 || !uidRe.test(String(j.uid || ''))) return { ok: false, reason: 'malformed' };
    if (!Number.isFinite(j.exp) || j.exp <= now) return { ok: false, reason: 'expired' };
    if (!st.users.byId.has(j.uid)) return { ok: false, reason: 'user_gone' };
    if (revoked.has(tokenKey(t))) return { ok: false, reason: 'revoked' };
    return { ok: true, uid: j.uid, iat: j.iat, exp: j.exp, token: t };
  }

  function login(username, password) {
    const st = status();
    if (!st.ready) return { ok: false, reason: 'auth_broken' };
    const u = st.users.byName.get(String(username || ''));
    const stored = u ? u.password_hash : DECOY_HASH;
    const good = checkPassword(password, stored);
    if (!u || !good) return { ok: false };
    return { ok: true, uid: u.user_id, token: mint(u.user_id) };
  }

  function revoke(sess) { if (sess && sess.ok) { revoked.add(tokenKey(sess.token)); if (revoked.size > 4096) revoked.clear(); } }

  /* ── 登录暴力尝试保护：每 IP 连续失败 → 锁定一段时间。成功清零；不引入验证码。 ── */
  const fails = new Map(); // ip -> { n, last, until }
  function loginGuard(ip) {
    const now = Date.now();
    const f = fails.get(ip);
    if (!f) return { locked: false };
    if (f.until > now) return { locked: true, retryAfterSec: Math.ceil((f.until - now) / 1000) };
    if (now - f.last > lockMs) fails.delete(ip);
    return { locked: false };
  }
  function loginFail(ip) {
    const now = Date.now();
    if (fails.size > 10000) fails.clear();
    const f = fails.get(ip) || { n: 0, last: 0, until: 0 };
    if (now - f.last > lockMs) f.n = 0;
    f.n += 1; f.last = now;
    if (f.n >= maxFails) { f.until = now + lockMs; f.n = 0; }
    fails.set(ip, f);
  }
  function loginPass(ip) { fails.delete(ip); }

  function cookieFor(token, reqProtoHttps) {
    const secure = cookieSecureEnv === '1' || (cookieSecureEnv !== '0' && !!reqProtoHttps);
    return `${COOKIE}=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure ? '; Secure' : ''}`;
  }
  const clearCookie = () => `${COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`;
  const cookieName = COOKIE;

  return { enabled, maxAge, status, mint, sessionOf, login, revoke, loginGuard, loginFail, loginPass, cookieFor, clearCookie, cookieName };
}

/* 从 Cookie 头里取 session 值（不解析其它 cookie） */
export function sessionTokenFrom(header, name = 'ws_sess') {
  const h = String(header || '');
  for (const part of h.split(';')) {
    const i = part.indexOf('=');
    if (i === -1) continue;
    if (part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
  }
  return '';
}
