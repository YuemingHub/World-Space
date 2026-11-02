/*
 * catalog-selftest —— 资源目录（catalog/resources.json）的字段与时效校验。
 *
 * 为什么需要它：M4 要求资源记录含 能力说明/适用场景/官方来源/使用门槛/费用/局限/
 * 隐私条件/最后核验时间/替代能力。没有装置，字段会随改动悄悄丢失、过期资源会留在目录里。
 *
 * 判据（任一失败 = FAIL）：
 *   1 顶层 version 是 x.y.z、entries ≥ 1
 *   2 每条必备字段齐全（含 M4 新增 privacy / child_suitability / alternatives / reachability）
 *   3 privacy 三字段齐全；child_suitability 是枚举值
 *   4 alternatives 只指向目录内其他 id，且不含自己
 *   5 reachability.checked_at 是 ISO 日期；http_status 是数字（429/405 这类 bot 盾也合法）
 *   6 last_reviewed_at 在 180 天内（过期 = 该条需要重新核验，先报 STALE）
 *   7 used_in 非空，且不含已退役的 V1 面板 id（goal-*-panel）
 *
 * 用法：node eval/catalog-selftest.mjs
 */
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const FILE = join(HERE, '..', 'catalog', 'resources.json');
const DAY = 86400000;
const STALE_DAYS = 180;
let total = 0, fails = 0;
const ok = (n, c, d) => { total++; console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) fails++; };

let cat;
try { cat = JSON.parse(readFileSync(FILE, 'utf8')); }
catch (e) { console.error('✗ 目录无法解析: ' + e.message); process.exit(1); }

ok('version 形状 x.y.z', /^\d+\.\d+\.\d+$/.test(String(cat.version || '')), String(cat.version));
ok('entries ≥ 1', Array.isArray(cat.resources) && cat.resources.length >= 1, String(cat.resources && cat.resources.length));

const ids = new Set((cat.resources || []).map(r => r.id));
const REQUIRED = ['id', 'name', 'one_line', 'official_url', 'source_urls', 'license', 'maintenance_status',
  'difficulty', 'cost_category', 'requires_api_key', 'china_accessibility', 'best_for', 'not_for',
  'why_selected', 'used_in', 'last_reviewed_at', 'privacy', 'child_suitability', 'alternatives', 'reachability'];
const CHILD = new Set(['child_ok', 'with_parent', 'not_for_child', 'unknown']);

for (const r of cat.resources || []) {
  const tag = r.id || '(no id)';
  for (const k of REQUIRED) ok(`${tag} 有 ${k}`, k in r && r[k] !== undefined && r[k] !== null, '');
  const p = r.privacy || {};
  ok(`${tag} privacy.data_destination`, typeof p.data_destination === 'string' && p.data_destination.length > 0);
  ok(`${tag} privacy.account_required 是布尔`, typeof p.account_required === 'boolean');
  ok(`${tag} privacy.child_note`, typeof p.child_note === 'string' && p.child_note.length > 0);
  ok(`${tag} child_suitability 枚举`, CHILD.has(r.child_suitability), String(r.child_suitability));
  const alts = Array.isArray(r.alternatives) ? r.alternatives : null;
  ok(`${tag} alternatives 是数组`, !!alts);
  if (alts) {
    ok(`${tag} alternatives 不含自己`, !alts.includes(r.id));
    ok(`${tag} alternatives 都在目录内`, alts.every(a => ids.has(a)), alts.join(','));
  }
  const reach = r.reachability || {};
  ok(`${tag} reachability.checked_at ISO 日期`, /^\d{4}-\d{2}-\d{2}$/.test(String(reach.checked_at || '')), String(reach.checked_at));
  ok(`${tag} reachability.http_status 数字`, typeof reach.http_status === 'number', String(reach.http_status));
  ok(`${tag} last_reviewed_at ISO 日期`, /^\d{4}-\d{2}-\d{2}$/.test(String(r.last_reviewed_at || '')), String(r.last_reviewed_at));
  const age = (Date.now() - Date.parse(r.last_reviewed_at + 'T00:00:00Z')) / DAY;
  ok(`${tag} 未过期（<${STALE_DAYS} 天，实际 ${Math.floor(age)} 天）`, age >= 0 && age < STALE_DAYS, String(r.last_reviewed_at));
  const used = Array.isArray(r.used_in) ? r.used_in : [];
  ok(`${tag} used_in 非空`, used.length > 0);
  ok(`${tag} used_in 不含退役 V1 面板 id`, !used.some(u => /^goal-.*-panel$/.test(u)), used.join(','));
}

console.log(`\nCATALOG_SELFTEST_TOTAL=${total}  FAILS=${fails}`);
console.log(fails === 0 ? 'CATALOG_SELFTEST=PASS' : 'CATALOG_SELFTEST=FAIL');
process.exit(fails === 0 ? 0 : 1);