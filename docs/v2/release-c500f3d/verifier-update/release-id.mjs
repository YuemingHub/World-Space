#!/usr/bin/env node
// release-id.mjs —— 从一棵**已验证等于批准提交**的发布树算出发布身份摘要。
//
// 与 server/world.mjs 里的 computeReleaseId() 必须逐字同口径（v1）：
//   sha256("world-release-tree-v1\n" + Σ sorted(relpath + "\0" + sha256hex(file) + "\n"))
// 排除：.git、node_modules、var（运行期账本）。发布树由 git archive 展开，
// 只会含提交里的文件；运行期写入的 var/ 必须排除，否则重启一次身份就变。
// 这不是"工具自己声明一个 SHA"，而是对批准产物做内容测量；运行中的进程对自己的树做同一测量，
// 两者相等才说明"正在服务的就是批准的这份字节"。
//
// 用法：node release-id.mjs <release-tree-dir>
//   成功：stdout 打印 64 位小写 hex
//   失败：stderr 说明原因，退出码 2（调用方必须按失败处理，不许拿空输出当身份）
import crypto from 'node:crypto';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const SCHEME = 'world-release-tree-v1';
const root = process.argv[2];
if (!root) { console.error('USAGE: release-id.mjs <release-tree-dir>'); process.exit(2); }
try { if (!statSync(root).isDirectory()) throw new Error('not a directory'); }
catch (e) { console.error(`RELEASE_ID_ERROR 目录不可读：${root}（${e.message}）`); process.exit(2); }

const files = [];
function walk(dir, rel) {
  let ents;
  try { ents = readdirSync(dir, { withFileTypes: true }); }
  catch (e) { throw new Error(`读不了 ${dir}：${e.message}`); }
  ents.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const ent of ents) {
    const r = rel ? rel + '/' + ent.name : ent.name;
    const top = r.split('/')[0];
    if (top === '.git' || top === 'node_modules' || top === 'var') continue;
    if (ent.isDirectory()) walk(join(dir, ent.name), r);
    else if (ent.isFile()) files.push(r);
    else { console.error(`RELEASE_ID_ERROR 发布树含非普通文件：${r}`); process.exit(2); }
  }
}
try {
  walk(root, '');
  files.sort();
  const h = crypto.createHash('sha256');
  h.update(SCHEME + '\n');
  for (const f of files) {
    h.update(f); h.update('\0');
    h.update(crypto.createHash('sha256').update(readFileSync(join(root, f))).digest('hex'));
    h.update('\n');
  }
  process.stdout.write(h.digest('hex') + '\n');
} catch (e) {
  console.error(`RELEASE_ID_ERROR ${e.message}`);
  process.exit(2);
}
