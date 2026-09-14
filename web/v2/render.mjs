/*
 * 渲染纯函数（无 DOM 依赖）：app.js 与 XSS 边界回归自测共用同一份代码。
 * 安全边界都在这里：
 *   esc —— 文本与属性通用的转义（引号必须转：否则一个 " 就能逃出属性）；
 *   httpUrl —— 可点击链接的最后一道边界：只放行 http(s)；
 *   HANDOFF_LINKS —— 交棒的跳转链接只来自这份前端代码白名单，
 *          绝不采用模型给的 URL；目标名匹配不上就不给"打开"按钮，宁可只给任务书。
 * 复制按钮不把文本拼进 HTML：这里只留槽位序号，真实文本由 app.js 在渲染后
 * 经 dataset（DOM property，不经过 HTML 解析）赋值，点击时读到的就是原文。
 *
 * 结果页信息架构（§23）：用户要做成什么 → 现在只做这一步 → 怎么算做完 → 去做 →
 * 做成了/卡住了/把结果带回来 → 其余复杂信息收进第二层（details，想看再展开）。
 * 唯一例外（§27）：真正重要的不确定性不藏——折叠摘要里就露出第一条。
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

/* 交棒目标白名单：name/url 由本代码定，模型只给目标名字符串。
   这不是能力市场——第一版只有一个通用 AI 交棒对象，真实需求出现再扩。 */
const HANDOFF_LINKS = [
  { match: 'deepseek', name: 'DeepSeek', url: 'https://chat.deepseek.com/' },
];
export function handoffLink(target) {
  const t = String(target || '').toLowerCase();
  return HANDOFF_LINKS.find(x => t.indexOf(x.match) !== -1) || null;
}

const MODE_LABEL = { internal: '在这一页就能完成', handoff: '交给现成工具更合适', human: '要你本人进入现实世界' };

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

/** 本轮唯一主行动。模型缺省时回退 safe_next_action（服务端通常已推导好 next_action）。 */
function nextActionOf(j) {
  if (j.next_action && j.next_action.text) return j.next_action;
  if (j.safe_next_action) return { text: j.safe_next_action, done_when: '', mode: '', handoff_task: '', handoff_target: '' };
  return null;
}

function actionHtml(j, copies) {
  const na = nextActionOf(j);
  if (!na) return '';
  const copyBtn = text => `<button class="ghost copy" data-copy-slot="${copies.push(String(text == null ? '' : text)) - 1}">复制这句话</button>`;
  let h = `<h2 class="act-head">现在只做这一步</h2><div class="action"><div class="act-text">${esc(na.text)}</div>`;
  if (na.done_when) h += `<div class="done-when">怎么算做完：${esc(na.done_when)}</div>`;
  if (MODE_LABEL[na.mode]) h += `<div class="fine">这一步${esc(MODE_LABEL[na.mode])}。</div>`;
  if (na.mode === 'handoff' && na.handoff_task) {
    h += `<div class="handoff"><div class="fine">任务书：复制 → 粘贴到${esc(na.handoff_target || '那个工具')} → 直接发送</div>`
      + `<div class="task">${esc(na.handoff_task)}</div>${copyBtn(na.handoff_task)}`;
    const link = handoffLink(na.handoff_target);
    if (link) h += ` <a class="ghost openlink" href="${attr(link.url)}" target="_blank" rel="noopener noreferrer">打开 ${esc(link.name)} ↗</a>`;
    else if (na.handoff_target) h += `<div class="fine">这里没有预置 ${esc(na.handoff_target)} 的入口链接——复制任务书，自己去打开它。</div>`;
    h += `</div>`;
  }
  h += `${copyBtn(na.text)}</div>`;
  return h;
}

/** 第二层信息：默认收起，想看再展开（复杂留给系统，选择留给人）。 */
function detailsHtml(summary, inner, open) {
  return `<details class="more"${open ? ' open' : ''}><summary>${summary}</summary><div class="more-body">${inner}</div></details>`;
}

/** 契约 → 结果页 HTML。copies 与输出里 data-copy-slot 的顺序一一对应，装载原文。 */
export function buildResultHtml(j) {
  const copies = [];
  let h = '';
  if (j.understanding) h += `<h2 class="want-head">你要做成</h2><div class="card want">${esc(j.understanding)}</div>`;

  h += actionHtml(j, copies);

  /* 回执紧贴主行动：用户做完抬眼就是"回来"的路，不用在长页里找。 */
  if (j.reality_feedback_prompt) {
    h += `<div class="bring-back"><div class="fine">去做，然后把结果带回来。${esc(j.reality_feedback_prompt)}</div>
      <div class="feedback">
        <button class="ghost" id="fb-done">做成了 ✓</button>
        <button class="ghost" id="fb-stuck">卡住了</button>
        <button class="ghost" id="fb-paste">把结果带回来</button>
      </div><div id="stuckbox" hidden></div></div>`;
  }

  if (j.questions && j.questions.length) {
    const inner = `<div class="qa">` + j.questions.map((q, i) =>
      `<div class="card"><strong>${i + 1}. ${esc(q.ask)}</strong><div class="fine">${esc(q.why || '')}</div></div>`).join('')
      + `</div><button class="ghost" id="answer">我要回答（打开输入框）</button><div id="ansbox" hidden></div>`;
    h += detailsHtml(`有 ${j.questions.length} 个情况，弄清后下一步会更准`, inner);
  }

  if (j.recommended_path && j.recommended_path.summary) {
    h += detailsHtml('为什么是这一步', `<div class="card">
      <div>${esc(j.recommended_path.summary)}</div>
      <div class="fine">为什么：${esc(j.recommended_path.why)}</div></div>`);
  }

  if (j.resources && j.resources.length) {
    h += detailsHtml(`世界上已经有什么（${j.resources.length}）`, j.resources.map(resourceHtml).join(''));
  } else {
    h += detailsHtml('世界上已经有什么', `<div class="card fine">这一步没有找到足够可信的现实资源，所以不硬塞。上面的动作不依赖它们。</div>`);
  }

  if (j.uncertainties && j.uncertainties.length) {
    /* §27 例外：重要的不确定不能藏进折叠里没人看见——摘要行直接露出第一条 */
    const first = String(j.uncertainties[0] || '');
    const preview = first.length > 44 ? first.slice(0, 44) + '…' : first;
    h += detailsHtml(`还有什么没有确定（${j.uncertainties.length}）——${esc(preview)}`,
      `<div class="notice"><ul>` + j.uncertainties.map(u => `<li>${esc(u)}</li>`).join('') + `</ul></div>`);
  }

  return { html: h, copies };
}
