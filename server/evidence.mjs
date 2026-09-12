/*
 * 证据与授权（Guard 层）。三件事：
 *   1. Evidence Binding：证据身份由服务端生成，模型只能引用 id，不能自己造 URL；
 *   2. Source Authority Guard：authority 由系统按规则授予，模型自称 official_primary 无效；
 *   3. 搜索词最小化：明显手机号/证件号/长号码在进入搜索前隐去。
 * Authority 只回答"这个域名是谁的"（政府 / 权威媒体 / 未核实），
 * 不回答"这个页面是否有资格支撑这个具体 claim"——后者靠真实 pilot 的人工审查暴露。
 * 来源只有两类，且都不读任何评测或文档数据：
 *   a. 稳定、可独立解释的域名规则（政府/教育/科研域名 + 一小撮权威媒体）；
 *   b. 将来确有需要时才建的极少量长期 registry（config/source_authority.json，
 *      每项须含 host/authority/why/checked_at，理由必须独立成立，不许"评测需要它"）。
 * 本轮只保留 a。判断不了的一律 unverified：宁可少授予，不造"互联网权威数据库"。
 * 授权表永远不写进提示词，否则它就从判定规则变成了模型的答案库。
 */
export const HIGH_RISK = ['法', '条例', '政策', '规定', '医保', '保险', '报销', '补贴', '资格',
  '证书', '职业标准', '备案', '许可', '价格', '收费', '免费', '部门', '热线', '投诉', '受理',
  '医院', '护理', '药品', '名单', '官方', '定点', '110', '12345', '12369', '12348', '12315'];

/** 高风险 = 说错了会让人白跑一趟、花错钱、或耽误病情的判断 */
export function hasHighRisk(text) {
  const s = String(text || '');
  return HIGH_RISK.some(k => s.indexOf(k) !== -1);
}

/*
 * F1 admission：claim 风险分三级（normal / important / high_risk），guard 按 风险 × 证据授权 决定放行/降级/删除。
 * 词表仍是高位基座，不扩容。真实 pilot（S2-d）证明词表追不上生成模型：
 * 体检时机、血氧阈值、肺水肿预警全是"健康域语素 + 量化断言"形态，于是只加一条结构性规则——
 *   健康域语素 × 量化断言 ⇒ high_risk；任何量化断言至少 important。
 * 语素表是封闭的一个类目（医疗），不是持续堆砌的关键词库；不做语义分类器、不加 Agent。
 */
const QUANTIFIED = /\d+(\.\d+)?\s*(%|％|个|天|日|周|月|年|小时|分钟|米|岁|度|次|元|克|毫克|升|城|人)|\d+\s*[-–~至]\s*\d+/;
const MEDICAL = ['医', '药', '病', '症', '诊', '疗', '体检', '血', '肺', '癌', '疫', '术', '急救', '抢救', '禁忌', '剂量'];
export function claimRisk(text) {
  const s = String(text || '');
  if (hasHighRisk(s)) return 'high_risk';
  if (!QUANTIFIED.test(s)) return 'normal';
  if (MEDICAL.some(m => s.indexOf(m) !== -1)) return 'high_risk';
  return 'important';
}

/** 一小撮权威二手来源，故意不做大而全的域名库；不在表里的一律降级 */
const TRUSTED_MEDIA = ['people.com.cn', 'xinhuanet.com', 'cinet.cn', 'cnr.cn', 'thepaper.cn'];

/** 授权由系统判定：官方原始 > 权威二手 > 未核实。永不升级，只会降级。
 *  域名匹配只认整段：h === t，或 h 以 '.' + t 结尾——防 evilxinhuanet.com 这类假亲戚。 */
export function authority(url) {
  let h = '';
  try { h = new URL(url).hostname.toLowerCase(); } catch (e) { return { source_type: 'unverified', host: '' }; }
  if (/(\.|^)gov\.cn$/.test(h)) return { source_type: 'official_primary', host: h };
  if (/\.(edu|ac)\.cn$/.test(h)) return { source_type: 'official_primary', host: h };
  if (TRUSTED_MEDIA.some(t => h === t || h.endsWith('.' + t))) return { source_type: 'trusted_secondary', host: h };
  return { source_type: 'unverified', host: h };
}

/** 本轮搜索结果的证据表：id 由服务端编号，模型看不到也造不了别人的 id */
export function evidenceTable(items) {
  const map = new Map();
  (items || []).slice(0, 8).forEach((x, i) => {
    const id = 'e' + (i + 1);
    map.set(id, {
      id, title: String(x.title || '').slice(0, 200), url: String(x.url || ''),
      snippet: String(x.snippet || '').slice(0, 400), published_at: String(x.published_at || ''),
      ...authority(x.url),
    });
  });
  return {
    has: id => map.has(String(id)),
    get: id => map.get(String(id)),
    size: () => map.size,
    /** 交给模型的只有 id + 标题 + 摘要 + 发布时间；URL 不给它复制的机会 */
    forPrompt: () => Array.from(map.values()).map(e => ({
      id: e.id, title: e.title, snippet: e.snippet, published_at: e.published_at,
    })),
    /** 允许模型转述的链接白名单：它引用的 id 才能解析回真实 URL */
    urlOf: id => (map.get(String(id)) || {}).url || '',
  };
}

/** 进入搜索前的最小化：去掉明显个人标识与长号码 */
export function minimizeQuery(q) {
  return String(q || '')
    .replace(/1[3-9]\d{9}/g, '[已隐去手机号]')
    .replace(/\d{17}[\dXx]/g, '[已隐去证件号]')
    .replace(/\d{8,}/g, '[已隐去长号码]')
    .replace(/\s+/g, ' ')
    .trim().slice(0, 80);
}
