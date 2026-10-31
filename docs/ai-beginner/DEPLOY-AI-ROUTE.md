# `/ai/` 发布合同 · 技术裁决与授权请求

> 状态：**候选未发布**。本文件只给方案与授权请求，不执行任何生产写入。
> 依据：Commander 2026-11-01 裁决 `APPROVED_PRODUCT_DIRECTION：PARALLEL_AI_ENTRY`。
> 作者：Deep（Builder）。**2026-11-01 v2 重写**：上一版依赖源码推断，生产身份未证实；本轮用一次**只读** SSH 调查
> （证据在 `D:\服务器\repos\ws-prod-identity-20261101\report.md`）拿到了真实部署身份，并按真实事实改了方案。
> 那次调查**没有**改任何文件、没 reload/restart、没部署、没改 DNS。

---

## 1. 已证实的生产身份（2026-11-01 01:05–01:12 +08:00，只读）

| 项 | 事实 | 证据 |
|---|---|---|
| 主机 | `iZ2ze97l6qb4ej1dz40ku6Z`，Ubuntu 22.04 内核 5.15 | `hostname; uname -a` |
| 登录方式 | `aliyun-ecs` → `10.254.0.1`（WireGuard 隧道），root | `~/.ssh/config` + `uid=0` |
| nginx | `nginx/1.18.0 (Ubuntu)`，ymai.fun 只由 `/etc/nginx/sites-available/world-space` 负责 | `nginx -T \| grep server_name` |
| server 块 | ymai.fun **恰好 2 个**：80（301 到 https）+ 443 | 同上 |
| CDN / 缓存层 | **无**：无 `proxy_cache_path`，`Server:` 头为本机原生 | `nginx -T` 全量 |
| Node 服务 | `world-space.service`，`User=wsapp`，`WorkingDirectory=/opt/world-space/current` | `systemctl cat` |
| release 身份 | `current` → `releases/3e8e15f17bc5bae7fe78298661a5d5d14ce581c6`（**无 .git**，只能靠目录名） | `ls -la /opt/world-space/` |
| 静态 webDir | `/opt/world-space/releases/<sha>/web/v2/`（内含 app.js / index.html / login.html / render.mjs / style.css；**无 ai/、无 ming/**） | `ls` |
| `/` 的 302 | **是 Node 发的**（`server/world.mjs` 登录门），不是 nginx | 头含 `cache-control: no-store`；nginx 无该 location 规则 |
| `/healthz` 200 | 同样由 Node 内联返回 | 同上 |
| `/ming/` | nginx 经 `include snippets/ming-portfolio.conf` **直接读磁盘** `/var/www/ymai.fun-static`，**不经过 Node** | snippet 原文 |
| `/ming/` 完整性 | 磁盘 md5 `3bca73c4d2533e4101b96583aa2113ec` = 公网 md5，同为 29,892 字节；目录共 11 个文件（含 7 个 PDF） | 双侧 md5 |
| `/ai/` 现在 404 的原因 | nginx 没给 location → 落到 `location /` → 交给 Node → Node 的 webDir 里没有该目录 | 链路推断 + 实测 404 |
| 端口 | 3200（业务）+ 3201（诊断），**同一 pid**，均只绑 `127.0.0.1` | `ss -ltnp` |

**上一版文档的错误**（已按证据推翻）：`/srv/world-space/` 不存在；静态目录不是 `/srv/.../www/`；`webDir` 不是环境变量而是源码硬编码 `join(HERE,'..','web','v2')`。

**仍然 Unknown**：运行中 release `3e8e15f1` 与 nginx 注释里的候选 `85c7b91e` 不一致——无法判断是"注释没更新"还是"曾回滚"。这不影响本方案（本方案不依赖该 SHA），但会作为交接风险写进发布单。

## 2. 选定方案：加一个 location，指向独立静态目录

### 2.1 目标形态（不变）

```
https://ymai.fun/ai/       ← 新增：静态目录，公开只读
https://ymai.fun/          ← 不变：302 /login（Node）
https://ymai.fun/login     ← 不变
https://ymai.fun/api/*     ← 不变
https://ymai.fun/healthz   ← 不变
https://ymai.fun/ming/     ← 不变（仓库外文件，不得覆盖）
```

### 2.2 落地方案（交总运维窗口执行；本轮不执行）

**关键约束（先读）**：`/srv/OPS.md` 明写「**生产 nginx 改动一律由总运维窗口执行，开发只交 SHA + 发布说明 + 验证证据**」，且 `/srv/ops-drift/` 漂移哨兵基线新鲜（`Nov 1 01:00`）。所以本合同的交付物是**发布单**，不是我自己上机执行。

```bash
# ① 在服务器上取候选（只读检出，不覆盖任何现有目录）
cd /opt/world-space && git clone --depth 1 --branch feature/ai-beginner-20261031 \
    https://github.com/YuemingHub/World-Space.git src-ai-<SHA> || \
    git -C /opt/world-space/repos/World-Space fetch origin && \
    git -C /opt/world-space/repos/World-Space archive <SHA> web/ai | tar -x -C /tmp/ai-<SHA>

# ② 只拷静态目录，落到 /var/www/ymai.fun-static/ai（与 /ming/ 同级，互不覆盖）
install -d -m 755 /var/www/ymai.fun-static/ai
cp -a /tmp/ai-<SHA>/web/ai/. /var/www/ymai.fun-static/ai/
find /var/www/ymai.fun-static/ai -type f -exec sha256sum {} \; | sort -k2 \
  > /var/www/ymai.fun-static/ai/../.ai-release-<SHA>.sha256   # 校验清单放在目录外，不对外暴露

# ③ nginx：在已被 443 块 include 的 snippets/ming-portfolio.conf 末尾追加
#    （不新建 include，不改 sites-available/world-space，不改 location /）
#
#    location = /ai { return 301 /ai/; }
#    location ^~ /ai/ {
#        root /var/www/ymai.fun-static;
#        index index.html;
#        try_files $uri $uri/index.html $uri/ =404;
#        add_header Cache-Control "public, max-age=300";
#    }
#
#    ⚠️ 绝不能写成 ^~ /a/ —— 那会把 /api/ 一起抢走。

nginx -t && systemctl reload nginx     # reload 不中断；nginx -t 失败时旧配置继续生效（fail-closed）
```

**为什么不会影响现有路由**：nginx 匹配优先级 `=` > `^~` > `~` > 普通前缀 > `/`。
`^~ /ai/` 只匹配以 `/ai/` 开头的路径；`/api/world` 第 2–3 字符是 `ap`，不会命中；
`/`、`/login`、`/healthz`、`/ming/` 都已有各自规则，`location /` 与 Node 完全不改。

**为什么不用另外两个方案**：
- 放进 release 的 `web/v2/` → 每次发版整体替换 release 目录，静态页会丢；
- 新建一个 Node 路由 → 要改 `server/world.mjs`，把"一个静态页"耦合进认证服务，风险和收益都不对。

### 2.3 硬约束

- **不覆盖 `/var/www/ymai.fun-static/{ming,*,pdf}`**：该目录无版本控制（root 拥有、无 git），误删 PDF 无仓库可恢复。
- **不删改 `sites-available/world-space`**：`/ming/` 的 include 就写在该文件的 443 块里，动它会连带弄坏 `/ming/`。
- **不碰 Pages**：`ymai.fun` 仍被 GitHub Pages 以 CNAME 认领（证书 `bad_authz`）。建议 Commander 裁决唯一发布通道；本轮不动 Pages 设置。
- **`client_max_body_size 64k`**：`/ai/` 只有静态页，不受影响；将来若要上传再单独议。
- 公开仓库现实：合并后源码在 `raw.githubusercontent.com` 可读。页面本身无个人信息，但要写进披露。

## 3. 发布后验证（当场做，公网 + 服务器各一遍）

| # | 检查 | 期望 |
|---|---|---|
| 1 | `curl -sI https://ymai.fun/ai/` | 200，`text/html; charset=utf-8` |
| 2 | `curl -sI https://ymai.fun/ai` | 301 → `/ai/` |
| 3 | `curl -sI https://ymai.fun/` | **仍是** 302 `/login` |
| 4 | `curl -sI https://ymai.fun/login` | 仍是 200 |
| 5 | `curl -sI https://ymai.fun/api/world -X POST` 无 cookie | 仍是 401（未被 `^~ /ai/` 抢走） |
| 6 | `curl -s https://ymai.fun/healthz` | `{"ok":true}` |
| 7 | `curl -sI https://ymai.fun/ming/` + md5 | 仍 200、`3bca73c4…`、29,892 字节 |
| 8 | `BASE_URL=https://ymai.fun SITE_DIR=/ai node eval/ai-beginner-journey.mjs` | 70/70（真实公网旅程） |
| 9 | `curl -s https://ymai.fun/ai/assets/ai.css` | 200 `text/css` |
| 10 | `curl -sI "https://ymai.fun/ai/../../web/index.html"`（规范化后） | 不返回旧站文件 |
| 11 | 手机 + 电脑各打开 `/ai/` | 首屏三入口可见、三条路可点进 |
| 12 | 服务器侧：`sha256sum -c` | 与 ② 的清单逐项一致 |

## 4. 回退（一条命令 + 一次 reload；不需要回滚 Node）

```bash
# A) 撤 nginx（最快，页面立刻 404，其他一切不变）
#    删除 snippets/ming-portfolio.conf 末尾那段 location，然后：
nginx -t && systemctl reload nginx

# B) 撤目录
mv /var/www/ymai.fun-static/ai /var/www/ymai.fun-static/ai.removed-$(date +%s)

# C) 校验回退现场
curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/ai/     # 期望 404
curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/        # 期望 302
curl -s https://ymai.fun/healthz                                  # 期望 {"ok":true}
curl -sI https://ymai.fun/ming/ | grep -i etag                    # 期望与发布前一致
```

回退**不影响** `/`、`/login`、`/api/*`、`/healthz`、`/ming/`、任何用户数据与 cookie；
回退**不需要**重启 Node、不需要动 release 目录、不需要动 DNS。

若第 ③ 步 `nginx -t` 失败：**不 reload**，旧配置继续生效，现场保持发布前状态。

## 5. 状态：`RUNTIME_IDENTITY_VERIFIED` / 发布仍待授权

- 生产身份：**已证实**（见 §1）。
- 发布执行权：**不在开发窗口**（`/srv/OPS.md` 硬规矩 + 漂移哨兵），因此本文件是**可执行发布单**，不是执行记录。
- 需要的授权（二选一即可）：
  1. 由**总运维窗口**按 §2.2 执行，把 §3 的 12 条验证输出回贴；
  2. 或明确授权本窗口执行 §2.2 的 ②③ 两段（仍不含 DNS、不含 Pages、不重启 Node）。
- 无论哪条路，**合并 PR 与正式发布都由 Commander 另行决定**；本文件不包含这两步的授权。

## 6. 明确不做（本轮）

nginx 修改 / DNS 修改 / 正式发布 / 生产目录写入 / 合并 PR / 改 GitHub Pages 设置 / 覆盖 `/ming/` / 重启 Node。
