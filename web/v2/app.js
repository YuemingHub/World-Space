/* World Space v2 前端：唯一职责是把一句真实的话交给 /api/world，把契约结果如实给人看，
 * 并接住用户带回的现实结果（回执）进入下一轮——Outcome Loop 的"回来"这一拍在这里。
 * 没有状态库、没有路由、没有占位数据；失败时说实话，并始终给一个不依赖本服务的现实下一步。
 * 渲染与安全边界（转义 / URL 白名单 / 复制槽位 / 交棒链接白名单）在 ./render.mjs，本文件只做 DOM 接线。 */
import { esc, buildResultHtml } from './render.mjs';

const API = new URLSearchParams(location.search).get('api') || '/api/world';
const $ = id => document.getElementById(id);
let lastIntent = '', busy = false, timer = null, t0 = 0;

/* 行动回路只存让"回来"这一拍成立的最小数据：意图、上一份契约、更新时间。
 * 只放本机 localStorage，不上传、不做账号、不做历史工作台。 */
const LOOP_KEY = 'ws.loop.v1';
function saveLoop(intent, j) {
  try { localStorage.setItem(LOOP_KEY, JSON.stringify({ intent, result: j, updated_at: Date.now() })); } catch (e) { }
}
function loadLoop() {
  try {
    const x = JSON.parse(localStorage.getItem(LOOP_KEY));
    return (x && x.intent && x.result && x.result.understanding !== undefined) ? x : null;
  } catch (e) { return null; }
}
function clearLoop() { try { localStorage.removeItem(LOOP_KEY); } catch (e) { } }

const ERR_TEXT = {
  budget_exceeded: ['今天的用量到上限了。', true],
  rate_limited: ['这一分钟请求太密了，等一分钟再试。', true],
  budget_guard_unavailable: ['服务暂时不可用（安全保护触发了）。稍后再试。', true],
  intelligence_unavailable: ['这一轮没有得出可靠结果（服务或网络波动）。可以重试一次；在这之前，别按不完整的答案行动。', false],
  intelligence_contract_failure: ['这一轮的结果没通过质量检查，已经整份作废。可以重试一次。', false],
  body_too_large: ['你写的内容太长了，试着把最核心的一两句发过来。', true],
  body_bad_json: ['发送的内容没能被正确读取，请重试一次。', false],
  intent_too_short: ['再多写几个字，让我知道你想做成什么。', true],
  intent_too_long: ['内容超过 500 字了，先说最核心的那件事。', true],
  network: ['连不上服务。检查网络后可以重试。', false],
};

async function ask(intent, answers, receipt) {
  if (busy) return;
  busy = true;
  lastIntent = intent || lastIntent;
  $('go') && ($('go').disabled = true);
  $('result').hidden = true; $('error').hidden = true;
  $('loading').hidden = false;
  t0 = Date.now();
  clearInterval(timer);
  timer = setInterval(() => {
    const s = Math.round((Date.now() - t0) / 1000);
    $('elapsed').textContent = `已经等了 ${s} 秒。`;
  }, 1000);
  const payload = { intent: lastIntent, answers: answers || [] };
  if (receipt && (receipt.status === 'done' || receipt.status === 'stuck' || receipt.text)) {
    payload.receipt = { status: receipt.status || 'info', text: String(receipt.text || '').slice(0, 2000) };
  }
  let res, j = null, netErr = false;
  try {
    res = await fetch(API, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(120000),
    });
    j = await res.json();
  } catch (e) { netErr = true; }
  clearInterval(timer);
  busy = false;
  $('loading').hidden = true;
  $('go') && ($('go').disabled = false);
  if (netErr) return showError('network', 0);
  if (res.status === 200 && j && j.understanding !== undefined) return render(j);
  showError((j && j.error) || 'network', res.status, j);
}

function showError(code, status, j) {
  const [text, noRetry] = ERR_TEXT[code] || ['出问题了，这一轮没有结果。', false];
  const fallback = j && j.fallback_if_refused;
  let h = `<div class="err"><strong>${esc(text)}</strong>`;
  if (fallback) h += `<p class="fine">不等服务也能做的事：${esc(fallback)}</p>`;
  if (!noRetry) h += `<button class="ghost" id="retry">再试一次</button>`;
  h += `</div>`;
  $('error').innerHTML = h;
  $('error').hidden = false;
  const b = $('retry');
  if (b) b.onclick = () => { $('error').hidden = true; ask(lastIntent); };
}

/* 复制：点击的是渲染时留下的槽位按钮，原文在渲染后经 dataset 赋值（DOM property，
 * 不经过 HTML 解析），这里读到的就是原文，不再有任何手工反转义。 */
document.addEventListener('click', async e => {
  const t = e.target.closest('[data-copy]');
  if (!t) return;
  const raw = t.dataset.copy || '';
  let done = false;
  try { await navigator.clipboard.writeText(raw); done = true; } catch (x) { }
  if (!done) {
    const ta = document.createElement('textarea');
    ta.value = raw; document.body.appendChild(ta); ta.select();
    try { done = document.execCommand('copy'); } catch (x) { }
    ta.remove();
  }
  t.textContent = done ? '已复制 ✓' : '复制失败——长按文字手动复制';
});

function render(j, restored) {
  const { html, copies } = buildResultHtml(j);
  let head = '';
  if (restored) {
    head = `<div class="card fine restore">这是你上次进行到的地方（只存在这台设备上）。
      <button class="ghost" id="fresh-start">换个新目标</button></div>`;
  } else {
    saveLoop(lastIntent, j); // 真实教训：持久化函数定义了但没接线，刷新后回路就断了
  }
  $('result').innerHTML = head + html;
  document.querySelectorAll('#result [data-copy-slot]').forEach(el => {
    el.dataset.copy = copies[Number(el.dataset.copySlot)] || '';
  });
  $('result').hidden = false;
  bindAfterRender(j, restored);
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

/* 回执：三种带法——做成了（可选贴结果）/ 卡住了（贴卡点原话）/ 直接粘贴结果。
 * 回执进下一轮模型上下文，第二轮是推进，不是重答。 */
const RECEIPT_FORMS = {
  'fb-done': {
    title: '做成了。世界给了你什么？', status: 'done', ph: '可以贴工单号、对方答复、外部 AI 给你的产出（选填）',
    btn: '带着结果继续',
  },
  'fb-stuck': {
    title: '卡在哪一步？', status: 'stuck', ph: '把对方的话、页面上的说法原样贴进来',
    btn: '换条路继续',
  },
  'fb-paste': {
    title: '把结果原样贴回来', status: 'info', ph: '粘贴你拿到的全部内容',
    btn: '接着这个往下走',
  },
};

function bindAfterRender(j, restored) {
  const fs = $('fresh-start');
  if (fs) fs.onclick = () => { clearLoop(); location.reload(); };
  const ans = $('answer');
  if (ans) ans.onclick = () => {
    const box = $('ansbox');
    box.hidden = !box.hidden;
    if (box.hidden) return;
    box.innerHTML = (j.questions || []).map((q, i) =>
      `<div class="card"><strong>${i + 1}. ${esc(q.ask)}</strong><textarea rows="2" data-ans="${i}"></textarea></div>`).join('')
      + `<button class="primary" id="sendans">按我的回答重新想</button>`;
    $('sendans').onclick = () => {
      const answers = Array.from(box.querySelectorAll('[data-ans]')).map((ta, i) => ({ q: j.questions[i].ask, a: ta.value }));
      ask(lastIntent, answers);
    };
  };
  const openReceipt = id => {
    const box = $('stuckbox');
    const f = RECEIPT_FORMS[id];
    const close = box.dataset.mode === id && !box.hidden;
    box.dataset.mode = id;
    box.hidden = close;
    if (close) return;
    box.innerHTML = `<div class="card"><strong>${esc(f.title)}</strong>
      <textarea rows="3" id="receipttxt" placeholder="${esc(f.ph)}"></textarea>
      <button class="primary" id="sendreceipt">${esc(f.btn)}</button></div>`;
    $('sendreceipt').onclick = () => ask(lastIntent, [], { status: f.status, text: $('receipttxt').value });
  };
  ['fb-done', 'fb-stuck', 'fb-paste'].forEach(id => { const b = $(id); if (b) b.onclick = () => openReceipt(id); });
}

$('go').onclick = () => {
  const v = $('intent').value.trim();
  if (v.length < 2) return showError('intent_too_short', 400);
  $('ask-sec').hidden = true;
  ask(v);
};

/* 刷新/回来后接着上次的继续：恢复上一份契约与回执入口，不要求用户重讲一遍。 */
{
  const saved = loadLoop();
  if (saved && Date.now() - saved.updated_at < 7 * 24 * 3600 * 1000) {
    lastIntent = saved.intent;
    $('ask-sec').hidden = true;
    render(saved.result, true);
  } else if (saved) {
    clearLoop();
  }
}
