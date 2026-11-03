#!/usr/bin/env node
/*
 * AI 从零开始 · 真实浏览器旅程（零依赖，playwright-core 由环境提供 + 本机 Chrome）
 *
 * 它验证的不是「页面能打开」，而是：一个匿名手机访客，能不能从首页走到任一入口、复制到话、
 * 按步骤走完、并在三条路径上各自拿到「做成」的判据。旧站同时做回归：入口与交互不破。
 *
 * 用法：
 *   node eval/ai-beginner-journey.mjs
 * 环境变量：
 *   PW_CORE  playwright-core 的绝对路径（默认取本机 npm 缓存里已装的那份）
 *   OUT      截图输出目录（默认 var/ai-journey/<时间戳>）
 *   BASE_URL 若给出，则扫线上/局域网地址而不是本地起服务（如 https://ymai.fun）
 * 退出码：0 全通过；1 有失败
 */
import { createServer } from 'node:http';
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve, extname } from 'node:path';
import { createRequire } from 'node:module';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const require = createRequire(import.meta.url);
const PW_CORE = process.env.PW_CORE || 'C:/Users/User/AppData/Local/npm-cache/_npx/e41f203b7505f1fb/node_modules/playwright-core';
const STAMP = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '');
const OUT = process.env.OUT || join(ROOT, 'var', 'ai-journey', STAMP);
mkdirSync(OUT, { recursive: true });

let pass = 0;
const fails = [];
function ok(cond, name, detail) {
  if (cond) { pass++; return true; }
  fails.push({ name, detail });
  return false;
}

const MIME = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8' };

function startServer() {
  const srv = createServer((req, res) => {
    const clean = decodeURIComponent(req.url.split('?')[0]);
    let file = join(ROOT, clean);
    if (clean.endsWith('/')) file = join(file, 'index.html');
    if (!file.startsWith(ROOT) || !existsSync(file)) { res.writeHead(404); res.end('404'); return; }
    try {
      const body = readFileSync(file);
      res.writeHead(200, { 'content-type': MIME[extname(file)] || 'application/octet-stream' });
      res.end(body);
    } catch { res.writeHead(500); res.end('500'); }
  });
  return new Promise((r) => srv.listen(0, '127.0.0.1', () => r(srv)));
}

async function auditOverflow(page, label) {
  const res = await page.evaluate(() => {
    const de = document.documentElement;
    const overflowing = [...document.querySelectorAll('body *')]
      .filter((el) => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && (r.right > de.clientWidth + 1 || r.left < -1);
      })
      .slice(0, 5)
      .map((el) => el.tagName.toLowerCase() + (el.className ? '.' + String(el.className).split(' ')[0] : ''));
    return { scrollWidth: de.scrollWidth, clientWidth: de.clientWidth, overflowing };
  });
  ok(res.scrollWidth <= res.clientWidth + 1, `${label}：无横向溢出（${res.scrollWidth} <= ${res.clientWidth}）`, JSON.stringify(res.overflowing));
}

async function auditTouch(page, label) {
  // 独立 Checker 的量法更严：只量元素自己的盒子。这里按同一口径——
  // 原生复选框本身只有 22px，可点区域由 <label> 提供，所以量 label；其余元素量自身。
  const small = await page.evaluate(() => {
    const nodes = [...document.querySelectorAll('a,button,summary,input[type="checkbox"]')];
    const list = [];
    for (const el of nodes) {
      const probe = el; // 严格口径：量元素自己的盒子（复选框也量自身）
      const r = probe.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;
      const style = getComputedStyle(probe);
      if (style.display === 'none' || style.visibility === 'hidden') continue;
      if (r.height < 44 || r.width < 24) list.push({ tag: el.tagName.toLowerCase(), text: (el.textContent || '').trim().slice(0, 18), h: Math.round(r.height), w: Math.round(r.width), cls: String(el.className) });
    }
    return list;
  });
  ok(small.length === 0, `${label}：所有可见交互元素自身可点区高度 ≥44px`, JSON.stringify(small).slice(0, 600));
}

async function externalRequestAudit(page) {
  const foreign = [];
  page.on('request', (req) => {
    const u = req.url();
    if (!/^(http:\/\/127\.0\.0\.1|https?:\/\/localhost|about:|data:)/.test(u) && !u.startsWith(SELF_ORIGIN)) foreign.push(u);
  });
  page.on('pageerror', (e) => fails.push({ name: '页面脚本报错', detail: e.message }));
  return foreign;
}

let SELF_ORIGIN = '';
// 站点在部署后的目录：默认 /web/ai（静态根=仓库根）；静态根=web/ 时用 SITE_DIR=/ai；也可整站走 file:// 时用 SITE_DIR=/web/ai
const SITE_DIR = process.env.SITE_DIR || '/web/ai';

const { chromium } = require(PW_CORE);
const srv = process.env.BASE_URL ? null : await startServer();
const base = process.env.BASE_URL || `http://127.0.0.1:${srv.address().port}`;
SELF_ORIGIN = base;

const browser = await chromium.launch({ channel: 'chrome' });
const ctx = await browser.newContext({
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 2,
  isMobile: true,
  hasTouch: true,
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  locale: 'zh-CN'
});
const page = await ctx.newPage();
const foreign = await externalRequestAudit(page);

// ---- A. 首页先看到什么 ----
await page.goto(base + SITE_DIR + '/index.html', { waitUntil: 'load' });
await page.screenshot({ path: join(OUT, 'a1-home-390.png') });
await page.screenshot({ path: join(OUT, 'a1-home-390-full.png'), fullPage: true });

const firstScreen = await page.evaluate(() => {
  const h1 = document.querySelector('h1');
  const goals = [...document.querySelectorAll('a.goal')].filter((g) => g.getBoundingClientRect().top < window.innerHeight).length;
  return { h1: h1 ? h1.innerText.replace(/\s+/g, ' ').trim() : '', goalsInFirstScreen: goals, title: document.title };
});
ok(firstScreen.h1.length > 6, '首屏有清楚的 h1', firstScreen.h1);
ok(firstScreen.goalsInFirstScreen >= 3, '首屏（390x844）能直接看到三个目标入口', JSON.stringify(firstScreen));
ok(/从零开始/.test(firstScreen.title), '标题说清「从零开始」', firstScreen.title);

// 首屏不出现技术名词（对零基础者的硬要求）
const jargon = await page.evaluate(() => {
  const text = document.body.innerText;
  return ['API', 'token', 'Token', 'prompt', 'Prompt', '大模型', '参数', '训练', '微调'].filter((w) => text.includes(w));
});
ok(jargon.length === 0, '首页正文不出现未解释的技术名词', JSON.stringify(jargon));

// ---- B. 三条路径：从首页点进去，走到底 ----
const journeys = [
  {
    name: '路径一 让 AI 帮我做一件小事',
    link: 'a.goal[data-path="make"]',
    url: '/paths/make-something.html',
    steps: 4,
    tool: 'https://www.doubao.com',
    doneLabel: '我把那段话真的发出去了'
  },
  {
    name: '路径二 做一张属于我自己的图',
    link: 'a.goal[data-path="picture"]',
    url: '/paths/make-a-picture.html',
    steps: 4,
    tool: 'https://www.doubao.com',
    doneLabel: '我保存了这张图'
  },
  {
    name: '路径三 查清一件真事',
    link: 'a.goal[data-path="facts"]',
    url: '/paths/find-the-facts.html',
    steps: 5,
    tool: 'https://chat.deepseek.com',
    doneLabel: '我写出了自己的三句话'
  }
];

const evidence = [];
for (const j of journeys) {
  await page.goto(base + SITE_DIR + '/index.html', { waitUntil: 'load' });
  const t0 = Date.now();
  await page.click(j.link);
  await page.waitForLoadState('load');
  const clicksToPath = 1;
  ok(page.url().endsWith(j.url), `${j.name}：首页一个点击就到达路径页`, page.url());
  const promise = await page.evaluate(() => (document.querySelector('.path-head .promise') || {}).innerText || '');
  ok(/做成/.test(promise), `${j.name}：页首写明「做成」的判据`, promise.slice(0, 80));

  // 复制第一句话：真读到剪贴板（chromium 允许 http://127.0.0.1 的 clipboard）
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.click('.stage .saybox button.copy');
  await page.waitForTimeout(300);
  const clip = await page.evaluate(() => navigator.clipboard.readText().catch(() => ''));
  ok(clip.length > 20, `${j.name}：第一个「复制」按钮真的把话复制进了剪贴板`, clip.slice(0, 40));
  const okd = await page.evaluate(() => (document.querySelector('.stage .saybox button.copy') || {}).dataset?.ok === '1');
  ok(okd, `${j.name}：复制成功后按钮如实反馈「已复制」`);

  // 工具入口：真实 href + 新窗口 + noopener
  const tool = await page.evaluate(() => {
    const a = document.querySelector('a.tool-link[data-tool]');
    return a ? { href: a.href, target: a.target, rel: a.rel, text: a.innerText.trim() } : null;
  });
  ok(tool && tool.href.startsWith(j.tool), `${j.name}：工具入口指向 ${j.tool}`, JSON.stringify(tool));
  ok(tool && tool.target === '_blank' && /noopener/.test(tool.rel || ''), `${j.name}：外链新窗口打开且带 noopener`);

  // 步骤完整性 + 勾完成 + 本地持久
  const stages = await page.$$('.stage');
  ok(stages.length >= j.steps, `${j.name}：页面上有 ${j.steps} 段步骤（实际 ${stages.length}）`);
  const boxes = await page.$$('input[type="checkbox"]');
  for (const b of boxes) await b.check();
  await page.reload({ waitUntil: 'load' });
  const persisted = await page.evaluate(() => [...document.querySelectorAll('input[type="checkbox"]')].every((b) => b.checked));
  ok(persisted, `${j.name}：勾选的「做成了」刷新后仍保留（本地存储）`);

  // 回退路径
  const stuck = await page.$$('details.stuck');
  ok(stuck.length >= 1, `${j.name}：有「卡住了怎么办」可展开`);
  if (stuck.length) {
    await stuck[0].click();
    const open = await stuck[0].evaluate((d) => d.open);
    ok(open, `${j.name}：「卡住了怎么办」点击后真的展开`);
  }

  const doneText = await page.evaluate(() => document.body.innerText);
  ok(doneText.includes(j.doneLabel), `${j.name}：页面写明最终「做成」的判据`, j.doneLabel);

  await page.screenshot({ path: join(OUT, `b-${j.url.split('/').pop().replace('.html', '')}-390-full.png`), fullPage: true });
  await auditOverflow(page, `${j.name} @390`);
  await auditTouch(page, `${j.name} @390`);
  evidence.push({ path: j.name, clicksFromHome: clicksToPath, ms: Date.now() - t0 });
}

// ---- C. 手机窄屏 320 / 平板 768 / 桌面 1440 ----
const pagesToAudit = ['/limits.html', '/tools.html', '/safety.html', '/paths/make-something.html', '/paths/make-a-picture.html', '/paths/find-the-facts.html'].map((p) => SITE_DIR + p);
for (const [w, h, tag] of [[320, 568, '320'], [768, 1024, '768'], [1440, 900, '1440']]) {
  await page.setViewportSize({ width: w, height: h });
  for (const p of pagesToAudit) {
    await page.goto(base + p, { waitUntil: 'load' });
    await auditOverflow(page, `${p} @${tag}`);
  }
  await page.goto(base + SITE_DIR + '/index.html', { waitUntil: 'load' });
  await page.screenshot({ path: join(OUT, `c-home-${tag}.png`) });
}

// ---- D. 键盘可达 + 焦点可见（基础无障碍） ----
await page.setViewportSize({ width: 390, height: 844 });
await page.goto(base + SITE_DIR + '/index.html', { waitUntil: 'load' });
const tabSeq = [];
for (let i = 0; i < 6; i++) {
  await page.keyboard.press('Tab');
  tabSeq.push(await page.evaluate(() => {
    const el = document.activeElement;
    const s = getComputedStyle(el);
    return { tag: el.tagName.toLowerCase(), txt: (el.innerText || '').trim().slice(0, 16), outline: s.outlineStyle + ' ' + s.outlineWidth };
  }));
}
ok(tabSeq.every((t) => !/none 0px/.test(t.outline)), '键盘 Tab 时焦点有可见描边', JSON.stringify(tabSeq));

// ---- E. 旧站回归：World Space 原入口没有被打坏 ----
const regress = [];
await page.setViewportSize({ width: 390, height: 844 });
await page.goto(base + '/index.html', { waitUntil: 'load' });
regress.push({ page: '/index.html', finalUrl: page.url(), title: await page.title() });
ok(/web\/index\.html/.test(page.url()), '旧站根入口仍跳到 web/index.html', page.url());

await page.goto(base + '/web/index.html', { waitUntil: 'load' });
const legacy = await page.evaluate(() => {
  const ids = ['btn-write', 'btn-poster', 'btn-web', 'btn-photo', 'btn-find', 'btn-organize', 'btn-ocr', 'startBtn', 'step-1', 'step-2', 'step-3'];
  const missing = ids.filter((id) => !document.getElementById(id));
  return { missing, title: document.title, hasProgressKey: /ws_progress_v2/.test(document.documentElement.innerHTML) };
});
ok(legacy.missing.length === 0, '旧站：7 个目标按钮与 3 步兜底仍在', JSON.stringify(legacy.missing));
ok(/你想做什么事/.test(legacy.title), '旧站标题未变', legacy.title);
// 旧站核心交互：点「写点东西」面板展开
await page.click('#btn-write');
const panelOpen = await page.evaluate(() => document.getElementById('goal-write').classList.contains('open'));
ok(panelOpen, '旧站：点击「写点东西」仍能展开目标面板');
// 旧站外链仍指向真实工具
const legacyLinks = await page.evaluate(() => [...document.querySelectorAll('#goal-write a[href^="https://"]')].map((a) => a.href));
ok(legacyLinks.some((u) => u.includes('doubao.com')), '旧站：写点东西面板仍外链豆包', JSON.stringify(legacyLinks.slice(0, 3)));
await page.screenshot({ path: join(OUT, 'e-legacy-390.png'), fullPage: false });

// 并存：旧站不出现新站链接（本阶段不改首页），新站链回旧站
const legacyHasNew = await page.evaluate(() => /web\/ai\//.test(document.documentElement.innerHTML));
ok(!legacyHasNew, '旧站未被注入新站链接（本阶段并存，不改旧首页）');
await page.goto(base + SITE_DIR + '/index.html', { waitUntil: 'load' });
const backHome = await page.evaluate(() => {
  const a = document.querySelector('footer a[href="../index.html"], .topbar a[href="../index.html"]');
  return a ? a.href : null;
});
ok(!!backHome, '新站能回到 World Space 主入口', backHome);

// ---- F. 零外部请求 ----
ok(foreign.length === 0, '全程页面未发起任何第三方请求（无统计/广告/字体/CDN）', JSON.stringify(foreign.slice(0, 5)));

const report = {
  at: new Date().toISOString(), base, viewport: '390x844 mobile (iPhone UA)', screenshots: OUT,
  evidence, regress, pass, fail: fails
};
const fs = await import('node:fs');
fs.writeFileSync(join(OUT, 'report.json'), JSON.stringify(report, null, 2));

await browser.close();
if (srv) srv.close();

console.log(`\nAI 从零开始 · 浏览器旅程：${pass}/${pass + fails.length} 通过`);
console.log(`截图与报告：${OUT}`);
if (fails.length) {
  for (const f of fails) console.error(`  ✗ ${f.name}${f.detail ? `\n    ${String(f.detail).slice(0, 400)}` : ''}`);
  process.exit(1);
}
