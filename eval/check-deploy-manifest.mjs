// 只读自检：文档里的 10 行 blob 哈希是否与 git HEAD 实测逐行一致（可重复运行）
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const c = readFileSync('docs/ai-beginner/DEPLOY-AI-ROUTE.md', 'utf8');
const re = /^\| \d+ \| `([^`]+)` \| `([0-9a-f]{40})` \|$/gm;
const rows = [...c.matchAll(re)];
let bad = 0;
for (const m of rows) {
  const real = execSync(`git rev-parse HEAD:web/ai/${m[1]}`, { encoding: 'utf8' }).trim();
  if (real !== m[2]) { bad++; console.log('MISMATCH', m[1], 'doc=', m[2], 'git=', real); }
}
console.log(`rows=${rows.length} mismatch=${bad}`);
process.exit(bad === 0 && rows.length === 10 ? 0 : 1);
