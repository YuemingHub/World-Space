# `/ai/` 发布单 · 技术裁决与授权请求

> 状态：**`PUBLIC_RELEASE_HOLD`**。本文件是**发布单**（供总运维窗口执行），不是执行记录。
> 依据：Commander 2026-11-01 裁决 `PARALLEL_AI_ENTRY`；本轮指令：**不修改 nginx、不部署、不合并**。
> **发布执行方固定为总运维窗口**，不由开发窗口执行，也不再要求 Owner 选择执行者。
>
> 2026-11-01 v3 修订（本文件）：修正 clone/archive 目录不一致、加入整树哈希与"已存在即中止"保护、
> nginx 备份与失败回退、四条独立回归、以及**一条此前说错的事实**——公网首页不会显示仓库静态首页的那行链接。

---

## 0. 本轮准确状态

| 项 | 值 |
|---|---|
| 待发布内容 | 分支 `feature/ai-beginner-20261031` 上的 `web/ai/` 目录（9 个文件） |
| **发布必须绑定的 SHA** | **`956bb4a4b2c27e435083fd948628173c762d5f20`**（本轮最终 head；只含文档增量，代码与 `888a977` 相同） |
| 代码验收基线 | `888a97726c9a63ebbb7a3c74abc6b99ddbb3a0d8`（独立终审在此执行） |
| PR #34 | **OPEN / DRAFT**，base `main`（`3f619d1676f10efa4e8e69517ce16cd4f201f793`） |
| 合并 | **未合并** |
| 发布 | **未发布**（`https://ymai.fun/ai/` 现为 404） |
| 发布前剩余门槛 | 真人验证 `NOT_YET_TESTED`；运营主体/备案/联系方式未定 |

---

## 1. 已证实的生产身份（2026-11-01 01:05–01:12 只读调查；未改任何文件、未 reload、未部署）

| 项 | 事实 |
|---|---|
| 主机 | `iZ2ze97l6qb4ej1dz40ku6Z`（Ubuntu，内核 5.15），经 WireGuard 隧道 `10.254.0.1` 以 root 登录 |
| nginx | `1.18.0 (Ubuntu)`；ymai.fun 只由 `/etc/nginx/sites-available/world-space` 负责 |
| server 块 | ymai.fun **恰好 2 个**：80（301 → https）+ 443 |
| CDN / 缓存 | **无**（无 `proxy_cache_path`；`Server:` 头为本机原生） |
| Node 服务 | `world-space.service`，`User=wsapp`，`WorkingDirectory=/opt/world-space/current` |
| release | `current` → `releases/3e8e15f17bc5bae7fe78298661a5d5d14ce581c6`（**无 .git**） |
| 静态目录 | `/var/www/ymai.fun-static`；`/ming/` 经 `include snippets/ming-portfolio.conf` **直接读盘**，共 11 个文件（含 7 个 PDF），**无版本控制** |
| `/ming/` 完整性基线 | md5 `3bca73c4d2533e4101b96583aa2113ec`，29,892 字节（磁盘 = 公网，已双侧核对） |
| `/` 的 302、`/healthz` 的 200 | **由 Node 发出**，不是 nginx |
| `/ai/` 现在 404 的原因 | nginx 无该 location → 落到 `location /` → 交给 Node → Node 的 webDir 里没有该目录 |

**仍 Unknown**：运行中 release `3e8e15f1` 与 nginx 注释里的候选 `85c7b91e` 不一致，无法判断是"注释未更新"还是"曾回滚"。
**交接风险**：发布前请总运维单独确认这一点；本方案不依赖该 SHA，但回滚目标可能因此改变。

---

## 2. 更正一条此前说错的事实（本轮指令点名项）

**此前写法（错）**：把"旧首页加一行入口"当成会影响公网首页。

**实际事实**：`https://ymai.fun/` 未登录时由 Node 返回 **302 → `/login`**（2026-11-01 实测），
公网访客**看不到** `web/index.html`。因此：

- `web/index.html` 新增的那一行「第一次用 AI、完全不懂？从这里开始 →」，**在当前线上不会显示给任何未登录访客**；
- 它只在以下情况可见：登录后的应用内（如果该路径可达）、GitHub Pages 通道（若有人把 DNS 指回）、或本地预览；
- 结论：**本次 `/ai/` 发布与"旧首页入口"是两件独立的事**。旧首页入口是否最终可见，取决于 Commander 未来对 `/` 的裁决，不是本发布单的前提。

> 这一条也解释了为什么不能靠"把目录放进静态根"就让入口出现——详见 §3。

---

## 3. 方案：一个 location + 一个独立目录

### 3.1 目标形态

```
https://ymai.fun/ai/       ← 新增：静态目录，公开只读
https://ymai.fun/          ← 不变：302 /login（Node）
https://ymai.fun/login     ← 不变
https://ymai.fun/api/*     ← 不变
https://ymai.fun/healthz   ← 不变
https://ymai.fun/ming/     ← 不变（仓库外文件，不得覆盖）
```

### 3.2 执行步骤（**总运维窗口执行**；本轮未执行）

#### 步骤 0｜确认身份（失败即停）

```bash
ssh aliyun-ecs
hostname                                   # 期望 iZ2ze97l6qb4ej1dz40ku6Z
nginx -v                                   # 期望 nginx/1.18.0
ls -la /opt/world-space/ && readlink -f /opt/world-space/current
ls -la /etc/nginx/sites-enabled/ && ls -la /etc/nginx/snippets/ming-portfolio.conf
```
任何一项与 §1 不符 → **停止**，回到 Commander，不要"边试边改"。

#### 步骤 1｜取文件（**只有一个目录，且绑定一个完整 SHA**）

```bash
SHA=956bb4a4b2c27e435083fd948628173c762d5f20        # 必须是这个完整 40 位 SHA，禁止分支名、禁止短 SHA
STAGE=/opt/world-space/ai-entries/$SHA              # 克隆与解包都用这一个目录

# 1a 取源：优先用服务器上已有的检出，其次才 clone（两者落到同一目录约定）
if [ -d /opt/world-space/repos/World-Space/.git ]; then
  git -C /opt/world-space/repos/World-Space fetch origin --prune
  git -C /opt/world-space/repos/World-Space cat-file -e "$SHA^{commit}" \
    || { echo "STOP: 该检出里没有 $SHA"; exit 1; }
  SRC=/opt/world-space/repos/World-Space
else
  git clone --no-checkout --filter=blob:none https://github.com/YuemingHub/World-Space.git "$STAGE"
  SRC="$STAGE"
fi

# 1b 只导出 web/ai 子树（不检出整仓、不触碰 release 目录）
mkdir -p "$STAGE/extract"
git -C "$SRC" archive --format=tar "$SHA" web/ai | tar -x -C "$STAGE/extract"

# 1c 取到的必须正好是 $SHA 的 web/ai，且与文档记录的树哈希一致
git -C "$SRC" rev-parse "$SHA:web/ai"                # 期望 73726ee17b1020a44e52ec781c38fdf6ec66da6b（不同→STOP）
find "$STAGE/extract/web/ai" -type f | wc -l         # 期望：9（若为 10，多出的通常是 3.2 之外的残留，也要 STOP 复核）
```
**禁止**：`git clone --branch feature/...`（分支会移动，等于没绑定 SHA）；`--depth 1` 之后再用短 SHA（无法保证取到同一棵树）。

#### 步骤 2｜复制前的哈希清单与"文件哈希"证据

```bash
cd "$STAGE/extract/web/ai"
find . -type f -exec sha256sum {} \; | sort -k2 > "$STAGE/web-ai-sha256.txt"
sha256sum "$STAGE/web-ai-sha256.txt"                 # 清单本身的哈希，记录进发布单回执
cat "$STAGE/web-ai-sha256.txt"                        # 9 行；逐行核对 §3.3
```

#### 步骤 3｜目标目录保护（**已存在即中止，绝不覆盖**）

```bash
DEST=/var/www/ymai.fun-static/ai

if [ -e "$DEST" ]; then
  echo "STOP: $DEST 已存在"
  echo "  这通常意味着已发布过一次。要升级请走 §6 的升级流程；"
  echo "  要重装请先按 §5 回退（移走旧目录），不要就地覆盖。"
  exit 1
fi

install -d -m 755 "$DEST"
cp -a "$STAGE/extract/web/ai/." "$DEST/"
```

同理，以下路径**存在即中止**（防止覆盖仓库外文件）：
`/var/www/ymai.fun-static/{ming,index.html,lrdf.html,site.css,og-card.png}` 以及任何 `.pdf`。

#### 步骤 4｜复制后校验（必须逐字一致）

```bash
cd "$DEST" && sha256sum -c "$STAGE/web-ai-sha256.txt"
find "$DEST" -type f | wc -l                          # 期望 9
find "$DEST" -type f -perm /o+w | wc -l               # 期望 0（不允许多余的可写位）
diff -r "$STAGE/extract/web/ai" "$DEST" && echo "TREE IDENTICAL"
chmod -R a+rX "$DEST" && find "$DEST" -type d -exec chmod 755 {} \;
```

#### 步骤 5｜nginx：先备份、再改、再验、失败即回退

```bash
SNIP=/etc/nginx/snippets/ming-portfolio.conf
BAK="$SNIP.bak-$(date +%Y%m%d%H%M%S)-$(sha256sum "$SNIP" | cut -c1-8)"
cp -a "$SNIP" "$BAK"
sha256sum "$SNIP" "$BAK" | tee /var/log/ymai-ai-release-nginx-hashes.txt
```

追加到 `$SNIP` **末尾**（不要改已有内容）：

```nginx
# --- /ai/ (World Space AI beginner entry) — 2026-11-01 ---
location = /ai { return 301 /ai/; }
location ^~ /ai/ {
    root /var/www/ymai.fun-static;
    index index.html;
    try_files $uri $uri/index.html $uri/ =404;
    add_header Cache-Control "public, max-age=300";
}
```

```bash
nginx -t || { echo "STOP: 配置校验失败，未 reload；现场仍是发布前状态"; cp -a "$BAK" "$SNIP"; exit 1; }
systemctl reload nginx && echo "reloaded (不中断连接，不重启 Node)"

# 失败回退（任何一步验证不过都执行）
#   cp -a "$BAK" "$SNIP" && nginx -t && systemctl reload nginx
```

**硬约束**
- 绝不能写成 `^~ /a/`（会抢走 `/api/`）。
- 不新建 include、不改 `sites-available/world-space`（`/ming/` 的 include 就写在该文件的 443 块里，动它会连带弄坏 `/ming/`）。
- `client_max_body_size 64k` 与静态页无关，不改。
- 不做 DNS、不动 GitHub Pages。

### 3.3 预期树哈希（作为对账基线）

```bash
git -C <World-Space 检出> rev-parse 956bb4a4b2c27e435083fd948628173c762d5f20:web/ai
# 期望：73726ee17b1020a44e52ec781c38fdf6ec66da6b
# 若服务器实测与它不同 → STOP：取到的不是这个 SHA 的同一棵树。
```

在 SHA `956bb4a4…` 上，`web/ai` 的**对象哈希 `73726ee17b1020a44e52ec781c38fdf6ec66da6b`**。
这是"整棵树"级别的对账点：只要它对上，9 个文件的内容就一个字节都不会错，不必逐个比对（但仍建议按步骤 2/4 保留文件级清单作为回执证据）。

文件清单（9 个，`git ls-tree -r` 实测）：
`assets/ai.css`、`assets/ai.js`、`assets/tools.js`、`index.html`、`limits.html`、
`paths/find-the-facts.html`、`paths/make-a-picture.html`、`paths/make-something.html`、`safety.html`、`tools.html`

---

## 4. 发布后验证（**四条独立回归 + 8 条新功能验证**）

先记基线（2026-11-01 实测，发布前）：

| 请求 | 基线 |
|---|---|
| `GET /` | **302 → /login** |
| `POST /api/world`（无 cookie） | **401** |
| `GET /login` | **200** |
| `GET /healthz` | **200** |
| `GET /web/index.html` | **404** |
| `GET /ming/` | **200**，md5 `3bca73c4d2533e4101b96583aa2113ec`，29,892 字节 |
| `GET /ai/` | **404** |

**A. 四条独立回归（逐条独立执行，不要串成一条命令——管道与 `&&` 会吞掉退出码）**

| # | 命令 | 期望 |
|---|---|---|
| A1 | `curl -sI https://ymai.fun/ \| head -1` | `302`；`location: /login` |
| A2 | `curl -s -o /dev/null -w "%{http_code}\n" -X POST https://ymai.fun/api/world -H 'content-type: application/json' -d '{"intent":"smoke"}'` | `401`（**证明 `^~ /ai/` 没抢 `/api/`**） |
| A3 | `curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/login` | `200` |
| A4 | `curl -s https://ymai.fun/healthz` | `{"ok":true}` |
| A5 | `curl -sI https://ymai.fun/ming/ \| grep -i -E "etag\|last-modified"` + `curl -s https://ymai.fun/ming/ \| md5sum` | 与基线一致（`3bca73c4…`，29,892 字节） |
| A6 | `curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/web/index.html` | `404`（与基线一致，**不是**本次发布的目标） |

**B. 新功能验证**

| # | 命令 | 期望 |
|---|---|---|
| B1 | `curl -sI https://ymai.fun/ai/ \| head -3` | `200`，`Content-Type: text/html; charset=utf-8` |
| B2 | `curl -sI https://ymai.fun/ai \| head -2` | `301`，`location: /ai/` |
| B3 | `curl -s -o /dev/null -w "%{http_code} %{content_type}\n" https://ymai.fun/ai/assets/ai.css` | `200 text/css` |
| B4 | `curl -s -o /dev/null -w "%{http_code}\n" "https://ymai.fun/ai/../web/index.html"` | 不为 `200`（不得穿过到旧站） |
| B5 | `curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/ai/nope` | `404` |
| B6 | `curl -s https://ymai.fun/ai/ \| sha256sum` 与 §3 清单比对 | 与 `web-ai-sha256.txt` 中 `index.html` 一致 |
| B7 | `BASE_URL=https://ymai.fun SITE_DIR=/ai node eval/ai-beginner-journey.mjs` | `70/70`，exit 0（真实公网旅程） |
| B8 | 手机 + 电脑各打开一次 `/ai/` | 首屏三入口可见、三条路可点进、无横向滚动 |

---

## 5. 回退（不需要重启 Node、不需要动 DNS）

```bash
# A) 撤 nginx（最快：/ai/ 立刻 404，其他一切不变）
SNIP=/etc/nginx/snippets/ming-portfolio.conf
BAK=$(ls -1t "$SNIP".bak-* | head -1)
cp -a "$BAK" "$SNIP"
nginx -t && systemctl reload nginx

# B) 撤目录（先移走，不删，保留取证）
mv /var/www/ymai.fun-static/ai /var/www/ymai.fun-static/ai.removed-$(date +%Y%m%d%H%M%S)

# C) 回退验收（与 §4 的 A1–A6 逐条对照，期望完全相同，只有 /ai/ 从 200 变回 404）
curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/ai/      # 404
curl -sI https://ymai.fun/ | head -1                                # 302
curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/login     # 200
curl -s https://ymai.fun/healthz                                    # {"ok":true}
curl -s https://ymai.fun/ming/ | md5sum                             # 3bca73c4…
```

若 `nginx -t` 失败：**不 reload**，旧配置继续生效，现场保持发布前状态。

---

## 6. 后续升级（同一路径的第二版）

```bash
NEW=956bb4a…      # 新的完整 SHA
test ! -e /var/www/ymai.fun-static/ai.removed-* || true
mv /var/www/ymai.fun-static/ai /var/www/ymai.fun-static/ai.prev-$NEW
# 然后按步骤 1–4 重新放一份，按 §4 全部再验一遍
# 确认后保留最近一份 ai.prev-*，不要同时留三份以上
```

---

## 7. 本轮明确不做

nginx 修改 / DNS 修改 / 正式发布 / 生产目录写入 / 合并 PR / 改 GitHub Pages 设置 / 覆盖 `/ming/` / 重启 Node / 修改网页代码。

## 8. 待授权清单（唯一来源）

| # | 事项 | 由谁 | 前置 |
|---|---|---|---|
| 1 | 合并 PR #34 | Commander | 真人验证完成（或明确接受不带真人的风险） |
| 2 | 执行本发布单 §3 | **总运维窗口** | 合并后，`main` 上出现同一个 `web/ai`；届时把 §0 的 SHA 换成 `main` 上的提交 |
| 3 | 运营主体 / 备案 / 联系方式 | Owner | 公开前 |
| 4 | 真人验证「找人」 | Owner | 材料已就绪：`REAL-USER-TRIAL.md` |
