/*
 * 护栏（Guard）：证据绑定 + 来源授权 + 高风险撤回 + 截断留痕 + 中性兜底。
 * 这一份是 Slice 1.1 的主体，与传输/流程分开，便于单独评审。
 * 立场：只降级，不升级；宁可撤回，不误指路。
 */
import { claimRisk } from './evidence.mjs';

const RESOURCE_TYPES = ['government', 'institution', 'company', 'service', 'place', 'person',
  'community', 'document', 'dataset', 'open_source', 'software', 'ai_tool', 'product', 'other'];
const NEUTRAL_ACTION = '今天先把这件事的三个要素写下来：发生时间、地点或对象、你已经做过什么。';

function today() { return new Date().toISOString().slice(0, 10); }

/**
 * @param c   模型产出的契约草稿
 * @param ev  服务端签发的本轮证据表（模型只能引用其中的 id）
 */
export function guard(c, ev) {
  const acts = [], dropped = [], downgrades = [];
  const out = JSON.parse(JSON.stringify(c || {}));

  if (!Array.isArray(out.questions) && Array.isArray(out.clarifying_questions)) {
    out.questions = out.clarifying_questions;
    acts.push('questions_alias_normalized');
  }
  if (Array.isArray(out.questions)) {
    out.questions = out.questions.map(q => (typeof q === 'string' ? { ask: q, why: '' } : q));
  }
  const rawQ = Array.isArray(out.questions) ? out.questions.length : 0;
  out.questions = rawQ > 2 ? out.questions.slice(0, 2) : (Array.isArray(out.questions) ? out.questions : []);
  if (rawQ > 2) acts.push(`questions_truncated:${rawQ}->2`);

  out.understanding = String(out.understanding || '');
  out.needs_clarification = !!out.needs_clarification;
  out.reality_feedback_prompt = String(out.reality_feedback_prompt || '');
  out.safe_next_action = out.safe_next_action || null;
  out.fallback_if_refused = String(out.fallback_if_refused ||
    '如果你不愿把内容交给 AI：把这件事改写成几个关键词，优先查对应的官方机构、实际服务提供方或真实平台；仍无法判断时，再找这个领域的人工客服、专业人员或现实中的人确认。');

  // 资源必须绑定本轮有效证据；模型自报的来源字段一律作废
  out.resources = (Array.isArray(out.resources) ? out.resources : []).slice(0, 3).map(r => {
    const x = Object.assign({}, r);
    if (x.source_url || x.source_title || x.source_type) {
      acts.push(`model_source_ignored:${x.name || '?'}`);
      dropped.push(`${x.name || '未命名资源'}：模型自报的来源不作数，已作废`);
    }
    delete x.source_url; delete x.source_title; delete x.source_type; delete x.checked_at;

    const id = String(x.evidence_id || '');
    if (!id) { dropped.push(`${x.name || '未命名资源'}：没有引用任何证据，不进答案`); return null; }
    if (!ev.has(id)) { dropped.push(`${x.name || '未命名资源'}：引用了本轮不存在的证据 ${id}，已删除`); return null; }

    const e = ev.get(id);
    x.source_url = e.url; x.source_title = e.title; x.source_type = e.source_type;
    x.published_at = e.published_at || ''; x.checked_at = today();
    if (!RESOURCE_TYPES.includes(x.type)) x.type = 'other';
    if (!['low', 'medium', 'high'].includes(x.confidence)) x.confidence = 'low';

    /* F1 admission：风险 × 证据授权。unverified 仍可当线索，但不得支撑高风险事实；
       量化结论来自 unverified 只降级（低置信 + 强制不确定标注），不静默放行也不全删。 */
    x.risk = claimRisk(`${x.claim || ''} ${x.why || ''} ${x.name || ''}`);
    x.high_risk = x.risk === 'high_risk';
    if (x.source_type === 'unverified' && x.risk === 'high_risk') {
      dropped.push(`${x.name}：高风险结论的证据未获授权，按 admission 规则删除`);
      acts.push('resource_rejected_unverified_high_risk');
      return null;
    }
    if (x.source_type === 'unverified' && x.risk === 'important') {
      x.confidence = 'low';
      downgrades.push(`${x.name}：量化结论的证据未获授权，已降级为低置信线索，行动前请自行核实`);
      acts.push('resource_downgraded_unverified_important');
    }
    /* 时效旗标：高风险资源的证据若确认较旧或无法确认发布时间，如实标注"是否现行需核对"。
       （真实复放：2019 年媒体转载被当成现行入口；provider 常不给发布时间，退而从 URL 提取年份。） */
    if (x.risk === 'high_risk') {
      const pubYear = (String(x.published_at || '').match(/(20\d{2})/) || (String(x.source_url || '').match(/(20\d{2})/)) || [])[1];
      const age = pubYear ? new Date().getFullYear() - Number(pubYear) : null;
      if (age === null || age > 3) {
        downgrades.push(`${x.name}：该证据${age === null ? '未能确认发布时间' : `发布于 ${pubYear} 年，较旧`}，口径是否仍然现行请在行动前核对`);
        acts.push('resource_freshness_flagged');
      }
    }
    return x;
  }).filter(Boolean);

  const backed = out.resources.filter(r => r.source_type !== 'unverified');
  const p = out.recommended_path;
  if (p && typeof p === 'object') {
    const ids = Array.isArray(p.evidence_ids) ? p.evidence_ids : [];
    const valid = ids.filter(i => ev.has(i));
    if (ids.length !== valid.length) acts.push(`path_evidence_dropped:${ids.length - valid.length}`);
    p.evidence_ids = valid;
    /* F2：路径与资源同一把 admission 尺。id 存在 ≠ 授权——
       高风险路径的 backing 必须含非 unverified 证据（引用的证据或保留下来的资源）。 */
    const authorityBacked = valid.some(i => (ev.get(i) || {}).source_type !== 'unverified') || backed.length > 0;
    const risk = claimRisk(`${p.summary || ''} ${p.why || ''} ${p.first_action || ''}`);
    if (risk === 'high_risk' && !authorityBacked) {
      out.recommended_path = null;
      dropped.push('确定路径含高风险判断，引用的证据均未获授权，已撤回');
      acts.push('path_revoked_unverified_backing');
    } else if (risk !== 'normal' && !authorityBacked) {
      downgrades.push('这条推荐路径引用的证据未获授权，其中的量化与结论性表述只当线索，行动前请自行核实');
      acts.push('path_downgraded_unverified_backing');
    }
  }

  // safe_next_action 是契约里指定的降级目标：动作本身不是"确定结论"，不能一看到高风险词就删掉。
  // 只做两件事：动作形态的保留并标注需自己核实；不像动作的（更像断言）才中性化。
  // F1：进入判定的尺子从词表换成三级 claimRisk——量化的断言形态动作也逃不过。
  const ACTION_SHAPED = ['打', '拨', '问', '记', '录', '查', '搜', '写', '列', '数', '约', '联系', '打开', '整理', '提交', '准备', '带', '挂'];
  if (out.safe_next_action && claimRisk(out.safe_next_action) !== 'normal') {
    if (ACTION_SHAPED.some(v => out.safe_next_action.indexOf(v) !== -1)) {
      out.uncertainties.push('这条立即动作里提到的具体部门或入口，请当作待核实的线索，别当成已经确认的结论；先按它动起来，同时自己核对一次归口。');
      acts.push('safe_action_kept_flagged');
    } else {
      dropped.push('立即动作读起来像一条未经证实的结论，已换成不做任何事实断言的通用动作');
      out.safe_next_action = NEUTRAL_ACTION;
      acts.push('safe_action_neutralized');
    }
  }

  out.uncertainties = (Array.isArray(out.uncertainties) ? out.uncertainties : []).concat(downgrades, dropped);
  if (!out.recommended_path && !out.safe_next_action && !out.questions.length) {
    out.safe_next_action = NEUTRAL_ACTION;   // 撤回之后也不能把人晾在原地
    acts.push('neutral_floor_action_added');
  }
  out.meta = Object.assign({}, out.meta, { guard_actions: acts, dropped_claims: dropped });
  return out;
}
