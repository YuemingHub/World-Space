/* 日期探针子进程：注入固定时刻，打印 localDate 与 UTC 日期，供 date-selftest 断言。 */
import { localDate, localMonth } from '../server/date.mjs';
const instants = process.argv.slice(2);
const out = instants.map(s => {
  const d = new Date(s);
  return { input: s, local: localDate(d), localMonth: localMonth(d), utc: d.toISOString().slice(0, 10) };
});
console.log(JSON.stringify(out));
