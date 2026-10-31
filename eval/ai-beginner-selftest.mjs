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
  ok(/复核于 20\d\d-\d\d-\d\d/.test(src), '工具页写明复核日期（格式可查）');
  ok(/下次复核 20\d\d-\d\d-\d\d/.test(src), '工具页写明下次复核日期');
  ok(/v0/.test(src) && /不作零基础第一步/.test(src), '工具页说明 v0 不作零基础第一步及原因（年龄门槛）');
  ok(/Stirling/.test(src) && /电脑/.test(src), '工具页说明 Stirling 需要电脑');
}

// 8b) 事实断言：这条文案曾经写错过一次（把官方 18 岁门槛写成「未明确最低年龄」，
//     方向还比官方更宽松）。第一次的写法是「说到最低年龄就必须出现 18」——那是空转的：
//     页面别处本来就有「18」，把错误文案注回去照样全绿（独立 Checker 用变异测试证伪过）。
//     现在改成直接禁旧措辞：断言必须能被证伪，否则绿灯不提供任何信息。
{
  const pages = { ...html, 'assets/tools.js': existsSync(join(SITE, 'assets', 'tools.js')) ? readFileSync(join(SITE, 'assets', 'tools.js'), 'utf8') : '' };
  const BANNED = [
    /未明确最低年龄/,
    /没有公开明确的最低年龄/,
    /更保守的家长判断线/,
    /未满\s*14\s*岁请和家长一起用/
  ];
  for (const [p, src] of Object.entries(pages)) {
    for (const re of BANNED) {
      ok(!re.test(src), `${p}：不得出现旧口径 ${re}`);
    }
  }
  // 每条年龄断言旁边必须是官方口径（18 周岁 + 监护人），并且有可点开的条款出处
  const tools = pages['tools.html'] || '';
  const ageLines = tools.split('\n').filter((l) => /未满 18 周岁/.test(l));
  ok(ageLines.length >= 2, '工具页对豆包与 DeepSeek 各写一次官方 18 周岁口径', `实际命中 ${ageLines.length} 行`);
  ok(/https:\/\/www\.doubao\.com\/legal\/terms/.test(tools), '豆包条款给出可点开的官方链接');
  ok(/https:\/\/cdn\.deepseek\.com\/policies\/zh-CN\/deepseek-terms-of-use\.html/.test(tools), 'DeepSeek 条款给出可点开的官方链接');
  ok(!/打不开官网定价页/.test(tools), '工具页不再写「v0 定价页打不开」（2026-10-31 实测 200）');
  ok(!/速度也不稳定|访问不稳定/.test(tools), '工具页不写没有实测支撑的「不稳定」判断');
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

// 11) 与现有站的真实关系（Commander 裁决 PARALLEL_AI_ENTRY）：
//     旧首页必须保留一个指向新入口的链接；但不得把新入口设成默认首页；
//     且这条链接只能是"一行小字"，不能改动旧首页其它结构。
{
  const legacy = readFileSync(join(ROOT, 'web', 'index.html'), 'utf8');
  const rootIdx = readFileSync(join(ROOT, 'index.html'), 'utf8');
  ok(/href="ai\/index\.html"/.test(legacy), '旧首页保留指向 ai/index.html 的入口链接');
  ok(!/<meta http-equiv="refresh"[^>]*ai\/index\.html/i.test(legacy), '旧首页不得把 AI 入口设成默认跳转');
  ok(/url=web\/index\.html/.test(rootIdx), '根跳转页仍指向 web/index.html（未被改成 /ai/）');
  ok((legacy.match(/href="ai\/index\.html"/g) || []).length === 1, '旧首页只有一处指向新入口（一行小字，不铺开）');
}

// 12) 路径一的「做成」不得以"别人回复"为判据（Commander 裁决：学习者的行动完成与否由他自己决定）
{
  const src = html['paths/make-something.html'] || '';
  ok(!/收到了?一个人的回应/.test(src), '路径一：不以「收到回应」作为做成判据');
  ok(!/等回应/.test(src), '路径一：不再要求「等回应」');
  ok(/不需要等谁回复/.test(src), '路径一：明确写出「不需要等谁回复才算数」');
  ok(/不是你的成果指标/.test(src), '路径一：明确写出对方回复不是成果指标');
}

const total = pass + fails.length;
if (fails.length) {
  console.error(`\nAI 从零开始 · 内容契约自测：${pass}/${total} 通过，${fails.length} 失败\n`);
  for (const f of fails) console.error(`  ✗ ${f.name}${f.detail ? `\n    ${f.detail}` : ''}`);
  process.exit(1);
}
console.log(`AI 从零开始 · 内容契约自测：${pass}/${total} 全部通过`);
