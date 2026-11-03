#!/usr/bin/env node
// face-probe.mjs —— 从提交里的代码判断"这份发布有没有内部诊断面"。
//
// 旧实现是 `grep -c opsPort`：一行注释就能把它骗成 dual_face，从而放过本该
// 在写入前中止的 LEGACY_AS_UPGRADE（Deep 复核 P8）。这里先去掉注释与字符串字面量，
// 再找**代码里真实出现的**诊断面标记。运行期仍由 ws-verify-faces.sh 按实际面判定，
// 这个静态探针只负责"别让注释/字符串冒充能力"。
//
// 用法：node face-probe.mjs <server/world.mjs 路径> [identity]
// 输出（默认）：dual_face | legacy_single_face
// 输出（identity）：identity_v1 | no_identity —— 目标代码是否自带发布身份测量
// 退出码：0 有结论；2 读不到文件
import { readFileSync } from 'node:fs';

const f = process.argv[2];
const mode = process.argv[3] || 'face';
if (!f) { console.error('USAGE: face-probe.mjs <world.mjs> [identity]'); process.exit(2); }
let s;
try { s = readFileSync(f, 'utf8'); } catch (e) { console.error(`FACE_PROBE_ERROR ${e.message}`); process.exit(2); }

// 去掉字符串字面量（含模板串）与注释。顺序：先字符串、再块注释、再行注释。
// 这不是完整的 JS 词法器，但足以让"注释/字符串里的标记"不再被当成代码能力；
// 运行期核验器仍然是权威判定（静态探针只影响预检方向）。
s = s.replace(/`(?:[^`\\]|\\.)*`/g, '``')
     .replace(/'(?:[^'\\\n]|\\.)*'/g, "''")
     .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
     .replace(/\/\*[\s\S]*?\*\//g, ' ')
     .replace(/\/\/[^\n]*/g, ' ');

// 真实能力证据：读取 WS_OPS_PORT 配置 + 实际 createServer/listen 诊断口。
// 只认代码 token，不认注释/字符串。
const hasOpsConfig = /WS_OPS_PORT/.test(s);
const hasOpsServer = /createServer/.test(s) && /\.listen\s*\(/.test(s);
if (mode === 'identity') {
  // 代码里真有"对自身发布树做测量"的实现（不是注释/字符串里的字样）
  const hasIdentity = /computeReleaseId/.test(s) && /RELEASE_ID_SCHEME/.test(s);
  process.stdout.write(hasIdentity ? 'identity_v1\n' : 'no_identity\n');
} else {
  process.stdout.write(hasOpsConfig && hasOpsServer ? 'dual_face\n' : 'legacy_single_face\n');
}
