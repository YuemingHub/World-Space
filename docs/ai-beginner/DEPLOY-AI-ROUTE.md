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
| 待发布内容 | `web/ai/` 目录 —— **10 个文件**（`git ls-tree -r --name-only <head> -- web/ai \| wc -l` 实测） |
| **发布必须绑定的对象** | 目录树 `web/ai` = **`73726ee17b1020a44e52ec781c38fdf6ec66da6b`**（`git rev-parse <SHA>:web/ai`）——它等于代码验收基线 `888a977` 的同一目录树，**不随提交重写而变化** |
| 记录方式 | **不绑定任何 commit 号**：分支上有 GitHub↔CNB 双向同步，commit 会被 force push 重写；发布与核对一律读目录树哈希。需要人工追溯时，以 PR #34 当时的 head 为准。 |
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

#### 步骤 1｜取文件（**唯一绑定依据是目录树哈希，不是 commit 号**）

> 为什么不用 commit 号绑定：该分支上有 GitHub↔CNB 双向同步机制，实测会以 force push 重写分支，
> commit SHA 会变；而 `web/ai` 的目录树哈希 `73726ee1…` 只要内容不变就一直不变。

```bash
TREE=73726ee17b1020a44e52ec781c38fdf6ec66da6b   # 唯一绑定依据：web/ai 目录树哈希
REF=refs/remotes/origin/feature/ai-beginner-20261031   # 只作为"取哪里"的来源，内容一律以 TREE 为准
STAGE=/opt/world-space/ai-entries/$TREE         # 克隆与解包都用这一个目录

# 1a 取源：优先用服务器上已有的检出，其次才 clone（两者落到同一目录约定）
if [ -d /opt/world-space/repos/World-Space/.git ]; then
  SRC=/opt/world-space/repos/World-Space
  git -C "$SRC" fetch origin --prune
else
  # 新 clone：通常已经带回远端跟踪 ref；这里仍然显式 fetch 一次作为保险（分支可能在克隆之后又前进）
  git clone --filter=blob:none https://github.com/YuemingHub/World-Space.git "$STAGE"
  SRC="$STAGE"
  git -C "$SRC" fetch origin \
    '+refs/heads/feature/ai-beginner-20261031:refs/remotes/origin/feature/ai-beginner-20261031'
fi

# 1b 先核验：这棵树的哈希必须等于 TREE，否则立即停止（不做任何导出）
ACTUAL=$(git -C "$SRC" rev-parse "$REF:web/ai") || { echo "STOP: 拿不到 $REF"; exit 1; }
[ "$ACTUAL" = "$TREE" ] || { echo "STOP: 树哈希不符 $ACTUAL != $TREE"; exit 1; }
VERIFIED_COMMIT=$(git -C "$SRC" rev-parse "$REF")   # 只用于回执记录，不作为绑定依据
echo "verified commit=$VERIFIED_COMMIT tree=$ACTUAL"

# 1c 用【同一个已核验的 commit】导出（不是浮动分支名，也不是重新解析一次分支）
mkdir -p "$STAGE/extract"
git -C "$SRC" archive --format=tar "$VERIFIED_COMMIT" web/ai | tar -x -C "$STAGE/extract"
find "$STAGE/extract/web/ai" -type f | wc -l         # 期望：10
```
**禁止**：`git clone --branch feature/...` 直接把分支当发布内容；`--depth 1` 之后用短 SHA；导出时重新解析分支名（两次解析之间分支可能移动）。
**正确做法**：先核验树哈希 → 把核验过的 commit 记进变量 → 用该变量导出。

#### 步骤 2｜复制前的哈希清单与"文件哈希"证据

```bash
cd "$STAGE/extract/web/ai"
find . -type f -exec sha256sum {} \; | sort -k2 > "$STAGE/web-ai-sha256.txt"
sha256sum "$STAGE/web-ai-sha256.txt"                 # 清单本身的哈希，记录进发布单回执
cat "$STAGE/web-ai-sha256.txt"                        # 10 行；逐行核对 §3.3
```

#### 步骤 3｜目标目录保护（**只保护 `/ai` 目录本身；既有生产文件只做哈希核对，不中止、不覆盖、不删除**）

```bash
DEST=/var/www/ymai.fun-static/ai

# 3a 只对「本次要创建的目录」做存在即中止
if [ -e "$DEST" ]; then
  echo "STOP: $DEST 已存在"
  echo "  这通常意味着已发布过一次。要升级请走 §6；要重装请先按 §5 移走旧目录，不要就地覆盖。"
  exit 1
fi

# 3b 保护对象：发布前记录哈希（只记录，不因它们存在而中止）
PROT=/var/www/ymai.fun-static
find "$PROT" -path "$PROT/ai" -prune -o -type f -print0 \
  | sort -z | xargs -0 sha256sum > /root/ai-release-protected-before.sha256
[ -s /root/ai-release-protected-before.sha256 ] || { echo "STOP: 保护清单为空，路径不对"; exit 1; }
wc -l < /root/ai-release-protected-before.sha256        # 期望 ≈ 11（/ming 下文件数，实测基线）
#   ↑ 这个数字不是门槛：只要不是 0 就说明找到了既有文件。它以实测为准，本文件不硬编码"必须等于几"。

install -d -m 755 "$DEST"
cp -a "$STAGE/extract/web/ai/." "$DEST/"
```

> **规则说明（本轮修正）**：`/ming`、既有 PDF 与其他生产文件**存在是正常的**，不会让发布中止；
> 它们由 3b 的哈希清单在发布前后核对，确保**一个字节都没有被改动或删除**。
> 只有 `$DEST`（本次新目录）已存在时才中止——那是"重复发布"的信号，需要人工判断。

#### 步骤 4｜复制后校验（必须逐字一致）

```bash
cd "$DEST" && sha256sum -c "$STAGE/web-ai-sha256.txt"     # 10/10 OK
find "$DEST" -type f | wc -l                              # 期望 10
find "$DEST" -type f -perm /o+w | wc -l                    # 期望 0（不允许多余的可写位）
diff -r "$STAGE/extract/web/ai" "$DEST" && echo "TREE IDENTICAL"
chmod -R a+rX "$DEST" && find "$DEST" -type d -exec chmod 755 {} \;

# 4b 保护对象复核：与发布前清单逐条比对，必须完全一致
find "$PROT" -path "$PROT/ai" -prune -o -type f -print0 \
  | sort -z | xargs -0 sha256sum > /root/ai-release-protected-after.sha256
diff /root/ai-release-protected-before.sha256 /root/ai-release-protected-after.sha256 \
  && echo "PROTECTED UNCHANGED" || { echo "STOP: 既有文件发生变化，按 §5 回退并上报"; exit 1; }
```

#### 步骤 5｜nginx：先备份、再改、再验、失败即回退

```bash
SNIP=/etc/nginx/snippets/ming-portfolio.conf
BAK="$SNIP.bak-$(date +%Y%m%d%H%M%S)-$(sha256sum "$SNIP" | cut -c1-8)"
cp -a "$SNIP" "$BAK"
# 回执：把备份路径与哈希写死下来，回退时只认这一条，不再 ls 猜
printf 'nginx_backup=%s\nbackup_sha256=%s\nsnip_sha256=%s\n' "$BAK" "$(sha256sum "$BAK" | cut -d' ' -f1)" "$(sha256sum "$SNIP" | cut -d' ' -f1)" \
  | tee /root/ai-release-nginx-receipt.txt
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
# 校验失败：立刻把原配置写回并确认，不允许"停在改了一半"
if ! nginx -t; then
  cp -a "$BAK" "$SNIP"
  nginx -t || { echo "STOP: 恢复后仍不通过，保持现场，立即上报总运维"; exit 1; }
  echo "配置校验失败，已恢复原配置并验证通过；未 reload，线上仍是发布前行为"
  exit 1
fi

# reload 失败：同样必须恢复到可用状态并再次验证
if ! systemctl reload nginx; then
  cp -a "$BAK" "$SNIP"
  nginx -t && systemctl reload nginx && echo "reload 失败后已恢复原配置并重新加载"
  exit 1
fi
echo "reloaded (不中断连接，不重启 Node)"
```

**硬约束**
- 绝不能写成 `^~ /a/`（会抢走 `/api/`）。
- 不新建 include、不改 `sites-available/world-space`（`/ming/` 的 include 就写在该文件的 443 块里，动它会连带弄坏 `/ming/`）。
- `client_max_body_size 64k` 与静态页无关，不改。
- 不做 DNS、不动 GitHub Pages。

### 3.3 对账基线：目录树哈希（**唯一绑定依据**）

```bash
# 任何一次 clone / 任何一次推送之后都能复算，且不会因为提交被重写而失效
git -C <World-Space 检出> rev-parse origin/feature/ai-beginner-20261031:web/ai
# 期望：73726ee17b1020a44e52ec781c38fdf6ec66da6b
```

`web/ai` 的**对象哈希 `73726ee17b1020a44e52ec781c38fdf6ec66da6b`**。
它与代码验收基线 `888a977` 的**同一目录树哈希完全相同**（`git rev-parse 888a977:web/ai` 实测），
说明本轮文档修订没有改动任何待发布文件。
这是"整棵树"级别的对账点：只要它对上，**10 个文件**的内容就一个字节都不会错，不必逐个比对（但仍建议按步骤 2/4 保留文件级清单作为回执证据）。

文件清单（**10 个**，`git ls-tree -r <head> -- web/ai` 实测；第三列为该文件的 blob 哈希）：

| # | 路径（相对 `web/ai/`） | blob 哈希 |
|---|---|---|
| 1 | `index.html` | `6671036d31c133c9c119863c9b0180ba66cde97b` |
| 2 | `limits.html` | `51f95670cf0d792049af23b41105f3571d11d5f8` |
| 3 | `tools.html` | `72d18ce1a8e917089c98d04af3a2e6c87182ebbd` |
| 4 | `safety.html` | `ba7046b760d82b94c522b47672d0cd3925035780` |
| 5 | `paths/make-something.html` | `d23a39fdc9ff303eb2605bc8bb79b427af191637` |
| 6 | `paths/make-a-picture.html` | `ec2591de0b632be0d9bfebe8282d9b862c9e1a9e` |
| 7 | `paths/find-the-facts.html` | `af853564cb01733424065f9c035ff8b5c212f644` |
| 8 | `assets/ai.css` | `97f97a416266ae1fcdf962a2f10f3f8fedd2a39f` |
| 9 | `assets/ai.js` | `9f642f7eb773969aeb00e265713e5854a0628000` |
| 10 | `assets/tools.js` | `4ac7aa721f60daab783c65069e664e9497c85146` |

> 说明：`tools.js` 目前没有被任何页面引用，但它是待发布内容的一部分（页面口径副本），所以照样计数、照样校验。
> 上表可作为"目录树哈希对上之后"的第二道人工核对：任一 blob 哈希不符 → STOP。
---

## 4. 发布后验证（**A1–A6 六条独立回归 + B1–B8 八项新功能验证，共 14 项**）

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

**A. 六条独立回归（逐条独立执行，不要串成一条命令——管道与 `&&` 会吞掉退出码）**

| # | 命令 | 期望 |
|---|---|---|
| A1 | `curl -sI https://ymai.fun/ \| head -1` | `302`；`location: /login` |
| A2 | `curl -s -o /dev/null -w "%{http_code}\n" -X POST https://ymai.fun/api/world -H 'content-type: application/json' -d '{"intent":"smoke"}'` | `401`（**证明 `^~ /ai/` 没抢 `/api/`**） |
| A3 | `curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/login` | `200` |
| A4 | `curl -s https://ymai.fun/healthz` | `{"ok":true}` |
| A5 | `curl -sI https://ymai.fun/ming/ \| grep -i -E "etag\|last-modified"` + `curl -s https://ymai.fun/ming/ \| md5sum` | 与基线一致（`3bca73c4…`，29,892 字节） |
| A6 | `curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/web/index.html` | `404`（与基线一致，**不是**本次发布的目标） |

**B. 八项新功能验证**

| # | 命令 | 期望 |
|---|---|---|
| B1 | `curl -sI https://ymai.fun/ai/ \| head -3` | `200`，`Content-Type: text/html; charset=utf-8` |
| B2 | `curl -sI https://ymai.fun/ai \| head -2` | `301`，`location: /ai/` |
| B3 | `curl -s -o /dev/null -w "%{http_code} %{content_type}\n" https://ymai.fun/ai/assets/ai.css` | `200 text/css` |
| B4 | `curl --path-as-is -s -o /dev/null -w "%{http_code}\n" "https://ymai.fun/ai/../web/index.html"` | 不为 `200`（**必须加 `--path-as-is`**：否则 curl 会先在客户端把 `..` 规范化掉，测的就不是服务端行为了） |
| B5 | `curl -s -o /dev/null -w "%{http_code}\n" https://ymai.fun/ai/nope` | `404` |
| B6 | `curl -s https://ymai.fun/ai/ \| sha256sum` 与 §3 清单比对 | 与 `web-ai-sha256.txt` 中 `index.html` 一致 |
| B7 | `BASE_URL=https://ymai.fun SITE_DIR=/ai node eval/ai-beginner-journey.mjs` | `70/70`，exit 0（真实公网旅程） |
| B8 | 手机 + 电脑各打开一次 `/ai/` | 首屏三入口可见、三条路可点进、无横向滚动 |

---

## 5. 回退（不需要重启 Node、不需要动 DNS、**不删除任何文件**）

```bash
# A) 撤 nginx —— 使用步骤 5 记录在回执里的【唯一备份路径】，禁止 ls 猜"最新那个"
SNIP=/etc/nginx/snippets/ming-portfolio.conf
BAK=/etc/nginx/snippets/ming-portfolio.conf.bak-<YYYYmmddHHMMSS>-<8位哈希>   # ← 从发布回执原样复制
[ -f "$BAK" ] || { echo "STOP: 回执里的备份文件不存在，不要猜其它文件"; exit 1; }
sha256sum "$BAK"                                     # 与回执里记录的备份哈希一致才继续

# A1) 写回原配置 → 校验 → reload，每一步失败都必须以非零码退出，不许"假成功"
cp -a "$BAK" "$SNIP"
if ! nginx -t; then
  echo "FAIL: 写回原配置后 nginx -t 不通过，现场保持原样，立即上报总运维"
  exit 1
fi
if ! systemctl reload nginx; then
  echo "FAIL: reload 失败。此时磁盘=原配置、线上=发布后配置，二者不一致。"
  echo "      处置：重试一次 systemctl reload nginx；仍失败则 systemctl restart nginx；"
  echo "      再失败则上报总运维，不要离开现场，不要执行任何 B/C/D 步骤。"
  exit 1
fi
nginx -t || { echo "FAIL: reload 后配置校验不通过，停止并上报"; exit 1; }
echo "OK: 已回到原配置并生效"

# B) 撤目录（先移走，不删，保留取证）。记录下来，D 步骤要用
MOVED=/var/www/ymai.fun-static/ai.removed-<YYYYmmddHHMMSS>
mv /var/www/ymai.fun-static/ai "$MOVED"

# C) 回退验收（与 §4 的 A1–A6 逐条对照，期望完全相同；只有 /ai/ 从 200 变回 404）
curl -s  -o /dev/null -w "%{http_code}\n" https://ymai.fun/ai/       # 404
curl -sI https://ymai.fun/ | head -1                                 # 302
curl -s  -o /dev/null -w "%{http_code}\n" https://ymai.fun/login     # 200
curl -s  https://ymai.fun/healthz                                    # {"ok":true}
curl -s  https://ymai.fun/ming/ | md5sum                             # 3bca73c4…

# D) 保护对象最终核对
#    ⚠ B 步骤已经把 ai 改名成 ai.removed-*，所以必须把【两个】目录都排除，
#    否则刚移走的 10 个文件会被算进"既有文件"，导致正常的回退被误报成故障。
find /var/www/ymai.fun-static \
      -path /var/www/ymai.fun-static/ai -prune -o \
      -path "$MOVED" -prune -o \
      -type f -print0 \
  | sort -z | xargs -0 sha256sum > /root/ai-release-protected-after-rollback.sha256
diff /root/ai-release-protected-before.sha256 /root/ai-release-protected-after-rollback.sha256 \
  || { echo "FAIL: 既有文件发生变化，立即上报总运维（不要删除任何文件）"; exit 1; }
echo "PROTECTED UNCHANGED AFTER ROLLBACK"
```

**回退铁律**
- 只用回执里记录的**那一个**备份文件，不用 `ls -t | head -1` 猜。
- `nginx -t` 失败 → **不 reload** 并以非零码退出；reload 失败 → 说清"磁盘与线上不一致"的处置步骤并以非零码退出，
  **不允许**出现"只打印提示却 exit 0"的假成功。
- 回退过程中**不删除**任何 PDF、`/ming/` 文件或其他既有生产文件；只 `mv` 走本次新建的 `ai` 目录。
- D 步骤必须同时排除 `ai` 与 `ai.removed-*`（B 步骤改名后的新路径），否则正常回退会被误判成故障。

---

## 6. 后续升级（同一路径的第二版）

```bash
NEW=<下一个完整 40 位 SHA>   # 升级时必须是完整 SHA，禁止短 SHA
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
