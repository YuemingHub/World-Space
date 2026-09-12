/*
 * 护栏（Guard）：证据绑定 + 来源授权 + 高风险撤回 + 截断留痕 + 中性兜底。
 * 这一份是 Slice 1.1 的主体，与传输/流程分开，便于单独评审。
 * 立场：只降级，不升级；宁可撤回，不误指路。
 */
import { hasHighRisk } from './evidence.mjs';

const RESOURCE_TYPES = ['government', 'institution', 'company', 'service', 'place', 'person',
  'community', 'document', 'dataset', 'open_source', 'software', 'ai_tool', 'product', 'other'];
const NEUTRAL_ACTION = '今天先把这件事的三个要素写下来：发生时间、地点或对象、你已经做过什么。';

function today() { return new Date().toISOString().slice(0, 10); }

/**
 * @param c   模型产出的契约草稿
 * @param ev  服务端签发的本轮证据表（模型只能引用其中的 id）
 */
export function guard(c, ev) {
  const acts = [], dropped = [];
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
    x.high_risk = hasHighRisk(`${x.claim || ''} ${x.why || ''} ${x.name || ''}`);
    if (x.high_risk && x.source_type === 'unverified') {
      dropped.push(`${x.name}：证据域名未获授权，高风险结论按未核实处理，已删除`);
      return null;
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
    if (hasHighRisk(`${p.summary} ${p.why} ${p.first_action}`) && !valid.length && !backed.length) {
      out.recommended_path = null;
      dropped.push('确定路径含高风险判断却没有有效证据，已撤回');
      acts.push('path_revoked_no_evidence');
    }
  }

  // safe_next_action 是契约里指定的降级目标：动作本身不是"确定结论"，不能一看到高风险词就删掉。
  // 只做两件事：动作形态的保留并标注需自己核实；不像动作的（更像断言）才中性化。
  const ACTION_SHAPED = ['打', '拨', '问', '记', '录', '查', '搜', '写', '列', '数', '约', '联系', '打开', '整理', '提交', '准备', '带', '挂'];
  if (out.safe_next_action && hasHighRisk(out.safe_next_action)) {
    if (ACTION_SHAPED.some(v => out.safe_next_action.indexOf(v) !== -1)) {
      out.uncertainties.push('这条立即动作里提到的具体部门或入口，请当作待核实的线索，别当成已经确认的结论；先按它动起来，同时自己核对一次归口。');
      acts.push('safe_action_kept_flagged');
    } else {
      dropped.push('立即动作读起来像一条未经证实的结论，已换成不做任何事实断言的通用动作');
      out.safe_next_action = NEUTRAL_ACTION;
      acts.push('safe_action_neutralized');
    }
  }

  out.uncertainties = (Array.isArray(out.uncertainties) ? out.uncertainties : []).concat(dropped);
  if (!out.recommended_path && !out.safe_next_action && !out.questions.length) {
    out.safe_next_action = NEUTRAL_ACTION;   // 撤回之后也不能把人晾在原地
    acts.push('neutral_floor_action_added');
  }
  out.meta = Object.assign({}, out.meta, { guard_actions: acts, dropped_claims: dropped });
  return out;
}
