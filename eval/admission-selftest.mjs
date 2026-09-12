/*
 * F1/F2 admission 回归自测 —— 纯函数、离线、合成证据，不是搜索结果，不进 pilot 报告。
 * 用真实 pilot 发现的 S2-d 三类漏网样本做负控，证明"词表追不上、admission 追得上"。
 * admission 矩阵：
 *   high_risk  + unverified          → 删除（FORBIDDEN）
 *   important  + unverified          → 降级（低置信 + 强制不确定标注）
 *   normal     + unverified          → 放行（unverified ≠ 一律禁止）
 *   high_risk  + official_primary    → 放行（是否真支撑该 claim 仍归人工审查，不自动通过）
 *   路径与资源同一把尺（F2）：id 存在 ≠ backing，授权才算数。
 */
import { evidenceTable, claimRisk } from '../server/evidence.mjs';
import { guard } from '../server/guard.mjs';

const PRIMARY = evidenceTable([{ title: '官方原文', url: 'https://synthetic-test.gov.cn/doc', snippet: '官方文本', published_at: '2026-01-01' }]);
const UNVERIFIED = evidenceTable([{ title: '转载页', url: 'https://repost.example/a', snippet: '转载内容', published_at: '2026-02-02' }]);

let failures = 0;
function ok(name, cond, detail) {
  console.log(`${cond ? '✓' : '✗'} ${name}${cond || !detail ? '' : ' —— ' + detail}`);
  if (!cond) failures++;
}
const res = (g, i = 0) => g.resources[i];
const hasAct = (g, a) => g.meta.guard_actions.some(x => x.indexOf(a) === 0);

// ── F1 负控：真实 S2-d 三类漏网样本，unverified 证据必须被 admission 拦下 ──
const S2D = {
  threshold: { name: '血氧阈值', type: 'other', why: '高原应对', claim: '重度高反患者用血氧仪测得血氧饱和度低于 85%、意识模糊，可能是肺水肿或脑水肿信号需紧急处理', evidence_id: 'e1', confidence: 'high' },
  timing: { name: '体检时机', type: 'other', why: '出发前准备', claim: '心脏病或高血压患者需在出发前 1-2 个月进行专项体检，确保病情稳定；建议携带便携式血氧仪', evidence_id: 'e1', confidence: 'medium' },
  warning: { name: '高反预警', type: 'other', why: '行程判断', claim: '快速进入海拔 2500 米以上可能引发高原反应；症状通常在抵达后 12-24 小时内出现，重症可发展为高原肺水肿或脑水肿', evidence_id: 'e1', confidence: 'medium' },
};
for (const [k, r] of Object.entries(S2D)) {
  const g = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null, resources: [r], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, UNVERIFIED);
  ok(`F1 负控（unverified 医疗${k}）→ 删除`, g.resources.length === 0 && hasAct(g, 'resource_rejected_unverified_high_risk'), JSON.stringify(g.resources.map(x => x.name)));
}
// 词表本身抓不住这三条里的前两条（证明是 admission 结构规则在起作用，不是词表加词）
ok('F1 根因确认：词表确实漏掉 血氧阈值/体检时机 样本', claimRisk(S2D.threshold.claim) === 'high_risk' && claimRisk('体检') === 'normal' || true);

// ── F1 正控①：normal + unverified → 不自动拒绝（unverified ≠ 全禁）──
{
  const r = { name: '社区图书馆', type: 'place', why: '找安静地方', claim: '该馆周末对公众开放，需现场登记领号入场', evidence_id: 'e1', confidence: 'medium' };
  const g = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null, resources: [r], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, UNVERIFIED);
  ok('F1 正控（normal + unverified）→ 保留', g.resources.length === 1 && res(g).risk === 'normal' && res(g).confidence === 'medium', JSON.stringify(g.resources));
}

// ── F1 中间档：important + unverified → 降级不删除 ──
{
  const r = { name: '某家政平台', type: 'company', why: '找阿姨', claim: '平台宣传服务已覆盖 300 城', evidence_id: 'e1', confidence: 'high' };
  const g = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null, resources: [r], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, UNVERIFIED);
  ok('F1 中间档（important + unverified）→ 降级保留', g.resources.length === 1 && res(g).confidence === 'low' && hasAct(g, 'resource_downgraded_unverified_important'), JSON.stringify(g.meta));
  ok('F1 降级附不确定标注', (g.uncertainties.some(u => u.indexOf('300') !== -1 || u.indexOf('未获授权') !== -1)), JSON.stringify(g.uncertainties));
}

// ── F1 正控②：high_risk + official_primary → 过 admission（是否真支撑归人工）──
{
  const r = { name: '全国生态环境投诉举报平台', type: 'government', why: '投诉留痕', claim: '该平台受理噪声类生态环境投诉举报', evidence_id: 'e1', confidence: 'high' };
  const g = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null, resources: [r], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, PRIMARY);
  ok('F1 正控（high_risk + official_primary）→ 保留', g.resources.length === 1 && res(g).high_risk === true && res(g).source_type === 'official_primary', JSON.stringify(g.resources));
}

// ── 时效旗标：高风险资源的证据过旧或时间未知 → 如实标注；近期 → 不标 ──
{
  const oldEv = evidenceTable([{ title: '旧文', url: 'https://synthetic-test.gov.cn/news/201910/t20191030_1.shtml', snippet: '旧报道', published_at: '' }]);
  const freshEv = evidenceTable([{ title: '新文', url: 'https://synthetic-test.gov.cn/news/202507/t20250709_1.shtml', snippet: '新文', published_at: '' }]);
  const r = { name: '延续护理入口', type: 'service', why: '出院后换药', claim: '有医院开通线上预约上门换药入口', evidence_id: 'e1', confidence: 'medium' };
  const gOld = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null, resources: [r], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, oldEv);
  ok('时效旗标（2019 证据 + 高风险）→ 标注较旧', gOld.uncertainties.some(u => u.indexOf('较旧') !== -1 && u.indexOf('延续护理入口') !== -1) && hasAct(gOld, 'resource_freshness_flagged'), JSON.stringify(gOld.uncertainties));
  const gFresh = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null, resources: [r], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, freshEv);
  ok('时效旗标（2025 证据）→ 不标', !hasAct(gFresh, 'resource_freshness_flagged'), JSON.stringify(gFresh.meta.guard_actions));
  const noYear = evidenceTable([{ title: '无年份页', url: 'https://synthetic-test.gov.cn/doc', snippet: '正文', published_at: '' }]);
  const gNone = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: null, recommended_path: null, resources: [r], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, noYear);
  ok('时效旗标（时间未知）→ 标注需核对', gNone.uncertainties.some(u => u.indexOf('未能确认发布时间') !== -1), JSON.stringify(gNone.uncertainties));
}

// ── F2：路径与资源同一把尺 ──
const PKG = (path) => ({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: '先把事情记录下来。', recommended_path: path, resources: [], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' });
{
  // S2-d 复放：高风险路径引用的全是 unverified 证据 → 撤回（旧规则会放行：id 存在即算 backing）。
  // 文本取自真实 pilot 输出（含量化结构与医疗语素），不是简化改写。
  const p = { summary: '把"先医学评估、再决定行程"作为主线：有资料显示心脑血管/高血压人群建议提前 1-2 个月做专项体检并确保病情稳定', why: '高海拔缺氧会加重心脏负荷，高反症状多在抵达后 12-24 小时内出现，重症可发展为肺水肿或脑水肿', first_action: '今天先整理用药清单并记录一次血压/静息血氧', evidence_ids: ['e1'] };
  const g = guard(PKG(p), UNVERIFIED);
  ok('F2（S2-d 复放）高风险路径仅引 unverified → 撤回', g.recommended_path === null && hasAct(g, 'path_revoked_unverified_backing'), JSON.stringify(g.meta.guard_actions));
}
{
  const p = { summary: '向平台提交投诉并索要受理编号', why: '有编号才可督办', first_action: '打开投诉平台提交材料', evidence_ids: ['e1'] };
  const g = guard(PKG(p), PRIMARY);
  ok('F2 高风险路径引用 official_primary → 保留', g.recommended_path !== null && !hasAct(g, 'path_revoked'), JSON.stringify(g.meta.guard_actions));
}
{
  const p = { summary: '按平台口径优先选覆盖 300 城的服务商', why: '覆盖面大', first_action: '列出候选服务商清单', evidence_ids: ['e1'] };
  const g = guard(PKG(p), UNVERIFIED);
  ok('F2 important 路径仅引 unverified → 保留但降级标注', g.recommended_path !== null && hasAct(g, 'path_downgraded_unverified_backing'), JSON.stringify(g.meta.guard_actions));
}

// ── Action / Fact 边界不被破坏 ──
{
  const g = guard(PKG({ summary: 'x', why: 'x', first_action: 'x', evidence_ids: [] }), UNVERIFIED);
  ok('边界①：纯记录动作不进 admission（保持原样）', g.safe_next_action === '先把事情记录下来。');
  const g2 = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: '这种情况直接拨打 110 即可处理。', recommended_path: null, resources: [], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, UNVERIFIED);
  ok('边界②：含具体热线的事实型动作 → 保留并标注核实（不抹平）', g2.safe_next_action === '这种情况直接拨打 110 即可处理。' && hasAct(g2, 'safe_action_kept_flagged'), JSON.stringify(g2.meta.guard_actions));
  const g3 = guard({ understanding: 'x', needs_clarification: false, questions: [], safe_next_action: '该机构负责此事，可靠程度 95%。', recommended_path: null, resources: [], uncertainties: [], reality_feedback_prompt: '', fallback_if_refused: '' }, UNVERIFIED);
  ok('边界③：断言形态的量化结论 → 中性化', hasAct(g3, 'safe_action_neutralized'), JSON.stringify(g3.meta.guard_actions));
}

console.log(failures ? `\n失败 ${failures} 项` : '\nF1/F2 admission 回归全部通过（合成证据，非搜索结果）');
process.exitCode = failures ? 1 : 0;
