# EMERGENCY CLOSED STATE — V0.1 的回滚语义（切流前必须装好）

> 2026-09-15。批准候选：`v2` @ `c500f3d`。本文只讲一件事：**出问题的时候往哪里退**。

## 0. 一句话原则

```text
认证版本出问题 → 宁可关站 → 不能回到公开版
OLD PUBLIC VERSION ≠ SECURITY ROLLBACK
```

## 1. 为什么 85c7b91 不是回滚目标

`85c7b91`（当前公网在跑的版本）**没有访问门**：任何知道地址的人都能直接调用它，
不需要账号、不区分用户、没有登录限流。把它当成"出问题的安全出口"，等于用一次故障
换一次更大范围的暴露——这比停站更糟。

同样不能作为回滚目标的还有：

```text
main 分支的 GitHub Pages 静态站（无门、且没有 V0 回路）
更早的中间提交（6e73725 等，同样无门）
任何"先把旧版本重新指回 DNS"的临时救火
```

**因此本次发布的回滚梯度只有两级：**

| 情况 | 动作 | 结果 |
|---|---|---|
| 新版本能用，只是某个功能不对 | 在**含访问门的本系列提交**之间回退 `current` 并重启 | 门还在，功能回到旧行为 |
| Node / 认证 / 入口出现核心故障，来不及判断 | `world-space-emergency.sh close` | 公网 503 维护页，不代理任何应用、不指向任何旧公开版 |

若本系列内没有可回退的更早提交，就直接关站。**关站是可接受的，泄密不可接受。**

## 2. 关站状态下仍然保留的东西（备份 ≠ 回滚目标）

```text
/opt/world-space/current                     仍然指向切流前那个版本，不动
/opt/world-space/releases/<每个 SHA>/        全部保留，一个都不删
/opt/world-space/shared/env/world-space.env  600，含 .bak-* 备份，全部保留
/opt/world-space/shared/data/budget.json     保留（账本不因关站清零）
world-space.service                          本脚本不 stop 它：Node 继续跑，只是公网不再代理过来
DNS / 解析记录                                一个字都不改（切流前根本没用 DNS 做过开关）
```

维护页正文只有一句"World Space 暂时不可用，请稍后再试。"，`no-store`、`noindex`、
不带 cookie、不含用户名、不含任何用户内容、不引用 CDN 或外部资源。

## 3. 切流前要做的三件事（顺序不能换）

```bash
# 3.1 装：把关站文件放到服务器（脚本会自动与线上 server_name / 证书路径核对）
scp docs/v2/release-c500f3d/emergency-closed/{world-space-closed.conf,maintenance.html,world-space-emergency.sh} \
    root@server:/opt/world-space/emergency/staging/
install -m 755 /opt/world-space/emergency/staging/world-space-emergency.sh /usr/local/bin/world-space-emergency.sh
world-space-emergency.sh install          # 必须 nginx -t 通过；只放置，不启用

# 3.2 验：用独立 nginx 进程在 127.0.0.1:8088 上验证"503 + 维护页"这套机制真的成立
world-space-emergency.sh preflight        # 期望 PREFLIGHT=PASS；不影响在跑的 nginx 与公网

# 3.3 记：把当前入口层状态留档，事后能区分"谁动的"
world-space-emergency.sh status | tee /opt/world-space/emergency/state/status-before-cutover.txt
```

**切流之前不允许演练 `close`**——那会让公网（当时是 85c7b91）短暂 503。
需要演练就在 Founder 指定的维护窗口里做，并提前说明会中断几十秒。

## 4. 出事时的动作

```bash
world-space-emergency.sh close      # 一条命令：换符号链接 -> nginx -t -> reload -> 逐 host 验证 503
```

脚本自带保险：`nginx -t` 不过就自动把符号链接放回原位，不会留下"半开"的入口层。

之后：

```bash
world-space-emergency.sh status             # 确认 CLOSED（已关站）
journalctl -u world-space.service -n 100    # 关站不影响 Node 继续留日志，事后取证用
curl -s http://127.0.0.1:3200/healthz       # 机内自查认证门状态：broken / ready / off
```

恢复只有在**确认根因已修好**之后：

```bash
world-space-emergency.sh restore
```

`restore` 回到的是 `current` 当前指向的版本——它可能正是出问题的那个版本，所以
restore 不是"撤销故障"，只是"重新开门"。

## 5. 这个方案没有覆盖什么（如实说明）

- 不防应用层的越权读写：关站是断总闸，不是修漏洞。用户数据只在各自浏览器
  `localStorage` 里，服务端本就没有用户正文库，所以关站即止住新的暴露。
- 不做流量隔离式灰度（单实例部署语义，见 `AUTH_UI_PREDEPLOY_HANDOFF.md` §10.1）。
- 维护页不显示工单入口/邮箱（刻意：不引入任何第三方资源与身份信息）。
- DNS 侧的 Pages 记录仍是 09-14 置 DISABLE 的三条（未删除）。**它们不属于回滚路径**，
  重新启用即等于"切回无门公开站"，必须与 close 一样被禁止，除非 Founder 明确重开候选。
