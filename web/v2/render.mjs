/*
 * 渲染纯函数（无 DOM 依赖）：app.js 与 XSS 边界回归自测共用同一份代码。
 * R1 两道边界都在这里：
 *   esc —— 文本与属性通用的转义（引号必须转：否则一个 " 就能逃出属性，
 *          注入 onerror / onfocus 之类的新属性；旧实现只转义文本节点上下文）；
 *   httpUrl —— 可点击链接的最后一道边界：只放行 http(s)。
 *          javascript: / data: / 解析失败的 URL 一律返回空串，调用方不给 <a>。
 * 复制按钮不把文本拼进 HTML：这里只留槽位序号，真实文本由 app.js 在渲染后
 * 经 dataset（DOM property，不经过 HTML 解析）赋值，点击时读到的就是原文。
 */
export function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
export const attr = esc; // 属性上下文与文本上下文共用同一转义（引号已转，逃不出引号定界的属性）

export function httpUrl(u) {
  try {
    const x = new URL(String(u || ''));
    return (x.protocol === 'http:' || x.protocol === 'https:') ? x.href : '';
  } catch (e) { return ''; }
}

const AUTH = {
  official_primary: ['官方来源', 'official'],
  trusted_secondary: ['权威媒体', 'trusted'],
  unverified: ['未核实来源', 'unverified'],
};

function resourceHtml(r) {
  const [label, cls] = AUTH[r.source_type] || AUTH.unverified;
  const fresh = (r.checked_at ? `核实于 ${esc(r.checked_at)}` : '');
  const conf = r.confidence === 'low' ? ' · 把它当线索' : '';
  const src = httpUrl(r.source_url);
  const srcHtml = r.source_url
    ? (src
      ? `<div class="src"><a href="${attr(src)}" target="_blank" rel="noopener noreferrer">打开来源</a>（${esc(r.source_title || '来源页')}）${fresh ? ' · ' + fresh : ''}</div>`
      : `<div class="src">（该来源的链接未通过安全校验，不提供点击）</div>`)
    : '';
  return `<div class="card">
    <strong>${esc(r.name)}</strong> <span class="badge ${cls}">${label}</span>${conf ? `<span class="badge">${'低置信'}</span>` : ''}
    <div>${esc(r.claim)}</div>
    <div class="fine">为什么它有用：${esc(r.why)}</div>${srcHtml}
  </div>`;
}

/** 契约 → 结果页 HTML。copies 与输出里 data-copy-slot 的顺序一一对应，装载原文。 */
export function buildResultHtml(j) {
  const copies = [];
  const copyBtn = text => `<button class="ghost copy" data-copy-slot="${copies.push(String(text == null ? '' : text)) - 1}">复制这句话</button>`;
  let h = '';
  h += `<h2>我们理解你现在想做的是</h2><div class="card">${esc(j.understanding)}</div>`;
  if (j.understanding) h += `<p class="fine">我理解得不对？回到上面改一改再发一次。</p>`;

  if (j.questions && j.questions.length) {
    h += `<h2>先回答这两个问题，答案会直接改变下一步</h2><div class="card qa">`;
    j.questions.forEach((q, i) => {
      h += `<div><strong>${i + 1}. ${esc(q.ask)}</strong><div class="fine">${esc(q.why || '')}</div></div>`;
    });
    h += `</div><button class="ghost" id="answer">我要回答（打开输入框）</button><div id="ansbox" hidden></div>`;
  }

  if (j.recommended_path && j.recommended_path.summary) {
    h += `<h2>默认我建议你先走这条</h2><div class="card">
      <div>${esc(j.recommended_path.summary)}</div>
      <div class="fine">为什么：${esc(j.recommended_path.why)}</div></div>`;
  } else {
    h += `<h2>默认我建议你先走这条</h2><div class="card fine">这一步还没法给你确定路径——先看下面要弄清的事和现在能做的一步。</div>`;
  }

  if (j.resources && j.resources.length) {
    h += `<h2>世界上已经有什么</h2>` + j.resources.map(resourceHtml).join('');
  } else {
    h += `<h2>世界上已经有什么</h2><div class="card fine">这一步没有找到足够可信的现实资源，所以不硬塞。下面的动作不依赖它们。</div>`;
  }

  if (j.uncertainties && j.uncertainties.length) {
    h += `<h2>这些事我还没把握，别当成结论</h2><div class="notice"><ul>`
      + j.uncertainties.map(u => `<li>${esc(u)}</li>`).join('') + `</ul></div>`;
  }

  if (j.safe_next_action) {
    h += `<h2>现在只做这一步</h2><div class="action">${esc(j.safe_next_action)}${copyBtn(j.safe_next_action)}</div>`;
  }
  if (j.reality_feedback_prompt) {
    h += `<div class="feedback">
      <button class="ghost" id="fb-done">做成了 ✓</button>
      <button class="ghost" id="fb-stuck">卡住了</button></div><div id="stuckbox" hidden></div>`;
  }
  return { html: h, copies };
}
