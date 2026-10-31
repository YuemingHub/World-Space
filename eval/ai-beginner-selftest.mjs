#!/usr/bin/env node
/*
 * AI 从零开始 · 内容契约自测（零依赖，只需 node）
 *
 * 只断言「可机械验证」的部分：文件存在、链接可解析、路径四段完整、外部入口与事实页一致、
 * 隐私面为 0（无表单/无统计/无第三方脚本）、无障碍基础。内容好不好，由独立 Checker 判断，不由本测试判断。
 *
 * 用法：node eval/ai-beginner-selftest.mjs
 * 退出码：0 全通过；1 有失败
 */
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve, normalize } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const SITE = join(ROOT, 'web', 'ai');

let pass = 0;
const fails = [];
function ok(cond, name, detail) {
  if (cond) { pass++; return; }
  fails.push({ name, detail });
}

const PAGES = [
  'index.html', 'limits.html', 'tools.html', 'safety.html',
  'paths/make-something.html', 'paths/make-a-picture.html', 'paths/find-the-facts.html'
];
const PATHS = {
  'paths/make-something.html': { steps: 4, resultWord: '真的发了出去', tool: 'https://www.doubao.com' },
  'paths/make-a-picture.html': { steps: 4, resultWord: '愿意保存在手机里', tool: 'https://www.doubao.com' },
  'paths/find-the-facts.html': { steps: 5, resultWord: '哪几点', tool: 'https://chat.deepseek.com' }
};

const html = {};
for (const p of PAGES) {
  const abs = join(SITE, p);
  ok(existsSync(abs), `页面存在：web/ai/${p}`);
  if (existsSync(abs)) html[p] = readFileSync(abs, 'utf8');
}

// 1) 站内链接全部可解析（相对路径，按目标文件所在目录解析）
for (const [p, src] of Object.entries(html)) {
  for (const m of src.matchAll(/href="([^"]+)"/g)) {
    const href = m[1];
    if (/^(https?:|mailto:|tel:|#|data:)/.test(href)) continue;
    const target = normalize(join(dirname(join(SITE, p)), href.split('#')[0]));
    ok(existsSync(target), `链接可解析：web/ai/${p} → ${href}`, `期望文件：${target}`);
  }
  for (const m of src.matchAll(/src="([^"]+)"/g)) {
    const src2 = m[1];
    if (/^(https?:|data:)/.test(src2)) continue;
    const target = normalize(join(dirname(join(SITE, p)), src2));
    ok(existsSync(target), `脚本可解析：web/ai/${p} → ${src2}`);
  }
}

// 2) 页面基础：lang、viewport、title、单一 h1
for (const [p, src] of Object.entries(html)) {
  ok(/<html lang="zh-CN">/.test(src), `lang=zh-CN：${p}`);
  ok(/name="viewport"[^>]*width=device-width/.test(src), `viewport 存在：${p}`);
  ok(/<title>[^<]{6,}<\/title>/.test(src), `title 存在：${p}`);
  ok(/<meta name="description" content="[^"]{20,}"/.test(src), `description 存在：${p}`);
  const h1 = (src.match(/<h1[\s>]/g) || []).length;
  ok(h1 === 1, `恰好一个 h1：${p}（实际 ${h1}）`);
}

// 3) 隐私面必须为 0
for (const [p, src] of Object.entries(html)) {
  ok(!/<form[\s>]/i.test(src), `无表单：${p}`);
  ok(!/<input(?![^>]*type="(checkbox|button)")/i.test(src), `无文本输入框（只允许 checkbox）：${p}`);
  ok(!/<textarea/i.test(src), `无 textarea：${p}`);
  ok(!/(fetch|XMLHttpRequest|sendBeacon|navigator\.sendBeacon)/.test(src), `页面脚本不发网络请求：${p}`);
  ok(!/<input[^>]*type="email"|<input[^>]*type="tel"/i.test(src), `无邮箱/电话输入：${p}`);
}
const js = readFileSync(join(SITE, 'assets', 'ai.js'), 'utf8');
ok(!/(fetch\(|XMLHttpRequest|sendBeacon|WebSocket|EventSource)/.test(js), 'ai.js 不含任何网络调用');
ok(/localStorage/.test(js), 'ai.js 只用本地 localStorage 记录勾选');

// 4) 外部请求必须为 0（除用户主动点击的外链）
const allSrc = Object.values(html).join('\n') + js;
ok(!/<script[^>]+src="https?:/.test(allSrc), '无第三方脚本');
ok(!/<link[^>]+href="https?:[^"]*\.css/.test(allSrc), '无第三方样式');
ok(!/@import|fonts\.googleapis/.test(allSrc), '无外部字体');
ok(!/<img[^>]+src="https?:/.test(allSrc), '无外部图片');

// 5) 三条路径：四段结构与“做成”判据
for (const [p, spec] of Object.entries(PATHS)) {
  const src = html[p] || '';
  const stages = (src.match(/class="stage"/g) || []).length;
  ok(stages >= spec.steps, `${p} 至少 ${spec.steps} 个步骤区（实际 ${stages}）`);
  ok(src.includes(spec.resultWord), `${p} 写清了「做成」的判据（含「${spec.resultWord}」）`);
  ok(/class="checkdone"/.test(src), `${p} 有可勾选的完成检查点`);
  ok((src.match(/<details class="stuck"/g) || []).length >= 1, `${p} 有「卡住了怎么办」回退路径`);
  ok((src.match(/class="saybox"/g) || []).length >= 1, `${p} 有可复制的第一句话`);
  ok(src.includes(spec.tool), `${p} 外链到实际工具 ${spec.tool}`);
  ok(/不要|不写|不上传/.test(src), `${p} 含隐私/边界提示`);
}

// 6) 首页：三条路径入口 + 首屏定位 + 安全先于工具
{
  const src = html['index.html'] || '';
  for (const p of Object.keys(PATHS)) ok(src.includes(p), `首页链接到 ${p}`);
  ok(/30 秒看懂/.test(src), '首页有「30 秒看懂 AI」');
  ok(/最关键|会出错|编造/.test(src), '首页说明 AI 会出错');
  ok(src.indexOf('什么不要告诉 AI') > 0, '首页有隐私边界区块');
  ok(src.indexOf('href="tools.html"') > src.indexOf('href="limits.html"'), '首页把「会出错」排在「工具」之前');
  ok(/不用注册|不索要|不用填任何个人信息/.test(src), '首页明确不需要注册/个人信息');
}

// 7) 判断方法页：四招 + 五种错误 + 求助
{
  const src = html['limits.html'] || '';
  const moves = (src.match(/class="move"/g) || []).length;
  ok(moves === 4, `判断方法页恰好 4 招（实际 ${moves}）`);
  ok(/换个相反的问法/.test(src) && /要来源/.test(src) && /只认官方|只有官方/.test(src) && /哪里可能是错的/.test(src), '四招名称齐全');
  ok((src.match(/<tr><td>/g) || []).length >= 5, '至少 5 种常见错误');
  ok(/两个不同的 AI/.test(src) || /两个 AI/.test(src), '破除「问两个 AI 就可靠」的误解');
}

// 8) 工具页：与外链真源一致 + 复核日期 + 年龄边界 + v0 不推荐
{
  const src = html['tools.html'] || '';
  for (const u of ['https://www.doubao.com', 'https://chat.deepseek.com', 'https://www.gaoding.com']) {
    ok(src.includes(u), `工具页含真实入口 ${u}`);
  }
  ok(/2026-10-31/.test(src), '工具页写明复核日期');
  ok(/v0/.test(src) && /不作零基础第一步/.test(src), '工具页说明 v0 不作零基础第一步及原因（年龄门槛）');
  ok(/Stirling/.test(src) && /电脑/.test(src), '工具页说明 Stirling 需要电脑');
}

// 8b) 事实断言：这条文案曾经写错过一次（把官方 18 岁门槛写成「未明确最低年龄」，
//     方向还比官方更宽松）。这里把它锁死：只要出现「最低年龄」「更保守」这类措辞，
//     同一页就必须写出官方口径（18 周岁 + 监护人），否则判失败。
{
  const pages = { ...html, 'assets/tools.js': existsSync(join(SITE, 'assets', 'tools.js')) ? readFileSync(join(SITE, 'assets', 'tools.js'), 'utf8') : '' };
  for (const [p, src] of Object.entries(pages)) {
    if (!/未明确/.test(src) && !/更保守/.test(src)) continue;
    ok(!/最低年龄/.test(src) || /18/.test(src), `${p}：说到「最低年龄」时必须同时写出官方 18 周岁口径`);
  }
  const tools = pages['tools.html'] || '';
  ok(/未满 18 周岁/.test(tools), '工具页写明豆包/DeepSeek 官方要求：未满 18 周岁须监护人陪同并同意');
  ok(/《用户协议》/.test(tools), '工具页给出官方条款出处（《用户协议》），不是只说「官方说」');
  // 曾经写错第二条事实：v0「打不开」——与实测相反
  ok(!/打不开官网定价页/.test(tools), '工具页不再写「v0 定价页打不开」（2026-10-31 实测 200）');
  // assets/tools.js 是未被引用的副本，不允许它复活旧口径
  const tjs = pages['assets/tools.js'] || '';
  ok(!/未明确最低年龄/.test(tjs), 'assets/tools.js 不含旧口径「未明确最低年龄」');
}

// 9) 安全页：隐私清单 + 求助渠道
{
  const src = html['safety.html'] || '';
  for (const w of ['真实姓名', '密码', '照片', '110', '120', '托管方']) ok(src.includes(w), `安全页含「${w}」`);
  ok(/没有账号系统/.test(src), '安全页说明本站没有账号系统');
  ok(/不测时长/.test(src), '安全页说明不测时长/不评分');
  // 全站唯一没有可核实来源的断言（12355 的具体归属）不得再出现在任何页面里
  for (const [p, pageSrc] of Object.entries(html)) {
    ok(!/12355/.test(pageSrc), `${p}：不写无法核实归属的热线号码`);
  }
}

// 10) 回主站链接存在（并存，不抢占首页）
{
  const src = html['index.html'] || '';
  ok(src.includes('../index.html'), '新站链回 World Space 主入口（../index.html）');
}

const total = pass + fails.length;
if (fails.length) {
  console.error(`\nAI 从零开始 · 内容契约自测：${pass}/${total} 通过，${fails.length} 失败\n`);
  for (const f of fails) console.error(`  ✗ ${f.name}${f.detail ? `\n    ${f.detail}` : ''}`);
  process.exit(1);
}
console.log(`AI 从零开始 · 内容契约自测：${pass}/${total} 全部通过`);
