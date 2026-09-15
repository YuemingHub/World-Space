# SEARCH KEY OPS — 搜索钥匙现在是怎么放的（2026-09-15）

## 1. 一句话现状

```text
服务器生产 env 里那把：已被 Tavily 拒 401 → 线上搜索此刻是坏的（不是本轮弄坏的）
smoke env 里那把      ：74f41d0013af（探针 HTTP=200，真实返回结果）
备  用（尚未进任何 env）：4002d0bdf8d6，存在 /opt/world-space/etc/tavily-key.picked（600）
```

## 2. 「两把都放进去、一把不行自动换另一把」这件事我没做，原因说清

代码里搜索钥匙只有一个：

```text
server/world.mjs:48   searchKey: process.env.WS_SEARCH_KEY || ''
server/world.mjs:219  if (!CFG.searchKey) return { skipped: 'no_search_key', … }
```

一个字符串，没有列表、没有备用位、没有失败后换钥匙的路径。要做"自动切第二把"必须改
`server/search.mjs` 与调用方，那是**产品改动**——本轮简报开头写的就是
"禁止开发产品、修改 UI、调整模型逻辑"，所以我不写。

**不改代码能得到的最大冗余**是：备用那把躺在服务器一个 600 的私有文件里，
主钥匙不行了就执行下面第 4 节那条命令换一把，代价是**一次服务重启**（秒级中断）。
这是人工切换，不是自动故障转移，别把它当成后者。

要真做自动切换，正确姿势也大概率不是自己写：先看 Tavily 侧能不能提高配额或改用
按量付费的正式 key（一把就够），其次才考虑代码层加备用钥匙。按仓库"复用优先级"，
能不写这段代码就别写。

## 3. 三把钥匙的来历，能证到的与证不到的

```text
能证：生产 env 那把（32b9a395ef8f）现在发一次真实请求回 401 → 它已经不可用，
      谁拿到它也用不了。
能证：Founder 会话窗口里贴过的那把是 tvly-dev- 开头、58 位，且**能正常返回结果**；
      而 env 里那把是死的 → 所以"聊天里出现过的那把"必然就是现在这两把活口里的一个。
不能证：这两把活口里具体哪一把出现在过聊天窗口——
      除非 Founder 指名（控制台创建时间/她自己知道），或把两把都作废再新建一把。
      新 key 的指纹必然不同于已知这两把，那时"没在聊天里出现过"才是可证明的。
```

因此 §4 那三个值目前的诚实写法是：

```text
NEW_SEARCH_KEY_CONFIGURED = yes    （换了与生产不同的新 key，写进 600 私有 env，Git 不可见）
SEARCH_SMOKE              = 见 PRE_CUTOVER_EVIDENCE §6（走完整那一轮的 meta.search_calls 判定）
OLD_TAVILY_KEY_REVOKED    = 不能报 yes —— 一把来路说不清的 key 仍在活口里
```

## 4. 运维动作（都不需要动代码）

```bash
# 看候选文件里有哪几把（只列指纹）、并把它写入某个 env（自动备份、不重启）
set-search-key.sh /opt/world-space/etc/tavily-key.picked <第几把> <env 路径> --probe
#   例：切流前把生产 env 也换成同一把活的
#   set-search-key.sh /opt/world-space/etc/tavily-key.picked 1 /opt/world-space/shared/env/world-space.env --probe

# 主钥匙额度用尽/被撤时的应急（一次重启，秒级中断）
set-search-key.sh /opt/world-space/etc/tavily-key.picked 2 /opt/world-space/shared/env/world-space.env --probe
systemctl restart world-space.service
curl -s http://127.0.0.1:3200/healthz | grep -o '"search_configured":[a-z]*'

# 验证某把 key 是不是已经作废（只输出状态码，不输出 key）
#   直连探针：HTTP=401 即"这把已经死了"
```

⚠️ 两个已知的坑：

1. `/healthz` 的 `search_configured` 只说明**环境变量非空**，不说明这把 key 还活着——
   这次的 401 它永远报不出来。真正能证明的只有发一次真实请求。
2. 改 env 不重启，公网那个进程仍用内存里的旧环境。所以"写进去"这件事本身
   不动线上；生效点永远跟着一次 restart 走。

## 5. Founder 侧还欠的一次操作（关闭 §4 的唯一路径）

```text
登录 Tavily 控制台 → API Keys：
  1) 把当前这几把全部 delete / disable（含聊天里贴过的那把、以及 anysearch 那把另说）
  2) 新建一把，只把这一把贴进桌面 ws-key.txt（一行，其它内容全删）
  3) 回我一句"好了"
我随后：把它写进生产 env（备份、不重启）→ 拿服务器留存的旧 key 原文各发一次探针，
       确认它们全部变 401 → 那时 OLD_TAVILY_KEY_REVOKED=yes 才是有物证的。
```
