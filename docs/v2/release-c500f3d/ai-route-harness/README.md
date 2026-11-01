# `/ai/` 路由隔离沙盘（只读验收，不接入生产）

用途：在**不碰生产**的前提下，用真 nginx 1.18.0 + 生产 443 块的真实文本，验证 PR #34 发布单
（`docs/ai-beginner/DEPLOY-AI-ROUTE.md`）里的 nginx 片段是否会误伤 `/` `/api/` `/login` `/healthz` `/ming/`。

本目录**不是发布产物**。发布只包含两样东西：`web/ai/` 十个文件 + 追加到
`/etc/nginx/snippets/ming-portfolio.conf` 末尾的两个 location。

## 基线来源

- 生产配置文本：2026-11-01 经 `ssh aliyun-ecs` 只读读取（`sites-available/world-space` 与
  `snippets/ming-portfolio.conf`）。沙盘里只改两处：监听 `443 ssl` → `8080`；静态根与 upstream 指到容器。
- 静态内容：发布单绑定的目录树 `73726ee17b1020a44e52ec781c38fdf6ec66da6b`（`web/ai`，10 文件）。
- 上游 Node：`stub-server.mjs` 只复现发布单基线里的状态码语义，不实现应用。

## 复现（需要 Docker；本机已装 nginx:1.18.0 与 node:20 镜像）

```bash
# 0) 目录约定（示例）
H=$PWD   # 本目录
mkdir -p static
git -C <World-Space 检出> archive <含该树的提交> web/ai | tar -x -C "$H/static"
mv "$H/static/web/ai" "$H/static/ai" && rmdir "$H/static/web"
mkdir -p static/ming snippets
printf '<!DOCTYPE html><html><body>MING-FIXTURE-SENTINEL</body></html>\n' > static/ming/index.html
cp ming-portfolio.conf snippets/ming-portfolio.conf

# 1) 起 stub 与 nginx（同一 user-defined network；upstream 名必须等于容器名 ai-stub）
docker network create ai-harness-net 2>/dev/null || true
docker run -d --rm --name ai-stub --network ai-harness-net \
  -v "$H/stub-server.mjs:/app/server.mjs:ro" node:20 node /app/server.mjs
docker run -d --rm --name ai-nginx --network ai-harness-net -p 18080:8080 \
  -v "$H/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$H/snippets:/etc/nginx/snippets:ro" \
  -v "$H/static:/srv/static:ro" nginx:1.18.0
```

`snippets/ming-portfolio.conf` 用本目录那份（静态根已改为 `/srv/static`）。

```bash
BASE=http://127.0.0.1:18080 STATIC_DIR="$H/static" bash check.sh
```

## 2026-11-01 实跑结果

| 配置 | 结果 |
|---|---|
| 发布单原片段（无 `charset`） | **19 PASS / 1 FAIL**，`B1b_ai_charset_header`：响应头是 `text/html`，不是文档写的 `text/html; charset=utf-8` |
| 原片段 + 在 `^~ /ai/` 内加一行 `charset utf-8;` | **20 PASS / 0 FAIL**，exit 0 |
| 变异 `^~ /ai/` → `^~ /a`（无尾斜杠） | **A2 红**：`POST /api/world` 从 401 变 404 —— 真正会抢 `/api/` 的是这个写法 |
| 变异 `^~ /ai/` → `^~ /a/`（带尾斜杠） | **A2 绿**，仅 `/ai/` 全红 —— 发布单原文举例的 `/a/` 并不会抢 `/api/` |
| 变异：删掉 `/ai/` 两个 location | B1/B2/B3/B6 红（404） |
| 变异：`root /srv/static` → `/srv/static/ai` | B1/B3/B6 红（路径翻倍） |

结论：`/ai/` 片段本身对既有路由是隔离的；`/ai` 与 `/ai/` 的 301、静态资源、深链、`try_files`
404、`--path-as-is` 穿越（返回 404/400）、缓存头均符合预期。**唯一与发布单文字不符的是 charset 响应头。**

## PR #34 自带检查的复核（2026-11-01，在 PR head `055609a` 的独立 worktree 里跑）

- `node eval/check-deploy-manifest.mjs` → `rows=10 mismatch=0`，exit 0
- `node eval/ai-beginner-selftest.mjs` → `285/285`，exit 0
- `bash eval/verify-rollback-logic.sh` → `pass=14 fail=0`，exit 0
- `eval/ai-beginner-journey.mjs`（`BASE_URL=沙盘 SITE_DIR=/ai`）**原样会崩**：E 段要求
  `/` 跳 `web/index.html`、`/web/index.html` 有 `#btn-write`，而生产基线是 `/`→302/登录、
  `/web/index.html`→404，`page.click('#btn-write')` 30s 超时，exit 1。
  去掉 E 段（旧站回归）后同一条旅程 **63/63 通过**，exit 0。发布单 B7 的「70/70」因此不可执行，
  应改为「静态站旅程 63/63」+「旧站回归另行按当前生产形状验」。
