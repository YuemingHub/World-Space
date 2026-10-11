/*
 * 公开入口浏览器旅程自测 —— 匿名合成访客（手机视口 390x844）从 / 触达「写点东西」行动路径。
 * 自包含：自己起 world.mjs（stub provider，fixture 用户），跑完即关，无需外部服务。
 * 验证层级：触达（页面打开）→ 选择（面板展开）→ 操作（复制第一步）→ 出口（工具外链）→ 深链 → 登录墙负控。
 * 浏览器自动化只能证明"触达和操作"；真实工具内的产出（豆包要登录）如实标注，不冒充真人体验。
 * 依赖：playwright-core（非本仓依赖，用 env PW_CORE 指到本机现成安装，浏览器二进制走 ms-playwright 缓存）。
 * 产物：截图 PNG 与 journey.json 落 var/frontdoor-journey/（gitignored，复跑即再生）。
 */
import { spawn } from 'node:child_process';
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { createAuth, hashPassword } from '../server/auth.mjs';

const PW_CORE = process.env.PW_CORE || 'C:/Users/User/.zcode/workspace/default/sdt/ui-test/node_modules/playwright-core/index.mjs';
const { chromium } = await import('file:///' + PW_CORE.replace(/\\/g, '/').replace(/^file:\/+/, 'file:///').replace(/^file:\/\/C:/, 'file:///C:'));

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const VAR = join(ROOT, 'var');
const OUT = join(VAR, 'frontdoor-journey');
const PORT = 8995;
mkdirSync(VAR, { recursive: true });
mkdirSync(OUT, { recursive: true });
const journey = { base: `http://127.0.0.1:${PORT}`, viewport: '390x844', locale: 'zh-CN', anonymous: true, steps: [], pageErrors: [] };
let failures = 0;
const step = (n, name, pass, detail) => {
  journey.steps.push({ n, name, pass, detail });
  console.log(`${pass ? '✓' : '✗'} [${n}] ${name}${pass ? '' : ' —— ' + detail}`);
  if (!pass) failures++;
};

const usersFile = join(VAR, 'frontdoor-users.json');
const secretFile = join(VAR, 'frontdoor-secret.txt');
const stateFile = join(VAR, 'frontdoor-journey-state.json');
writeFileSync(secretFile, randomBytes(48).toString('base64') + '\n');
writeFileSync(usersFile, JSON.stringify({ users: [{ user_id: 'u-fd', username: 'frontdoor', password_hash: hashPassword('frontdoor-check-2026') }] }));
rmSync(stateFile, { force: true });

const child = spawn(process.execPath, [join(ROOT, 'server', 'world.mjs')], {
  env: Object.assign({}, process.env, {
    WS_PROVIDER: 'stub', WS_STUB_CASE: 'ok', WS_SEARCH: 'fixture', WS_LIVENESS: '0',
    WS_PORT: String(PORT), WS_HOST: '127.0.0.1', WS_STATE_FILE: stateFile,
    WS_OPS_PORT: String(PORT + 400), WS_DAILY_CAP: '500',
    WS_AUTH_USERS_FILE: usersFile, WS_SESSION_SECRET_FILE: secretFile, WS_RATE_LIMIT: '1000',
  }),
  stdio: 'ignore',
});
for (let i = 0; i < 40 && !await fetch(`${journey.base}/healthz`).then(r => r.ok).catch(() => false); i++) await new Promise(r => setTimeout(r, 150));

const browser = await chromium.launch({ headless: true });
try {
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    locale: 'zh-CN',
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  });
  const page = await ctx.newPage();
  page.on('pageerror', e => journey.pageErrors.push(String(e).slice(0, 200)));

  await page.goto(journey.base + '/', { waitUntil: 'domcontentloaded' });
  const title = await page.title();
  step(1, '匿名手机访客打开 / 触达七行动入口门面页', title.includes('你想做什么事'), `title=${title}`);
  await page.screenshot({ path: join(OUT, '01-facade-mobile.png'), fullPage: true });

  const btn = page.locator('#btn-write');
  await btn.click();
  await page.waitForTimeout(300);
  const expanded = await btn.getAttribute('aria-expanded');
  const panelVisible = await page.locator('#goal-write').isVisible();
  step(2, '点击「写点东西」→ 面板展开（aria-expanded=true，面板可见）', expanded === 'true' && panelVisible, `expanded=${expanded} visible=${panelVisible}`);
  await page.screenshot({ path: join(OUT, '02-write-panel.png'), fullPage: true });

  const promptText = await page.locator('#goal-write .prompt-box').innerText();
  step(3, '第一步文案可见且可复制（含模板句与复制按钮）', promptText.includes('帮我写一段话') && await page.locator('#goal-write .copy-btn').isVisible(), promptText.slice(0, 60));
  await page.locator('#goal-write .copy-btn').click();
  await page.waitForTimeout(300);
  step(4, '复制按钮点击无 JS 错误（剪贴板权限为环境限制，如实标注）', journey.pageErrors.length === 0, `pageErrors=${journey.pageErrors.length}`);

  const toolHref = await page.locator('#goal-write a.tool-btn').getAttribute('href');
  step(5, '「打开豆包 →」工具外链在面板内（href 存在）', toolHref === 'https://www.doubao.com', `href=${toolHref}`);

  await page.goto(journey.base + '/#write', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(400);
  const deepExpanded = await page.locator('#btn-write').getAttribute('aria-expanded');
  step(6, '深链 /#write 直达面板展开（可分享/收藏）', deepExpanded === 'true', `expanded=${deepExpanded}`);
  await page.screenshot({ path: join(OUT, '04-deeplink-write.png'), fullPage: true });

  await page.goto(journey.base + '/login', { waitUntil: 'domcontentloaded' });
  const loginForm = await page.locator('#username').isVisible() && await page.locator('#password').isVisible();
  step(7, '负控：/login 登录页正常（账号+密码表单在，既有入口无回归）', loginForm, `title=${await page.title()}`);
  await page.screenshot({ path: join(OUT, '03-login-negative-control.png'), fullPage: true });

  journey.summary = failures === 0 ? 'ALL_STEPS_PASS' : `${failures}_STEPS_FAIL`;
  writeFileSync(join(OUT, 'journey.json'), JSON.stringify(journey, null, 2));
  console.log(failures === 0 ? '\n旅程：全部触达成功' : `\n旅程：${failures} 步失败`);
} finally { await browser.close(); try { child.kill('SIGKILL'); } catch (e) { } }
process.exit(failures === 0 ? 0 : 1);
