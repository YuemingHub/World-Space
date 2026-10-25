/* B3 统一身份接入（RP 侧）——2026-10-25。
 *
 * 边界立场（与 B1/B2 合同一致，且守住 World Space 的两条既有不变量）：
 *   1) **零依赖不变**：本模块只用 node:crypto / node:fs / 全局 fetch——
 *      授权码+PKCE 流程是 OAuth2 标准请求；ID Token 验签用 Node 标准
 *      crypto.verify('RSA-SHA256', ...) 对 IdP JWKS 的 RSA 公钥（非自研加密）。
 *      不引入 openid-client 是为保持本服务「零 npm 依赖」的部署形态；
 *      权衡已在评审分支文档记录，若 Commander 裁决改用库，接口不变。
 *   2) **门禁权限不放大**：统一身份只提供「另一条进门的路」。绑定必须持
 *      本地门禁账号密码证明（AUTH.login），链接只记 sub → user_id；
 *      会话照旧由 AUTH 签发（与手工登录同一把 cookie），准入面一字不变。
 *   3) fail-closed：WS_OIDC_ENABLED=1 但配置缺失 → 启动即抛错（与业务口
 *      「配错就该起不来」同一立场）；任何验签/状态异常 → 拒绝，不降级放行。
 *
 * 状态存放：pending/bind 是进程内 Map（单实例语义与 auth.mjs 相同），TTL 10 分钟；
 *   链接落盘 WS_OIDC_LINKS_FILE（默认与门禁 users 文件同目录 oidc-links.json）。
 */
import crypto from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

const PENDING_TTL_MS = 10 * 60 * 1000;
const pending = new Map();  // state → { nonce, verifier, created_at }
const binds = new Map();    // bindToken → { sub, name, created_at }
const jwksCache = { uri: '', keys: null, fetchedAt: 0 };

function prune(map) {
  const now = Date.now();
  for (const [k, v] of map) if (now - v.created_at > PENDING_TTL_MS) map.delete(k);
}

function loadLinks(linksFile) {
  if (!existsSync(linksFile)) return {};
  try { return JSON.parse(readFileSync(linksFile, 'utf8')); } catch { return {}; }
}
function saveLinks(linksFile, links) {
  mkdirSync(dirname(linksFile), { recursive: true });
  writeFileSync(linksFile, JSON.stringify(links, null, 2));
}

/* ---- OIDC 协议面（薄客户端） ---- */

async function discover(issuer) {
  const url = issuer.replace(/\/$/, '') + '/.well-known/openid-configuration';
  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`discovery failed: ${res.status}`);
  return res.json();
}

async function jwksKeys(discovery) {
  if (jwksCache.uri === discovery.jwks_uri && jwksCache.keys && Date.now() - jwksCache.fetchedAt < 3600_000) {
    return jwksCache.keys;
  }
  const res = await fetch(discovery.jwks_uri, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`jwks fetch failed: ${res.status}`);
  jwksCache.uri = discovery.jwks_uri;
  jwksCache.keys = await res.json();
  jwksCache.fetchedAt = Date.now();
  return jwksCache.keys;
}

async function verifyIdToken(idToken, { issuer, clientId, nonce }) {
  const [h64, p64, s64] = String(idToken).split('.');
  if (!h64 || !p64 || !s64) throw new Error('id_token malformed');
  const header = JSON.parse(Buffer.from(h64, 'base64url').toString('utf8'));
  if (header.alg !== 'RS256') throw new Error(`unexpected alg ${header.alg}`);
  const jwks = await jwksKeys(await discover(issuer));
  const jwk = (jwks.keys || []).find(k => k.kty === 'RSA' && (!k.kid || k.kid === header.kid) && (k.use || 'sig') === 'sig');
  if (!jwk) throw new Error('no matching JWK');
  const key = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const ok = crypto.verify('RSA-SHA256', Buffer.from(`${h64}.${p64}`), key, Buffer.from(s64, 'base64url'));
  if (!ok) throw new Error('signature invalid');
  const claims = JSON.parse(Buffer.from(p64, 'base64url').toString('utf8'));
  const now = Math.floor(Date.now() / 1000);
  if (claims.iss !== issuer) throw new Error('iss mismatch');
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!aud.includes(clientId)) throw new Error('aud mismatch');
  if (!Number.isFinite(claims.exp) || claims.exp <= now) throw new Error('token expired');
  if (nonce && claims.nonce !== nonce) throw new Error('nonce mismatch');
  return claims;
}

async function exchangeCode(discovery, { clientId, clientSecret, redirectUri, code, verifier }) {
  const basic = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
  const res = await fetch(discovery.token_endpoint, {
    method: 'POST',
    headers: { authorization: `Basic ${basic}`, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code', code, redirect_uri: redirectUri, code_verifier: verifier,
    }).toString(),
    signal: AbortSignal.timeout(8000),
  });
  const token = await res.json();
  if (!res.ok || !token.id_token) throw new Error(`token exchange failed: ${JSON.stringify(token).slice(0, 150)}`);
  return token;
}

/* ---- 绑定页（与门禁登录页同一视觉语系，零外部资源） ---- */
function bindPageHtml(bindToken, esc) {
  return `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>World Space · 绑定</title><link rel="stylesheet" href="/style.css"></head>
<body class="login-page"><main class="login">
<h1>绑定你的空间</h1>
<p class="sub">统一身份首次使用需要和这个空间对上号。输入你原有的门禁账号和密码，只做一次，之后免输。</p>
<form method="POST" action="/api/oidc/bind">
<input type="hidden" name="bind" value="${esc(bindToken)}">
<label for="username">账号</label>
<input id="username" name="username" type="text" autocomplete="username" autocapitalize="none" spellcheck="false" required>
<label for="password">密码</label>
<input id="password" name="password" type="password" autocomplete="current-password" required>
<button class="primary" type="submit">绑定并进入</button>
</form></main></body></html>`;
}

const esc = (s) => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return new URLSearchParams(Buffer.concat(chunks).toString());
}

/* ---- 挂载：返回路由处理器集合；配置不全时抛错（fail-closed，调用方拒启） ---- */
export function createOidcRp({ AUTH, usersFile, env = process.env }) {
  const enabled = env.WS_OIDC_ENABLED === '1';
  const issuer = env.WS_OIDC_ISSUER || '';
  const clientId = env.WS_OIDC_CLIENT_ID || '';
  const clientSecret = env.WS_OIDC_CLIENT_SECRET || '';
  const redirectUri = env.WS_OIDC_REDIRECT_URI || '';
  const linksFile = env.WS_OIDC_LINKS_FILE || (usersFile ? join(dirname(usersFile), 'oidc-links.json') : '');

  if (!enabled) return { enabled: false };
  if (!issuer || !clientId || !clientSecret || !redirectUri || !linksFile) {
    throw new Error('[oidc] WS_OIDC_ENABLED=1 但 ISSUER/CLIENT_ID/CLIENT_SECRET/REDIRECT_URI/LINKS_FILE 配置不完整——拒绝以半配置状态启动');
  }
  if (!AUTH || !AUTH.status().enabled) {
    throw new Error('[oidc] 门禁未启用时统一登录没有可绑定的本地账号——先配置 WS_AUTH_* 再启用 WS_OIDC_*');
  }

  const discoveryCache = { value: null };
  async function discovery() {
    if (!discoveryCache.value) discoveryCache.value = await discover(issuer);
    return discoveryCache.value;
  }

  function mintSessionCookie(res, token, protoHttps) {
    res.setHeader('set-cookie', AUTH.cookieFor(token, protoHttps));
  }

  return {
    enabled: true,
    /* GET /api/oidc/start */
    async start(res) {
      prune(pending);
      const state = crypto.randomBytes(16).toString('base64url');
      const nonce = crypto.randomBytes(16).toString('base64url');
      const verifier = crypto.randomBytes(32).toString('base64url');
      pending.set(state, { nonce, verifier, created_at: Date.now() });
      const d = await discovery();
      const url = new URL(d.authorization_endpoint);
      url.searchParams.set('client_id', clientId);
      url.searchParams.set('redirect_uri', redirectUri);
      url.searchParams.set('response_type', 'code');
      url.searchParams.set('scope', 'openid profile');
      url.searchParams.set('state', state);
      url.searchParams.set('nonce', nonce);
      url.searchParams.set('code_challenge', crypto.createHash('sha256').update(verifier).digest('base64url'));
      url.searchParams.set('code_challenge_method', 'S256');
      res.writeHead(302, { location: url.toString(), 'cache-control': 'no-store' });
      res.end();
    },
    /* GET /api/oidc/callback */
    async callback(req, res, protoHttps) {
      try {
        const params = new URL(req.url, 'http://x').searchParams;
        const state = params.get('state') || '';
        const entry = pending.get(state);
        if (!entry) return jsonErr(res, 400, '登录会话无效或已过期，请重新点击统一登录。');
        pending.delete(state);
        if (Date.now() - entry.created_at > PENDING_TTL_MS) return jsonErr(res, 400, '登录会话已过期，请重新点击统一登录。');
        const code = params.get('code') || '';
        if (!code) return jsonErr(res, 400, '授权码缺失，请重新登录。');
        const token = await exchangeCode(await discovery(), {
          clientId, clientSecret, redirectUri, code, verifier: entry.verifier,
        });
        // iss/aud/exp/nonce 与签名全部在此校验，失败即抛
        const claims = await verifyIdToken(token.id_token, { issuer, clientId, nonce: entry.nonce });
        const sub = String(claims.sub);
        const links = loadLinks(linksFile);
        const link = links[sub];
        if (link && typeof link.user_id === 'string') {
          // 链接命中：与手工登录同一会话签发路径（AUTH.mint——uid 存在性由 sessionOf 复验）
          const token = AUTH.mint(link.user_id);
          const s = AUTH.sessionOf(token);
          if (!s.ok) return jsonErr(res, 403, '绑定的门禁账号已不存在，请联系维护者。');
          mintSessionCookie(res, token, protoHttps);
          res.writeHead(302, { location: '/', 'cache-control': 'no-store' });
          return res.end();
        }
        prune(binds);
        const bindToken = crypto.randomBytes(24).toString('hex');
        binds.set(bindToken, { sub, name: String(claims.name || ''), created_at: Date.now() });
        res.writeHead(302, { location: '/oidc/bind?bind=' + bindToken, 'cache-control': 'no-store' });
        res.end();
      } catch (err) {
        console.log(`${new Date().toISOString()} oidc callback error: ${err && err.message}`);
        return jsonErr(res, 503, '统一登录暂时不可用，请稍后再试或用账号密码登录。');
      }
    },
    /* GET /oidc/bind */
    bindPage(req, res) {
      const bindToken = String(new URL(req.url, 'http://x').searchParams.get('bind') || '');
      if (!binds.has(bindToken)) {
        res.writeHead(400, { 'content-type': 'text/html; charset=utf-8' });
        return res.end('<!doctype html><meta charset="utf-8"><p>绑定会话无效或已过期，请重新点击统一登录。</p><p><a href="/login">返回登录</a></p>');
      }
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(bindPageHtml(esc(bindToken), esc));
    },
    /* POST /api/oidc/bind */
    async bind(req, res, protoHttps) {
      try {
        prune(binds);
        const body = await readBody(req);
        const bindToken = String(body.get('bind') || '');
        const entry = binds.get(bindToken);
        if (!entry) return jsonErr(res, 400, '绑定会话已过期，请重新点击统一登录。');
        const username = String(body.get('username') || '').trim();
        const password = String(body.get('password') || '');
        if (!username || !password) return jsonErr(res, 400, '请填写门禁账号和密码。');
        const r = AUTH.login(username, password);
        if (!r.ok) return json(res, 401, { error: 'bad_credentials', message: '账号或密码不正确。' });
        // 防串绑：这个门禁账号已绑过别的统一身份 → 拒绝（先解绑再换）
        const links = loadLinks(linksFile);
        for (const [existingSub, l] of Object.entries(links)) {
          if (l.user_id === r.uid && existingSub !== entry.sub) {
            return json(res, 409, { error: 'already_linked', message: '这个空间已绑定过统一身份。如需更换，请先解绑。' });
          }
        }
        links[entry.sub] = { user_id: r.uid, bound_at: new Date().toISOString(), bound_via: 'local_password_proof' };
        saveLinks(linksFile, links);
        binds.delete(bindToken);
        mintSessionCookie(res, r.token, protoHttps);
        res.writeHead(302, { location: '/', 'cache-control': 'no-store' });
        res.end();
      } catch (err) {
        console.log(`${new Date().toISOString()} oidc bind error: ${err && err.message}`);
        return jsonErr(res, 503, '统一登录暂时不可用，请稍后再试。');
      }
    },
  };
}

function json(res, status, obj) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}
function jsonErr(res, status, message) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify({ error: 'oidc_error', message }));
}
