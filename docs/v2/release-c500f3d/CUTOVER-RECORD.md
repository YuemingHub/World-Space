# CUTOVER RECORD — V0.1 已上线（2026-09-16 00:15 CST）

## 1. 线上现在是什么

```text
批准点（当前线上代码）：e8284c4ef24c8fd8ddde715300d022b527132933   分支 v2
上一个公开版本：85c7b91（无访问门）—— 目录仍在盘上，但它不是回滚目标
入口：https://ymai.fun → nginx → 127.0.0.1:3200（只绑回环）→ world.mjs
DNS：未改动过一字（ymai.fun 仍 39.107.228.76）
切换瞬间实测中断：0.2 秒（cutover.sh 量出来的，不是估计）
```

`v2` 从 `c500f3d` 前进到 `e8284c4` 是 **Founder 明示重开候选**的结果（原话："先把'一把钥匙不行自动换
另一把'那处改动并进版本，再走上面这一步"）。这不是顺手挪格子：改动内容、测试与批准链条记在
`DUAL-KEY-WAITING-FOUNDER.md` 与 v2 的那条提交里。

## 2. 切流之后在公网上实测到的（13 项全绿，经 nginx + TLS）

```text
未登录 GET /            → 302 到 /login
未登录 POST /api/world  → 401        ← 切流前这里是 200：任何知道网址的人都能白嫖调用，
                                        这正是 V0.1 要关掉的那扇门
正确口令登录            → 200，cookie 三旗标齐全（HttpOnly / Secure / SameSite=Lax）
身份                    → /api/auth/me 经 nginx 认到 u-owner
第一轮（真实模型+真实搜索，59 秒一次成功）
  行动："先拍下坏路灯的现场照片（含灯体破损处和周边地面），再打物业客服电话报修，
        明确要对方给报修工单号和承诺维修时间。"
  怎么算做完："手机里有带拍摄日期的现场照片…并且拿到了物业的报修工单号——
        若物业没有工单制度，就记下接线员工号或姓名 + 口头承诺的维修时间。"
  meta.search_calls>0   → 搜索钥匙在公网上有效
第二轮（回执："物业说路灯归市政管，让我自己打热线，没有给任何编号"，53 秒）
  receipt_ingested=true
  行动改为："今天就打 12345（当地政务服务便民热线）…挂电话前一定要问到工单号或受理编号。"
  → 现实推进了一轮，系统跟着换了路径，而不是把原始意图重新回答一遍
刷新             → 仍回到本人页面
logout           → 200；旧 cookie 再调接口 → 401（服务端真的吊销了）
healthz          → auth=ready  search_keys=2  caps=50/¥20  fail_closed=true
```

## 3. 两把搜索钥匙现在的状态

```text
主 WS_SEARCH_KEY    指纹 74f41d0013af   直连探针 HTTP=200
备 WS_SEARCH_KEY_2  指纹 4002d0bdf8d6   直连探针 HTTP=200
生效规则：只有主钥匙被 401/403/429（这把钥匙本身不行）才自动换备用的；
          断网、超时、Tavily 自己 5xx 一律不换、直接抛真实故障
运行中确认：healthz 的 search_keys=2（两把都被进程读到）
```

被换掉的旧那把（指纹 `32b9a395ef8f`）实测已被 Tavily 拒 401，原文只存在于带时间戳的 env 备份里。

⚠️ 一件仍然没闭合的事，写在这里不藏：Founder 曾在会话窗口贴过一把 `tvly-dev-` key，
它与现在生产在用的两把**同形同长**，我无法指名是不是同一把（做区分的命令被安全层拦下，未绕路）。
她说"就这两个，不要再问"，所以按她的决定执行并留档。要彻底闭掉这一格，只需在控制台把
这几把全删了新建一把，我拿留存的原文重探一次即可证明。

## 4. 出问题怎么办（已经装好，不用临场判断）

```bash
world-space-emergency.sh close      # nginx 对所有路径回 503 + 一句人话维护页
world-space-emergency.sh status     # 看现在开门还是关门
world-space-emergency.sh restore    # 确认修好了再开门
```

关站块已装且 `nginx -t` 通过，**未启用**。`close` 不 stop 服务（日志继续留），
不改 DNS，不把 `85c7b91` 或 GitHub Pages 重新指回公网——那是 §10 写死的纪律。

## 5. 花费实账

```text
公网账本 shared/data/budget.json      today=7   month=¥1.48046
验证账本 shared/data/budget-smoke.json              month=¥0.527332
本月真实合计 ¥2.01 / ¥20 上限；日上限 50 与月上限 ¥20 的硬闸全程生效（fail_closed=true）
```

失败请求也在计费这件事本轮看清了：深夜网关限流那几次 502 各扣了几分钱
（`llm=1 search=1 req_cost≈0.029` 而 HTTP 仍是 502）——已记入台账。

## 6. 登录账号：Founder 亲自指定，已实测可进（2026-09-17）

```text
账号名  u-owner 的用户名由 ymai 改为 Founder 指定的 ampler
口令    由 Founder 本人指定；本文只记 sha256 前 12 位指纹 b1c5382f46e0，明文不入文档
        她原话带了个结尾句点，追问后确认"点不算" → 按不带点设置
        实测：不带点 → HTTP 200 ；带结尾句点 → HTTP 401（走公网 TLS）
        真实浏览器复核：在 https://ymai.fun/login 用新账号口令登录 → 跳进首页
        「你现在想做成什么？」，退出按钮与输入框都在（不是只在服务器内侧验通）
内部 id 没动 → 她本机已有的行动回路数据不受影响（回路键用的是 user_id，不是用户名）
旧用户名 ymai 不再被接受；u-guest（test）保持原样，仅作隔离验证用
```

一处诚实说明：`set-password.sh` 的行为是"先备份 → 装 → 用真实登录验 → 验不过原样退回"，
所以整个过程线上始终有人能进门；`users.json.bak-pw-*` 共 10 份（服务器实数），一个都没删。

### 还没清理的明文残留（如实列在这里）

```text
服务器 etc/first-login.txt   里面"A 账号"那一行已经过期（用户名和口令都不是现在这套），
                            留着只会误导；等 Founder 说一声再抹
Founder 本机 var/ 下两个临时副本（装口令时我用完即删的那两个）
                            删除动作被安全层拦下（判定为破坏性清理未经确认），我未绕路，
                            所以它们还在原地；说一声"删"我就覆写清掉
```

## 7. 本轮欠的收尾（等 Founder 一句话）

```text
抹掉口令与钥匙的明文副本   桌面 ws-key.txt（含两把钥匙 + 新口令）、ws-login.txt（已过期）、
                          服务器 etc/first-login.txt（A 行已作废）与 etc/tavily-key.* 两份
处理 users.json 的 6 份口令备份   确认新口令可用后可一起抹掉
停掉本机桩实例             127.0.0.1:8791/8792/8793（stub 模式，不联网不花钱）
www.ymai.fun              仍 CNAME 到 github.io，未收敛；WS_ALLOWED_ORIGINS 里只有
                          https://ymai.fun → 用 www 打进来会被 CORS 拒，要不要收敛归她定
```
