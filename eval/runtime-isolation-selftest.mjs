/*
 * 生产运行时隔离 Gate（P0-2）。静态文件扫描，不做依赖分析——足够简单就够用。
 * 规则：生产运行路径（server/**、config/**、web/**）里任何文件都不得出现
 * 评测数据的路径级引用（eval/、reality_eval、pilot12、docs/v2）。
 * 评测数据只能当裁判，绝不能成为运行时的来源库 / 授权表 / 检索提示 / 提示词上下文 / 兜底数据库。
 * 违规即失败，并输出 PRODUCTION_RUNTIME_REFERENCES_EVAL_DATA。
 */
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const FORBIDDEN = [/eval\//, /reality_eval/, /pilot12/, /docs\/v2/];
const SCAN_DIRS = ['server', 'config', 'web'].map(d => join(ROOT, d)).filter(existsSync);

function walk(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, acc);
    else acc.push(p);
  }
  return acc;
}

const hits = [];
let scanned = 0;
for (const dir of SCAN_DIRS) {
  for (const file of walk(dir)) {
    scanned++;
    const text = readFileSync(file, 'utf8');
    text.split('\n').forEach((line, i) => {
      if (FORBIDDEN.some(re => re.test(line))) hits.push(`${file}:${i + 1}: ${line.trim().slice(0, 120)}`);
    });
  }
}

if (hits.length) {
  console.log('PRODUCTION_RUNTIME_REFERENCES_EVAL_DATA —— 生产运行路径引用了评测数据：');
  hits.forEach(h => console.log('  ' + h));
  console.log(`\n失败（扫描 ${scanned} 个文件）。评测集只能当裁判，运行时不得引用。`);
  process.exitCode = 1;
} else {
  console.log(`✓ 生产运行路径 → 评测数据 引用数 = 0（隔离 Gate，扫描 server/config/web 共 ${scanned} 个文件）`);
}
