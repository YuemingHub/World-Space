/*
 * Outcome Loop 真实旅程驱动器 —— 对真实服务（默认 127.0.0.1:8890）逐轮发送
 * { intent, answers, receipt }，原始输入/输出全部落盘 eval/out/iter2/<name>-t<N>.json。
 * 只做驱动与留痕，不做判分；成败由人（或后续复核）看原始输出。
 * 用法：node eval/outcome-journeys.mjs --only T1   （缺省跑全部）
 */
import { writeFileSync, mkdirSync } from 'node:fs';

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i === -1 ? d : argv[i + 1]; };
const ONLY = arg('only', '');
const BASE = arg('base', 'http://127.0.0.1:8890');
const DIR = 'eval/out/iter2';
mkdirSync(DIR, { recursive: true });

const J = (name, intent, rounds) => ({ name, intent, rounds });

export const JOURNEYS = [
  J('T1-handoff', '我不是程序员，但我想找一份能大量使用 AI 的工作。', [
    {}, // t1：首轮
    { receipt: { status: 'info', text: '它说我比较适合 AI 产品运营、客户成功和内容运营这三个方向，还让我补一段自己的工作经历' } }, // t2：把外部 AI 的结果带回来
  ]),
  J('T2-human', '我们小区里面的路灯坏两个星期了。', [{}]),
  J('T3-world', '我想在附近找一家拳馆，先体验一次，不想办年卡。', [{}]),
  J('T4-stuck-switch', '我们小区里面的路灯坏两个星期了。', [
    {},
    { receipt: { status: 'stuck', text: '物业说路灯不归他们管，让我们自己去找供电局或者城管，没给任何工单' } },
  ]),
  J('T5-handoff-failed', '我不是程序员，但我想找一份能大量使用 AI 的工作。', [
    {},
    { receipt: { status: 'stuck', text: 'DeepSeek 给我的全是套话，没什么用' } },
  ]),
];

const brief = (j) => {
  const na = j.next_action || {};
  return [
    `understanding: ${j.understanding}`,
    `next_action[${na.mode || '-'}]: ${na.text || '-'}`,
    `done_when: ${na.done_when || '-'}`,
    na.handoff_task ? `handoff → ${na.handoff_target || '?'} | 任务书 ${na.handoff_task.length} 字: ${na.handoff_task.slice(0, 100)}…` : null,
    `questions: ${(j.questions || []).map(q => q.ask).join(' / ') || '-'}`,
    `resources: ${(j.resources || []).map(x => `${x.name}(${x.type},${x.source_type})`).join('、') || '-'}`,
    `path: ${j.recommended_path ? j.recommended_path.first_action : 'null'}`,
    `safe: ${j.safe_next_action || 'null'}`,
    `fb: ${j.reality_feedback_prompt}`,
    `meta: llm=${j.meta.llm_calls} search=${j.meta.search_calls} receipt=${j.meta.receipt_ingested ? j.meta.receipt_status : 'no'} guards=${(j.meta.guard_actions || []).join(',') || '-'}`,
  ].filter(Boolean).join('\n');
};

let exitBad = 0;
for (const jn of JOURNEYS) {
  if (ONLY && jn.name.indexOf(ONLY) !== 0) continue;
  console.log(`\n===== ${jn.name}：${jn.intent} =====`);
  let prev = null;
  for (let i = 0; i < jn.rounds.length; i++) {
    const body = { intent: jn.intent, answers: jn.rounds[i].answers || [] };
    if (jn.rounds[i].receipt) body.receipt = jn.rounds[i].receipt;
    const t0 = Date.now();
    let r, jj;
    try {
      r = await fetch(`${BASE}/api/world`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body), signal: AbortSignal.timeout(150000),
      });
      jj = await r.json();
    } catch (e) {
      console.log(`t${i + 1} 请求失败：${e.message}`); exitBad = 1; break;
    }
    const ms = Date.now() - t0;
    writeFileSync(`${DIR}/${jn.name}-t${i + 1}.json`, JSON.stringify({ sent: body, status: r.status, response: jj, ms }, null, 1));
    console.log(`\n--- t${i + 1}（HTTP ${r.status}，${ms}ms，${
      jj && jj.meta ? `${jj.meta.llm_calls}llm+${jj.meta.search_calls}srch` : '-'}）---`);
    if (r.status !== 200) { console.log(JSON.stringify(jj).slice(0, 300)); exitBad = 1; break; }
    console.log(brief(jj));
    if (prev && prev.next_action && jj.next_action) {
      console.log(`>> 与上一轮主行动相同？${prev.next_action.text === jj.next_action.text ? '是（疑似重答，需人工看）' : '否（已推进）'}`);
    }
    prev = jj;
  }
}
process.exitCode = exitBad;
