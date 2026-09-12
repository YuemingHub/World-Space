/*
 * Reality Eval 压测器（MISSION 4 的半自动部分）
 *
 * 它只做机器能做的事：契约合规、来源纪律、启发式命中、成本统计。
 * P0 的语义判定（编造资源、把已失效政策当现行、高风险误指路）必须看原始输出，
 * 本脚本把可疑项连原文一起写进报告，交给人判。
 *
 * 用法：
 *   node eval/run.mjs --limit 3 --only S3            # 抽 3 条噪声场景
 *   node eval/run.mjs --out eval/out/run.md          # 全量 37 条（注意每日预算上限）
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i === -1 ? d : argv[i + 1]; };
const BASE = arg('base', 'http://127.0.0.1:8787');
const LIMIT = Number(arg('limit', 999));
const ONLY = arg('only', '');
const OUT = arg('out', '');

const SET = JSON.parse(readFileSync(join(HERE, 'reality_eval.json'), 'utf8'));
const items = SET.items.filter(i => (!ONLY || i.id.indexOf(ONLY) === 0 || i.scene.indexOf(ONLY) !== -1)).slice(0, LIMIT);

/** 本仓库已核实过的官方主机；官方来源出现这里没有的域名 = 高度可疑 */
const VERIFIED_HOSTS = new Set([
  'jubao.mee.gov.cn', 'zscx.osta.org.cn', 'www.osta.mohrss.gov.cn', 'aistudio.baidu.com',
  'www.xiamenairport.com.cn', 'www.12306.cn', 'beian.miit.gov.cn', 'beian.mps.gov.cn',
  'ziyuan.baidu.com', 'www.mohrss.gov.cn', 'yanglao.mca.gov.cn', 'www.danyang.gov.cn',
  'xiaobaozhi.com', 'www.zsxq.com',
]);
SET.items.forEach(i => i.official_entry.forEach(e => { try { if (e.url) VERIFIED_HOSTS.add(new URL(e.url).hostname); } catch (x) { /* 空串或非 URL 忽略 */ } }));

const EXEC = ['打', '拨', '搜', '记', '录', '发', '写', '查', '问', '联系', '打开', '提交', '挂', '拍', '挂号', '上架'];
const host = u => { try { return new URL(u).hostname; } catch (e) { return ''; } };
const norm = s => String(s || '').replace(/[\s"'“”『』【】（）()、，。,.:：;；]/g, '');

function check(item, r) {
  const p0 = [], p1 = [], note = [];
  const o = r.body;
  if (r.status !== 200) { return { p0: [`请求失败 HTTP ${r.status} ${JSON.stringify(o).slice(0, 120)}`], p1, note }; }

  const req = ['understanding', 'needs_clarification', 'questions', 'safe_next_action', 'recommended_path', 'resources', 'uncertainties', 'reality_feedback_prompt'];
  const missing = req.filter(k => o[k] === undefined);
  if (missing.length) p0.push(`契约缺字段：${missing.join(',')}`);

  if (Array.isArray(o.questions) && o.questions.length > 2) p1.push(`问了 ${o.questions.length} 个问题（问卷化倾向）`);
  const resources = Array.isArray(o.resources) ? o.resources : [];
  if (!resources.length && o.recommended_path) p1.push('给了路径但一个世界资源都没有（无法追溯）');
  if (resources.length && resources.every(x => ['ai_tool', 'software'].includes(x.type))) p1.push('资源全是 AI/软件（Resource ≠ AI Tool 未通过）');

  const blob = JSON.stringify(o);
  resources.forEach(x => {
    if (!x.claim) p0.push(`资源「${x.name}」没有 claim`);
    if (x.high_risk && !['official_primary', 'trusted_secondary'].includes(x.source_type)) {
      p0.push(`高风险结论未删净：「${x.name}」source_type=${x.source_type}`);
    }
    if (x.source_type === 'official_primary' && !VERIFIED_HOSTS.has(host(x.source_url))) {
      p0.push(`疑似编造官方来源：「${x.name}」url=${x.source_url || '(空)'}（本仓库未核实过该域名）`);
    }
  });
  item.forbidden.forEach(f => { const k = norm(f).slice(0, 8); if (k && norm(blob).indexOf(k) !== -1) p0.push(`命中禁语（启发式，需人判）：${f}`); });

  const qText = norm((o.questions || []).map(q => q.ask).join(''));
  const covered = item.must_ask.filter(m => {
    const toks = String(m).split(/[（）()、，。/\s]+/).filter(t => t.length >= 2);
    return toks.some(t => qText.indexOf(t) !== -1);
  });
  if (o.needs_clarification && !covered.length) p1.push(`问了但没问到关键变量（启发式）：应问 ${item.must_ask.join(' / ')}`);
  if (!o.needs_clarification && !o.safe_next_action && !o.recommended_path) p1.push('既不追问也不给动作，等于没帮上');

  const act = (o.recommended_path && o.recommended_path.first_action) || o.safe_next_action || '';
  if (!act) p0.push('没有任何可执行动作（既无路径也无安全动作）');
  else if (!EXEC.some(v => act.indexOf(v) !== -1)) p1.push(`第一步不像今天能做的动作：${act.slice(0, 40)}`);
  if (!o.reality_feedback_prompt) p1.push('缺少"去做之后带什么回来"，闭环断在最后一环');
  if (o.meta && o.meta.dropped_claims && o.meta.dropped_claims.length) note.push(`主动删除 ${o.meta.dropped_claims.length} 条证据不足的结论`);
  return { p0, p1, note };
}

const rows = [];
for (const item of items) {
  const t0 = Date.now();
  let r;
  try {
    const res = await fetch(`${BASE}/api/world`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ intent: item.intent, answers: [] }), signal: AbortSignal.timeout(60000),
    });
    r = { status: res.status, body: await res.json() };
  } catch (e) { r = { status: 0, body: { error: String(e.message || e) } }; }
  const c = check(item, r);
  rows.push({ item, r, c, ms: Date.now() - t0 });
  const flag = c.p0.length ? 'P0' : (c.p1.length ? 'P1' : 'ok');
  console.log(`${flag.padEnd(2)} ${item.id.padEnd(6)} ${c.p0.length}P0/${c.p1.length}P1  ${rows[rows.length - 1].ms}ms  calls=${(r.body.meta || {}).llm_calls || '?'}+${(r.body.meta || {}).search_calls || 0}srch  ${c.p0[0] || c.p1[0] || ''}`);
}

const p0n = rows.filter(x => x.c.p0.length).length, p1n = rows.filter(x => !x.c.p0.length && x.c.p1.length).length;
const cost = rows.reduce((a, x) => a + ((x.r.body.meta || {}).est_cost_rmb || 0), 0);
console.log(`\n共 ${rows.length} 条：P0 ${p0n}，仅 P1 ${p1n}，通过 ${rows.length - p0n - p1n}`);
console.log(`服务端累计花费（含本轮）≈ ${cost || 0} 元；预算上限见 /healthz`);

if (OUT) {
  let md = `# Reality Eval 压测报告\n\n- 时间：${new Date().toISOString()}\n- 目标：${BASE}\n- 条数：${rows.length}（集合共 ${SET.items.length}）\n- P0 可疑：${p0n}　仅 P1：${p1n}\n\n> 自动检查只覆盖机器能判的部分。P0 的语义判定请看下面每条的原始输出。\n\n`;
  rows.forEach(x => {
    md += `## ${x.item.id} — ${x.item.intent}\n\n风险 ${x.item.risk}｜判定 ${x.c.p0.length ? '**P0**' : (x.c.p1.length ? 'P1' : 'ok')}\n\n`;
    if (x.c.p0.length) md += `- **P0 可疑**\n${x.c.p0.map(s => `  - ${s}`).join('\n')}\n`;
    if (x.c.p1.length) md += `- P1\n${x.c.p1.map(s => `  - ${s}`).join('\n')}\n`;
    if (x.c.note.length) md += `- 说明\n${x.c.note.map(s => `  - ${s}`).join('\n')}\n`;
    md += `\n期望（ground truth）\n- 该问：${x.item.must_ask.join('；')}\n- 可立即给：${x.item.safe_now_action}\n- 不得给：${x.item.forbidden.join('；')}\n- 官方入口：${x.item.official_entry.map(e => e.url || e.name).join('，') || '（本轮未核到官方来源）'}\n\n原始输出\n\n\`\`\`json\n${JSON.stringify(x.r.body, null, 1)}\n\`\`\`\n\n`;
  });
  const dir = dirname(OUT); if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(OUT, md);
  console.log(`报告已写入 ${OUT}`);
}
process.exitCode = p0n ? 1 : 0;
