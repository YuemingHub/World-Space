/* 运行时模型凭据覆盖层（World Space 侧）——2026-11-03。
 *
 * 目的与 Self Space 同：统一管理台改完即生效、重启后仍在，密钥不进仓库、不进 env。
 * 覆盖文件默认落在预算状态文件同目录（/opt/world-space/shared/data，服务用户私有），
 * mode 0600；启动时命中才覆盖 CFG 的 llm 三项，没写过覆盖的环境行为不变。
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FILE = process.env.WS_RUNTIME_CONFIG_FILE
  || path.join(path.dirname(process.env.WS_STATE_FILE || path.join(HERE, '..', 'var', 'budget.json')), 'runtime-config.json');

function readConfig() {
  try {
    return JSON.parse(fs.readFileSync(FILE, 'utf8'));
  } catch (err) {
    if (err.code === 'ENOENT') return {};
    throw err;
  }
}

function writeConfig(value) {
  fs.mkdirSync(path.dirname(FILE), { recursive: true });
  const tmp = FILE + '.tmp.' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2), { mode: 0o600 });
  try { fs.chmodSync(tmp, 0o600); } catch (_) { /* umask 已满足时失败无害 */ }
  try {
    fs.renameSync(tmp, FILE);
  } catch (_) {
    fs.copyFileSync(tmp, FILE);
    try { fs.unlinkSync(tmp); } catch (_) { /* 残留临时文件无害 */ }
  }
  try { fs.chmodSync(FILE, 0o600); } catch (_) { /* 同上 */ }
}

export function loadLlmOverrides() {
  try {
    const llm = (readConfig() || {}).llm || {};
    const out = {};
    for (const field of ['base_url', 'model', 'api_key']) {
      if (typeof llm[field] === 'string' && llm[field]) out[field] = llm[field];
    }
    return out;
  } catch (err) {
    console.error(new Date().toISOString() + ' runtime-config 读取失败，按 env 运行 code=' + (err.code || err.message));
    return {};
  }
}

function fingerprint(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex').slice(0, 10);
}

export function llmView(CFG) {
  let llm = {};
  try { llm = (readConfig() || {}).llm || {}; } catch (_) { /* 读取失败按 env 展示 */ }
  return {
    base_url: CFG.llmBase,
    model: CFG.llmModel,
    key_configured: Boolean(CFG.llmKey),
    key_fingerprint: CFG.llmKey ? fingerprint(CFG.llmKey) : '',
    source: Object.keys(llm).length ? 'override' : 'env',
    updated_at: llm.updated_at || null,
  };
}

function validate(patch) {
  const input = patch && typeof patch === 'object' ? patch : {};
  const out = {};

  if (input.base_url !== undefined) {
    const raw = String(input.base_url || '').trim();
    if (!raw) return { ok: false, error: 'base_url_required' };
    if (raw.length > 300) return { ok: false, error: 'base_url_too_long' };
    let parsed;
    try { parsed = new URL(raw); } catch (_) { return { ok: false, error: 'base_url_invalid' }; }
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return { ok: false, error: 'base_url_invalid' };
    if (parsed.username || parsed.password) return { ok: false, error: 'base_url_must_not_embed_credentials' };
    out.base_url = raw.replace(/\/+$/, '');
  }

  if (input.model !== undefined) {
    const raw = String(input.model || '').trim();
    if (!raw) return { ok: false, error: 'model_required' };
    if (raw.length > 100) return { ok: false, error: 'model_too_long' };
    if (/[\u0000-\u001f\u007f]/.test(raw)) return { ok: false, error: 'model_invalid' };
    out.model = raw;
  }

  if (input.api_key !== undefined && String(input.api_key || '') !== '') {
    const raw = String(input.api_key).trim();
    if (raw.length > 400) return { ok: false, error: 'api_key_too_long' };
    if (/\s/.test(raw)) return { ok: false, error: 'api_key_must_not_contain_whitespace' };
    out.api_key = raw;
  }

  if (!Object.keys(out).length) return { ok: false, error: 'nothing_to_update' };
  return { ok: true, value: out };
}

export function applyLlm(CFG, patch) {
  const checked = validate(patch);
  if (!checked.ok) return checked;

  let config;
  try {
    config = readConfig() || {};
  } catch (_) {
    return { ok: false, error: 'runtime_config_unreadable' };
  }

  const llm = Object.assign({}, config.llm, checked.value, { updated_at: new Date().toISOString() });
  try {
    writeConfig(Object.assign({}, config, { llm }));
  } catch (_) {
    return { ok: false, error: 'runtime_config_write_failed' };
  }

  if (llm.base_url) CFG.llmBase = llm.base_url.replace(/\/$/, '');
  if (llm.model) CFG.llmModel = llm.model;
  if (llm.api_key) CFG.llmKey = llm.api_key;
  return { ok: true, llm: llmView(CFG) };
}
