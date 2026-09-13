/*
 * R3 日期真源回归。业务日期只有 server/date.mjs 一个来源：
 *   1. 时区边界：Asia/Shanghai 00:30 的业务日期必须是当天（2026-09-13），不能得到前一天的
 *      checked_at / 预算日——用同一时刻的 UTC 日期字段当负控（旧 UTC 实现就会给前一天）；
 *   2. UTC 主机上业务日期跟主机时区走：全仓库一个语义，不是两套"今天"；
 *   3. guard 的 checked_at 与运行时预算的"今天"同源（都来自 localDate）；
 *   4. 静态残留检查：server/** 不允许再出现 toISOString().slice(0,10) 这类第二套"今天"。
 */
import { spawn } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { localDate } from '../server/date.mjs';
import { evidenceTable } from '../server/evidence.mjs';
import { guard } from '../server/guard.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (n, c, d) => { console.log(`${c ? '✓' : '✗'} ${n}${c || !d ? '' : ' —— ' + d}`); if (!c) failures++; };

function probe(tz, instants) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [join(HERE, 'date-selftest.child.mjs'), ...instants], {
      env: Object.assign({}, process.env, { TZ: tz }), stdio: ['ignore', 'pipe', 'pipe'],
    });
    let buf = '', err = '';
    child.stdout.on('data', d => buf += d);
    child.stderr.on('data', d => err += d);
    child.on('close', code => code === 0 ? resolve(JSON.parse(buf)) : reject(new Error(err || ('exit ' + code))));
  });
}

// 1. 上海时区的时区边界
{
  const rows = await probe('Asia/Shanghai', [
    '2026-09-13T00:30:00+08:00', '2026-09-13T07:59:59+08:00',
    '2026-09-13T08:00:01+08:00', '2026-09-13T23:59:59+08:00',
  ]);
  ok('上海 00:30 → 业务日期 = 当天（不是前一天）', rows[0].local === '2026-09-13', JSON.stringify(rows[0]));
  ok('负控：该时刻的 UTC 日期确实是前一天（证明不是恒等断言）', rows[0].utc === '2026-09-12', JSON.stringify(rows[0]));
  ok('上海 07:59:59 → 当天（旧 UTC 实现在此 8 小时窗口给昨天）', rows[1].local === '2026-09-13', JSON.stringify(rows[1]));
  ok('上海 08:00:01 → 当天', rows[2].local === '2026-09-13', JSON.stringify(rows[2]));
  ok('上海 23:59:59 → 当天', rows[3].local === '2026-09-13', JSON.stringify(rows[3]));
}
// 2. UTC 主机：业务日界 = 主机时区日界（单一语义）
{
  const rows = await probe('UTC', ['2026-09-13T00:30:00+08:00']);
  ok('UTC 主机同一时刻 → 业务日期 = 主机当天（语义一致，不藏在代码里第二套）', rows[0].local === '2026-09-12' && rows[0].utc === '2026-09-12', JSON.stringify(rows[0]));
}
// 3. guard checked_at 与 localDate() 同源
{
  const ev = evidenceTable([{ title: '官方原文', url: 'https://synthetic-date-test.gov.cn/doc', snippet: '正文', published_at: '2026-01-01' }]);
  const g = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null,
    resources: [{ name: '入口', type: 'government', why: '查办理入口', claim: '该平台受理相关事项', evidence_id: 'e1', confidence: 'high' }],
    uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, ev);
  ok('guard checked_at 与 localDate() 同源', g.resources.length === 1 && g.resources[0].checked_at === localDate(),
    `checked_at=${g.resources[0] && g.resources[0].checked_at} localDate=${localDate()}`);
}
// 4. 静态残留：server/** 不许再有第二套"今天"
{
  const offenders = [];
  for (const f of readdirSync(join(HERE, '..', 'server'))) {
    if (!f.endsWith('.mjs')) continue;
    readFileSync(join(HERE, '..', 'server', f), 'utf8').split('\n').forEach((line, i) => {
      if (/toISOString\(\)\.slice\(0,\s*(7|10)\)/.test(line) || /function today\(\)/.test(line) || /function thisMonth\(\)/.test(line)) {
        offenders.push(`server/${f}:${i + 1}`);
      }
    });
  }
  ok('server/** 无第二套"今天"（UTC 切片 / 本地 today 残留 = 0）', offenders.length === 0, offenders.join(', '));
}

console.log(failures ? `\n失败 ${failures} 项` : '\n日期真源回归全部通过');
process.exitCode = failures ? 1 : 0;
