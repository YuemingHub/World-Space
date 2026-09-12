/*
 * 授权判定正负控自测。全部合成域名，不联网、不是搜索结果、不进任何 pilot 报告。
 * 负控：形似假亲戚必须 unverified；正控：规则内域名按现有设计判定。
 * 残留检查：曾在评测数据白名单里的 zscx.osta.org.cn 现在必须是 unverified——
 * 证明"评测 → 运行时授权"的通路已彻底拆除。这不是给 pilot 种答案，恰恰相反：
 * pilot 会搜到什么、能不能拿到授权，系统事先一个都不知道。
 */
import { authority, hasHighRisk } from '../server/evidence.mjs';

const NEGATIVE = [
  'https://evilxinhuanet.com/a',
  'https://fakepeople.com.cn/a',
  'https://not-thepaper.cn/a',
  'https://xinhuanet.com.attacker.example/a',
  'https://fakegov.cn/a',
];
const POSITIVE_TRUSTED = [
  'https://xinhuanet.com/',
  'https://www.xinhuanet.com/a',
  'https://people.com.cn/',
  'https://www.people.com.cn/a',
  'https://www.thepaper.cn/newsDetail_x',
];
const POSITIVE_GOV = [
  'https://gov.cn/',
  'https://www.gov.cn/a',
  'https://jubao.mee.gov.cn/netreport/index',
  'https://www.tsinghua.edu.cn/',
];
const RESIDUE = ['https://zscx.osta.org.cn/', 'https://www.12306.cn/'];

let failures = 0;
function expect(label, list, type) {
  const bad = list.filter(u => authority(u).source_type !== type);
  const ok = bad.length === 0;
  console.log(`${ok ? '✓' : '✗'} ${label}: ${list.length} 条全部 ${type}${ok ? '' : '，未达标：' + bad.join(', ')}`);
  if (!ok) failures++;
}

expect('负控（假亲戚域名）', NEGATIVE, 'unverified');
expect('正控（权威媒体规则）', POSITIVE_TRUSTED, 'trusted_secondary');
expect('正控（政府/教育域名规则）', POSITIVE_GOV, 'official_primary');
expect('残留检查（原评测白名单域名）', RESIDUE, 'unverified');

// 非 URL 与空串也必须安全降级
const junk = authority('not a url') .source_type === 'unverified' && authority('').source_type === 'unverified';
console.log(`${junk ? '✓' : '✗'} 非 URL / 空串降级为 unverified`);
if (!junk) failures++;

// 高风险词表必须仍然把热线类断言标为高风险（这是"热线要有证据"的机制，不是答案来源）
const hr = hasHighRisk('打 12345 问归口') && hasHighRisk('直接拨打 110 即可') && !hasHighRisk('记录三个晚上的噪声时间');
console.log(`${hr ? '✓' : '✗'} 高风险词表仍咬住热线类断言，且不误伤普通动作`);
if (!hr) failures++;

console.log(failures ? `\n失败 ${failures} 项` : '\n授权正负控全部通过（合成域名，非搜索结果）');
process.exitCode = failures ? 1 : 0;
