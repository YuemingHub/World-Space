/*
 * 业务日期唯一真源：服务器主机本地时区的"今天"。
 * 仓库此前有两个"今天"（运行时预算用本地日期、护栏 checked_at 用 UTC ISO），
 * 一天里 evidence 的核实日期与预算日切会各说各话。所有业务日期只许从这里取。
 * 业务日界 = 主机时区的日界（部署在哪个时区，哪里的"今天"就是业务日期）；
 * 部署在上海时区的机器上，上海 00:30 的 checked_at 必须是当天，不能是前一天。
 * now 参数只用于回归测试注入固定时刻，生产调用一律不传。
 */
export function localDate(now = new Date()) {
  const d = now instanceof Date ? now : new Date(now);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
export function localMonth(now = new Date()) {
  return localDate(now).slice(0, 7);
}
