# `/ai/` 发布合同 · 技术裁决与授权请求

> 状态：**候选未发布**。本文件只给方案与授权请求，不执行任何生产写入。
> 依据：Commander 2026-11-01 裁决 `APPROVED_PRODUCT_DIRECTION：PARALLEL_AI_ENTRY`。
> 作者：Deep（Builder）。所有"实测"均标时间与本机执行方式，可复跑。

---

## 1. 只读核对到的生产事实（2026-11-01 00:58 +08:00 实测）

| 事实 | 证据（可复跑） | 结论 |
|---|---|---|
| `https://ymai.fun/` → **302 `/login`** | `curl -sI https://ymai.fun/` | 与历史报告一致；**未登录访客到不了任何静态页** |
| 响应头 `Server: nginx/1.18.0 (Ubuntu)` | 同上 | 公网入口是 **nginx 反代**，不是 GitHub Pages |
| `https://ymai.fun/healthz` → 200 `{"ok":true}` | `curl -s https://ymai.fun/healthz` | v2 应用（Node，`server/world.mjs`）在跑 |
| `https://ymai.fun/ai/`、`/web/ai/`、`/web/`、`/ai` → **404** | `curl -o /dev/null -w "%{http_code}"` | 静态根当前**没有**在公网暴露 `/web/` |
| `https://ymai.fun/ming/` → **200**，`Content-Type: text/html`，`Last-Modified: 2026-10-25` | `curl -sI https://ymai.fun/ming/` | **已有静态目录在以 /ming/ 形式对外服务**；但它**不是** repo 里的 `ming/index.html`（本地 `<!doctype html>` + 27KB 内联样式；线上是另一版 29,892 字节的独立文件）。→ 线上静态目录里存在**仓库外的副本**，不得覆盖。 |
| `https://ymai.fun/paths/...`、`/robots.txt` → 404 | `curl` | 仓库根不是静态根 |
| GitHub Pages | `gh api repos/YuemingHub/World-Space/pages` → `status: built`、`source: main /`、`cname: ymai.fun`、`https_certificate.state: bad_authz` | **Pages 也在发布**，且 `ymai.fun` 已被 Pages 的 CNAME 认领（证书状态异常），但公网解析到的是 ECS。**两个发布通道同时存在，是当前最大的身份风险。** |
| 仓库 `private=false` | GitHub API | 公开仓库 → `raw.githubusercontent.com/YuemingHub/World-Space/main/...` 对任何人都可读（`/ai/` 未上线时，源码侧已有第二种触达方式） |
| 本机有到 ECS 的 SSH 配置条目（`Host aliyun-ecs`） | `~/.ssh/config` 只有 Host 名 | **只读事实，未连接、未执行任何远程命令**。生产身份（目录、服务单元、文件属主）**未在本机得到证实** |

### 1.1 为什么不能直接"把 web/ai 放进静态目录"

1. `ymai.fun/` 是 302 `/login`——说明**当前静态根根本没有对未登录用户提供服务**。单独放一个目录进去，不会让 `/ai/` 自动出现（尤其 `/web/ai/` 已实测 404，说明 nginx 没有把 `/web/` 映射出去）。
2. 会动到 **nginx location**（合同禁止本轮修改），也与 v2 的"未登录只给 `/login`"安全姿态冲突。
3. `/ming/` 证明了线上有仓库外文件——**覆盖式同步会毁掉它**。

## 2. 选定方案（最小风险、可回退）

### 2.1 目标形态

```
https://ymai.fun/ai/         ← 新增（静态目录，公开只读）
https://ymai.fun/            ← 不变：302 /login（v2 应用，保持现状）
https://ymai.fun/login       ← 不变
https://ymai.fun/ming/       ← 不变（不得覆盖）
https://ymai.fun/healthz     ← 不变
```

`/ai/` 是**独立静态目录** + nginx 里**一条** `location ^~ /ai/`（只读 `try_files`），不加载 Node、不带鉴权、不共享 `/login` 的 cookie 语义。

### 2.2 落地步骤（仅 Owner / 运维执行；本轮不执行）

```bash
# 0) 先确认生产身份（这是唯一还缺的一步，见 §5）
ssh aliyun-ecs
ls -la /srv/world-space/ && ls -la /srv/world-space/repos/World-Space/ 2>/dev/null
md5sum /srv/world-space/repos/World-Space/web/index.html   # 与候选里的 web/index.html 对照
systemctl cat <v2 服务单元名> | head -40                    # 确认 WorkingDirectory 与静态根

# 1) 取候选（只读检出，不覆盖任何现有目录）
cd /srv/world-space/repos/World-Space && git fetch origin
git worktree add /srv/world-space/ai-entries/<SHA> <SHA>    # 或 git clone --depth 1 -b <branch>

# 2) 单独拷出静态目录（不 touch /web/、不 touch ming/）
install -d -m 755 /srv/world-space/www/ai
cp -a /srv/world-space/ai-entries/<SHA>/web/ai/. /srv/world-space/www/ai/
find /srv/world-space/www/ai -type f -exec sha256sum {} \; > /srv/world-space/etc/ai-release-<SHA>.sha256

# 3) nginx：只加一个 location（插在 server{} 里，别改已有 location 顺序）
#    location ^~ /ai/ { root /srv/world-space/www; try_files $uri $uri/ /ai/index.html; }
#    注意：^~ 前缀匹配，不参与正则；与 /、/login、/api/ 的现有规则互不影响。
nginx -t && systemctl reload nginx     # reload 不中断；失败时旧配置继续生效

# 4) 双侧验证（见 §3）
```

### 2.3 必须同时满足的约束

- **不覆盖 `/ming/`**：`/srv/.../www/ming/` 里是仓库外文件，任何同步都必须"只加不删、目录隔离"。
- **不改 `/`**：v2 的未登录 302 保持不动；本方案不碰 `server/world.mjs`。
- **不改 DNS**：解析与证书照旧。
- **先处理 Pages 与 ECS 的双通道**：`ymai.fun` 已被 GitHub Pages 以 CNAME 认领（证书 `bad_authz`）。如果以后有人把 DNS 指回 Pages，`/ai/` 会以**另一种方式**出现（Pages 发布的是 `main` 根目录，不含未合并的 `/ai/`）。建议 Commander 先裁决"唯一发布通道"，否则同一域名会有两个内容来源。**本轮不动 Pages 设置。**
- 公开仓库的现实：合并后 `/ai/` 的源码在 `raw.githubusercontent.com` 上也可读；这不冲突（页面本身无个人信息），但要写进披露。

## 3. 验证（发布后当场做，双侧）

| # | 检查 | 期望 |
|---|---|---|
| 1 | `curl -sI https://ymai.fun/ai/` | 200，`Content-Type: text/html; charset=utf-8` |
| 2 | `curl -sI https://ymai.fun/` | **仍是** 302 `/login` |
| 3 | `curl -sI https://ymai.fun/login` | 仍是 200 |
| 4 | `curl -sI https://ymai.fun/ming/` | 仍是 200 且 `Last-Modified` 不变 |
| 5 | `curl -s https://ymai.fun/healthz` | `{"ok":true}` |
| 6 | `BASE_URL=https://ymai.fun SITE_DIR=/ai node eval/ai-beginner-journey.mjs` | 70/70（真实公网旅程） |
| 7 | `curl -s https://ymai.fun/ai/assets/ai.css` | 200 `text/css` |
| 8 | `curl -sI https://ymai.fun/ai/../web/index.html`（路径穿越） | 不返回旧站文件（nginx merge_slashes/规范化下应为 404/301 到 `/web/`，而 `/web/` 本身 404） |
| 9 | 手机 + 电脑各打开一次 `/ai/` | 首屏三入口可见、三条路可点进 |
| 10 | `curl -s https://ymai.fun/web/index.html` | **仍然 404**（与今天一致，不因本次发布而变化） |

## 4. 回退（一条命令 + 一次 reload）

```bash
# A) 只撤 nginx（最快：页面立刻 404，其他一切不变）
sed -i '/location \^~ \/ai\//,+3d' /etc/nginx/sites-enabled/<站点文件> && nginx -t && systemctl reload nginx

# B) 撤目录（nginx 撤掉后做，或先做也行）
mv /srv/world-space/www/ai /srv/world-space/www/ai.removed-$(date +%s)

# C) 校验回退现场
curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/ai/     # 期望 404
curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/        # 期望 302
curl -s https://ymai.fun/healthz                                  # 期望 {"ok":true}
curl -sI https://ymai.fun/ming/ | grep Last-Modified              # 期望与发布前一致
```

- 回退**不影响**：`/`、`/login`、`/api/*`、`/healthz`、`/ming/`、任何用户数据与 cookie。
- 回退**需要**：一次 `nginx -t` + `reload`（不改进程、不重启 Node）。
- 若第 3 步 `nginx -t` 失败：**不 reload**，旧配置继续生效，现场保持发布前状态（fail-closed）。

## 5. 生产身份：`BLOCKED_BY_RUNTIME_IDENTITY`（如实报告）

**已证实**（公网侧）：域名、nginx 版本、`/login` 与 `/healthz` 行为、`/ming/` 存在且含仓库外文件、Pages 与 ECS 双通道并存。
**未证实**（需要服务器侧一次只读登录才能确认）：

1. nginx 站点文件路径与 `server_name` 实际匹配；
2. v2 服务单元名、`WorkingDirectory`、`webDir` 实际指向（`join(HERE,'..','web','v2')` 只是源码推断）；
3. `/srv/world-space/www/ming/` 的实际文件与来源；
4. 是否存在第二个 server 块或 CDN 缓存层。

**因此**：§2.2 的落地步骤**在第 0 步之前不可执行**。本轮不连接服务器、不写任何生产目录。

### 需要 Commander 授权的最小动作（一句话即可）

> 允许用现有 `aliyun-ecs` SSH 只读登录一次，执行 §2.2 第 0 步的 4 条命令（`ls` / `md5sum` / `systemctl cat` / `nginx -T | grep -n "server_name\|location\|root"`），把输出作为生产身份证据写进本文件。

获得该证据后，本方案即可从"候选"变为"可执行发布合同"；在获得发布授权前，**仍不执行任何写入**。

## 6. 明确不做（本轮）

nginx 修改 / DNS 修改 / 正式发布 / 生产目录写入 / 合并 PR / 改 GitHub Pages 设置 / 覆盖 `/ming/`。
