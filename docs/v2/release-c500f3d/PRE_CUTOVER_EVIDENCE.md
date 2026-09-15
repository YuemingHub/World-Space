# PRE-CUTOVER EVIDENCE — V0.1 @ c500f3d（2026-09-15 本轮实际做过的事）

> 候选：`v2` @ `c500f3d76601abb263511cb622efd38379e8b959`。
> 本轮**未改动公网**：`ymai.fun`、DNS、Nginx 入口、`current` 指向、`world-space.service`、共享生产 env 全部原样。
> 本文不含任何真实密钥值。

## 1. 候选锁死（§1）

```text
本地 v2            = c500f3d76601abb263511cb622efd38379e8b959
origin/v2          = c500f3d76601abb263511cb622efd38379e8b959
working tree       clean（本轮发布准备物在分支 release/v01-c500f3d，v2 保持冻结）
Gate 运行时的代码树 = c500f3d 本身（该分支相对 c500f3d 只有 docs 差异：
                     git diff c500f3d --stat → 仅 docs/v2/AUTH_UI_DEPLOY_CHECKLIST.md）
```

不在 `v2` 上追加提交是刻意的：Gate 的判定要求 `HEAD = origin/v2 = 批准 SHA`，
任何为准备发布而加的提交都会让这句话变成假话。发布物一律走 `release/v01-c500f3d`。

## 2. Gate 全量复跑（§11）— 开发机新鲜一次，服务器侧待授权后重跑

`2026-09-15T10:52Z` 在 `c500f3d` 树上全量跑，13/13 绿。全部离线桩
（127.0.0.1 + `*.example`/`*.invalid` 合成域名，0 外网请求，0 花费）：

```text
runtime-isolation PASS   authority PASS   adapter-shape PASS   admission PASS
retry PASS               liveness PASS    xss-boundary PASS    budget-cap PASS
date PASS                outcome-loop PASS frontend-e2e PASS   runtime PASS
auth PASS (4s, 42+ 断言)
```

这不是"引用开发机之前的绿灯"——是本 SHA 本轮现跑的。
但它仍然**不是服务器发布树的绿灯**：`ws-prep.sh gates` 必须在
`/opt/world-space/releases/c500f3d…/` 里再跑一遍才算 §11 完成。日志在
`eval/out/local-gate-c500f3d/`（gitignore）。

## 3. UI 本机检查（§13）— 实测数字，不是印象

本地起桩实例（`WS_PROVIDER=stub`，`WS_SEARCH=fixture`，`WS_LIVENESS=0`，只绑 127.0.0.1，
访问门开着，fixture 用户来自自测文件）。宽度用同源 iframe 真实视口，媒体查询按该宽度生效。

登录页 `/login`：

```text
320 / 390 / 414 / 1280 四档：scrollWidth - innerWidth = 0，无一个元素越过视口右边界
输入框高 52px，「进入」按钮 48px 宽 280-300px，单列居中；label 只有 账号 / 密码
```

首页 `/`：`h1` 唯一且是「你现在想做成什么？」（移动 28px / 桌面 32px），
未登录直接 302 到 `/login`（实测 `GET / -> 302`）。

结果页（human 模式，receipt 桩）：

```text
.action = "今天给物业打电话正式报修这两盏路灯，要一个工单号或接待人姓名"
.done-when 可见 = "怎么算做完：拿到工单号，或物业给出明确的修复时间"（15px）
"这一步要你本人进入现实世界。" + 页面内 <a> 数量 = 0  → human 场景没有塞外部 AI 入口
可见按钮全部 46px：复制这句话 / 做成了 ✓ / 卡住了 / 把结果带回来 / 换个新目标
折叠 3 组（为什么是这一步 / 世界上已经有什么 / 还有什么没有确定）全部可展开且有真实内容
不确定性摘要行直接露出第一条：「还有什么没有确定（1）——路灯的具体归口…本轮未核实」
"世界上已经有什么" 在无匹配资源时如实写"没有找到足够可信的现实资源，所以不硬塞"
```

结果页（handoff 模式，handoff 桩）：

```text
任务书块在；两个复制按钮文案不同（复制任务书 / 复制这句话）
唯一外链 = https://chat.deepseek.com/ （rel="noopener noreferrer" target="_blank"）
  → 链接来自前端白名单，不是模型给的 URL
```

本轮记录到的一条真实观察（不改 UI，交给 Founder 判断）：

```text
顶栏「退出」在四档宽度下实测高 36px，低于 44px 触控目标建议值；
它是顶栏次要动作，V0.1 可接受，但这是数字，不是感觉。
```

## 4. 访问门与运行边界（§3 §6 §7 §8 §9 — 代码侧事实，配置侧待服务器）

```text
fail closed        auth-selftest 覆盖：缺用户文件/缺 secret/坏 hash → healthz broken、
                   业务接口 503 auth_unavailable、页面弹 /login；运行中删文件立即生效
单实例语义         预算文件 + 内存登出吊销表，无 cluster/worker 配置
只监听本机         WS_HOST 默认 127.0.0.1（本轮桩实例实测 ss 只见 127.0.0.1）
Cookie             HttpOnly + SameSite=Lax + Path=/；Secure 由 WS_COOKIE_SECURE=1
                   或（受信反代 + X-Forwarded-Proto: https）自动开
Proxy              默认只认 socket 对端，开了 WS_TRUST_PROXY 才读转发头（不看客户端 XFF）
CORS               代码里不存在 '*'：只回显"被允许的那个 Origin"，且响应不带
                   allow-credentials → 跨源带凭据的请求在浏览器层就不可能；
                   非白名单 Origin → 403 origin_not_allowed
                   生产必须设 WS_ALLOWED_ORIGINS=https://ymai.fun（未设时=本地模式，
                   只放 localhost/127.0.0.1 与无 Origin 的请求）
预算               WS_DAILY_CAP=50 / WS_MONTHLY_CAP_RMB=20 是本 SHA 的默认值，
                   开发期为自测抬高过的额度不得带上线（服务器 env 逐项核对，见 §待办）
```

## 5. 回滚语义修正（§10）

`docs/v2/AUTH_UI_DEPLOY_CHECKLIST.md`：

- §8 原文"切回上一个批准 SHA 重启即可"作废 → 两级回滚梯度 + 明确 `85c7b91`、
  `6e73725`、`main`/GitHub Pages、"改 DNS 指回旧站"都**不是**安全回滚目标；
- 新增 §9 把"搜索凭据轮换"从"上线后"清单里提到**切流前 blocker**；
- 新增 §0 记录真实部署坐标（`/opt/world-space`、端口 3200），避免照抄清单里的通用示例路径跑空。

关站方案实物（切流前必须 install + preflight）：

```text
docs/v2/release-c500f3d/EMERGENCY_CLOSED.md              说明与操作顺序
docs/v2/release-c500f3d/emergency-closed/
  world-space-closed.conf     80/443 全路径 return 503 + 维护页，不代理任何 upstream
  maintenance.html            只有"World Space 暂时不可用，请稍后再试。"，no-store/noindex
  world-space-emergency.sh    install / preflight / close / restore / status
```

三个设计点值得单独看：

1. 关站块与正常块**不能同时 enabled**（字母序 `world-space` 在前会赢，等于没关站）；
   脚本用"移动符号链接"而不是删除来互斥切换，`nginx -t` 不过就自动回退，不留半开状态。
2. `preflight` 用**独立 nginx 进程**在 127.0.0.1:8088 上验证"503 + 维护页"这套
   `error_page` 机制真的成立，不需要 reload 公网入口，也不需要拿线上做演练。
3. 关站**不 stop** `world-space.service`：Node 继续跑、日志继续留，事后能取证。

## 6. 本轮没做完的（以及各卡在哪）

```text
§11 服务器发布树 Gate   需要：服务器授权语（本轮被安全层拦下）
§2 仓库外 users/secret  需要：两个账号的口令来源
§3 fail closed 实机验证 需要：上面两项 + 本机验证实例（127.0.0.1:3210，已备好脚本）
§4 搜索凭据             需要：新 key 的落地方式（见下）
§12 正式模式 smoke      需要：§2 §3 §4 完成后才能跑，含真实调用（预计 ¥0.2～0.4）
```

### 关于搜索凭据，本轮必须先说清的事实

Founder 在会话窗口里直接贴了两把真实 key（一把 Tavily `tvly-dev-` 前缀，一把 anysearch
`as_sk_` 前缀）。**贴进聊天窗口的这一刻，它们就成了新的暴露面**，与 §4 要处理的
"历史暴露的 Tavily key"是同一类问题。因此：

```text
聊天里出现过的那两把 key：一律按"已暴露"处理，不得作为生产 key 使用
生产 key 的正确来源：在 Tavily 控制台新建，只在服务器上写入 600 的私有 env，
                     值不进聊天、不进 Git、不进日志、不进报告
OLD_TAVILY_KEY_REVOKED 的判定方法：拿旧 key 调一次真实接口看是否失效（401/403=已 revoke），
                     或控制台里该 key 显示为已删除/已停用；口头确认不作为 yes 的证据
```

本轮**没有**执行Founder 附带的另外两个动作，理由是它们不在这份 15 节简报里，
且简报开头就写了"禁止开发产品、修改 UI、调整模型逻辑"：

```text
1. 抓取并执行 tavily.com/agent-setup/SKILL.md
2. 下载 anysearch skill 压缩包并接入第二个搜索 provider（改 server/search.mjs）
这两件都是"新增能力"，不是发布收口；在一个以"不造轮子 + 内容诚信"为约束的仓库里，
从第三方 URL 拉脚本直接跑还需要单独一次授权。anysearch 那把 key 同样需要轮换
（它已经出现在会话记录里）。
```

## 7. 本机留下的运行物（如实说明）

三个本地桩实例（127.0.0.1:8791 / 8792 / 8793）在本轮结束时的停止命令被安全层拦下，
**仍在运行**。它们只绑回环、provider=stub、search=fixture，不产生任何外网请求与费用，
不碰公网。需要停可以随时说，或自己执行：

```powershell
Get-NetTCPConnection -LocalPort 8791,8792,8793 -State Listen |
  ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```
