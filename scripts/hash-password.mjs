/*
 * 运维小工具：生成一条可放进服务器私有用户文件（JSON）的记录。
 * 密码不进命令行参数（会留在 shell 历史），从 stdin 读入：
 *   node scripts/hash-password.mjs <user_id> <username> < users/password.txt
 * 或运行后手动输入一行密码再按回车。输出直接粘贴进用户文件的 users 数组。
 * 服务器上的用户文件路径由部署约定（仓库外），仓库里永远只有本工具，没有真实密码。
 */
import { hashPassword } from '../server/auth.mjs';

const [uid, username] = process.argv.slice(2);
if (!uid || !username || !/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,31}$/.test(uid)) {
  console.error('用法：node scripts/hash-password.mjs <user_id> <username>   （密码从 stdin 读一行；user_id 仅限字母数字_-）');
  process.exit(2);
}
let pw = '';
process.stdin.setEncoding('utf8');
for await (const chunk of process.stdin) pw += chunk;
pw = pw.replace(/\r?\n$/, '');
if (pw.length < 8) { console.error('密码至少 8 个字符，未生成。'); process.exit(2); }
console.log(JSON.stringify({ user_id: uid, username, password_hash: hashPassword(pw) }));
