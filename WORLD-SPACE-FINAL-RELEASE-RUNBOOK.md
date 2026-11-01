# World Space · 最终发布手册（V1）

> 状态：**未发布**。本手册描述"从当前生产旧版切到本次发布候选"的完整动作；
> 所有生产写入都在 §3 的门后面，未获 Owner 逐项批准前，一条都不执行。
> 本手册不替代证据：切流成功的唯一判据是 `CUTOVER=OK` 且运行期 `release_id` 等于批准身份。

读者：Owner（月明）/ Commander / 执行 Agent。
执行环境：生产服务器，经 WireGuard（`ssh family-space`），root。

---

## 0. 本手册证明什么、不证明什么

证明：

- 生产上正在服务的那份字节 = 已批准提交的发布树（运行期 `release_id` 闭环）；
- 匿名访客 `https://ymai.fun/` 看到公开首页（200），登录用户进入应用；
- `/ai/` 是独立并列入口，`/ming/` 与 `/api/` 不受影响；
- 出问题时有一条**可执行、可核实**的退路（标准回滚或带外回退）。

不证明（别把下面当成已完成）：

- 不代表已经在生产执行过（本手册的演练在 Docker 隔离环境完成，生产动作等待授权）；
- 付费真实回路（LLM / 搜索）只在 Owner 单独批准花费后才跑；
- 不处理 DNS、证书续期、其他站点；不删任何旧 release / 备份 / 用户文件。

---

## 1. 发布前事实（2026-11-01T16:01Z 只读实测）

| 项 | 实测值 |
|---|---|
| 生产 `current` | `/opt/world-space/releases/3e8e15f17bc5bae7fe78298661a5d5d14ce581c6`（**无发布身份**） |
| Node | v20.20.2（`/usr/bin/node`，systemd `ExecStart`） |
| nginx | 1.18.0；`/etc/nginx/sites-available/world-space` include `snippets/ming-portfolio.conf` |
| 公网面 | `127.0.0.1:3200`；诊断面 `127.0.0.1:3201` |
| 当前匿名 `/` | **302 → `/login`**（`cache-control: no-store`）——本次发布要改的正是这一条 |
| 当前 `/healthz` | 200，正文 `{"ok":true}` |
| 当前 `/ai/` | **404**（生产 snippet 里没有 `/ai` location） |
| 当前 `/ming/` | 200（snippet 的 `root /var/www/ymai.fun-static`） |
| 静态根 | `/var/www/ymai.fun-static`；**`/srv/static` 不存在** |
| 旧核验器 | `/usr/local/bin/ws-verify-faces.sh`，10623 B，`523597968809da7ca3ebb4000704077cfb069f7e12b2f33049621567bde3aad8`；无 `.sha256`、无 `face-probe.mjs`、无 `release-id.mjs` |
| 旧工具 | cutover `405a9b80…`、ws-prep `2533365a…`、ops-selftest `2f876b13…`、ops-fixture-face `9a35cfd9…` |
| 关站工具（2026-11-02T00:55Z 只读补测） | `/usr/local/bin/world-space-emergency.sh` 8132 B（2026-09-15）；staging 两件在位：`/opt/world-space/emergency/staging/world-space-closed.conf` 2256 B、`maintenance.html` 990 B；`/etc/nginx/sites-available/world-space-closed` 2256 B |
| 服务 | `world-space.service` active；`WorkingDirectory=/opt/world-space/current`；env 在 `/opt/world-space/shared/env/world-space.env` |

由此得到两个**必须一起做**的发布项：

1. **工具整组换新**（旧核验器不认识新身份契约，见 `docs/v2/release-c500f3d/verifier-update/README.md` §3）；
2. **`/ai/` 静态文件 + nginx location 落地**（当前生产没有 `/ai`，且静态根是 `/var/www/ymai.fun-static` 而不是沙盘里的 `/srv/static`）。

---

## 2. 变量约定（每一步都先定义，再执行）

```bash
set -euo pipefail
TS=$(date -u +%Y%m%dT%H%M%SZ)
# 合并发布线之后填写：必须是 v2 的当前提交号（40 位）
RELEASE_SHA=<40 位提交号>
REL=/opt/world-space/releases/$RELEASE_SHA
STATE=/opt/world-space/state
```

`RELEASE_SHA` 只能来自一次现读：

```bash
git -C /opt/world-space/.git-cache/World-Space.git rev-parse refs/heads/v2
```

不要从旧文档、聊天记录或本手册抄 SHA；旧编号（包括 `705ba5c…`、`e8c949a6…`）不适用。

---

## 3. 授权门（逐项点头，未批不执行）

| 门 | 动作 | 写到哪里 | 回退 |
|---|---|---|---|
| G1 | 把冻结候选合并进 GitHub `v2` | 远端分支 | 不合并即无影响 |
| G2 | 装新工具组（8 件） | `/usr/local/bin/` + `/root/backups/…` | `install-tools.sh` 的 `backup_dir` 整组还原 |
| G3 | 放 `/ai/` 静态文件（10 个，只增不删） | `/var/www/ymai.fun-static/ai/` | 停用 location 即可；文件保留 |
| G4 | 改 nginx snippet（追加 `/ai` 两个 location）并 reload | `/etc/nginx/snippets/ming-portfolio.conf`（先备份） | 还原 `.bak-$TS` 并 reload |
| G5 | `ws-prep` 取树 / 登记 / 预演 / 起本机 3210 验证实例 | 见下方“G5 实际写入面” | 不换 `current`、不 reload nginx、公网不变 |
| G6 | `cutover.sh` 切流（换 `current` + 重启一次） | `/opt/world-space/current`、systemd | 见 §7 |
| G7（可选） | 付费真实回路（LLM + 搜索） | 生产账本，产生真实费用 | 不跑即零花费 |
| G8（仅故障时） | 带外回退到无身份旧版 | `current` + `state` | 见 §7.2 |

**G5 实际写入面**（批准 G5 = 同时批准下面全部，不是只管 releases/state/env）：

- `/opt/world-space/releases/<RELEASE_SHA>/`（取树）；
- `/opt/world-space/state/`（批准记录、树清单、日志、3210 实例 pid）；
- `/opt/world-space/shared/env/world-space.v01-smoke.env`（从生产 env 派生的副本，600）；
- `/opt/world-space/shared/data/budget-smoke.json`（3210 预演实例的**独立**预算账本，不碰生产账本）；
- `/opt/world-space/emergency/www/maintenance.html`（`ws-prep emergency` 装关站维护页）；
- `/etc/nginx/sites-available/world-space-closed`（装关站块；**不**改 `sites-enabled/world-space`，**不** reload）；
- `/opt/world-space/etc/`（若不存在则建目录）及 `users.json` → `users.json.hold` → 原位（`failclosed` 期间临时移开并恢复，内容不变）。

G5 **不写**：`/opt/world-space/current`、`sites-enabled/world-space`、`shared/env/world-space.env`、
systemd 服务、DNS、`/var/www`。`ws-prep emergency` 会跑 `nginx -t`（只校验，不 reload）；
`preflight` 另起一个 8088 端口的一次性 nginx 进程，不碰公网入口。

**任何一步没拿到对应门的批准，就停在这一步之前。** 已经批准的步骤失败时，只按该步的失败语义处理，不擅自扩大写入面。

---

## 4. 执行步骤

### 步骤 0 · 发布前只读核对（不写任何东西）

```bash
readlink -f /opt/world-space/current        # …/releases/3e8e15f17bc5bae7fe78298661a5d5d14ce581c6
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3200/healthz   # 200
curl -s http://127.0.0.1:3200/healthz       # {"ok":true}
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3200/        # 302（旧行为）
sha256sum /usr/local/bin/ws-verify-faces.sh # 52359796…（旧版）
systemctl is-active world-space             # active
node -v                                     # v20.20.2
nginx -v                                    # nginx/1.18.0
test -x /usr/local/bin/world-space-emergency.sh && echo EMERG_TOOL=YES   # YES
test -f /opt/world-space/emergency/staging/world-space-closed.conf \
  && test -f /opt/world-space/emergency/staging/maintenance.html \
  && echo EMERG_STAGE=YES                    # YES
```

`world-space-emergency.sh` 与 staging 两件**不在 G2 的 8 件里**，也不由本手册安装；
它们缺失时 `ws-prep emergency` 会零写入退出，`cutover.sh` 的重启失败关站路径也不可用。
若上面两项不是 `YES`：**停止**，先按现有运维流程补齐（scp + chmod 755），再继续。

若其中任一项与 §1 表不符：**停止**，先查清"谁在什么时候改的"，不要在漂移的现场上发布。
建议此时由 Owner 触发一次服务器快照（平台动作，不在本手册命令内）；本手册不删除任何已有备份。

### 步骤 1 ·（G1）把冻结候选合并进发布线 `v2`

`ws-prep.sh` 只认 `refs/heads/v2` 上的提交，所以这一步是硬前置。

```bash
# 在开发机/受控环境，把候选分支合并到 v2 并推送（由 Owner/Commander 执行）
git fetch origin
git checkout v2 && git merge --no-ff origin/<候选分支> && git push origin v2
git rev-parse v2        # ← 记成 RELEASE_SHA
```

期望：`v2` 新提交的**树**与冻结候选的树逐文件相同（`git diff --stat <候选> v2` 为空）。
合并提交本身不影响发布身份：身份算的是树，不是提交号。

### 步骤 2 ·（G5 前置）取发布树（不动 `current`）

```bash
export WS_REF=$RELEASE_SHA
bash /usr/local/bin/ws-prep.sh fetch
```

期望输出（关键行）：

```text
OK 发布树就位：/opt/world-space/releases/<RELEASE_SHA>
   树清单：<64hex>
```

若报 `PREDEPLOY_ABORT_*`：零写入退出，按错误名处理（多数是 `v2` 还没包含该提交）。

### 步骤 3 ·（G2）装新工具组

```bash
cd /opt/world-space/releases/$RELEASE_SHA/docs/v2/release-c500f3d/verifier-update
```

> 只在**服务器发布树**里执行。发布树是 `git archive` 展开的 LF 字节；哈希钉也是按 LF 字节算的。
> 不要从 Windows 工作副本 scp 这些文件：CRLF 会让 `TOOLS.sha256` 以 `FAIL_SOURCE_HASH` 拒绝
> （这是设计的 fail-closed，不是误报）。

# 3.1 装前认证（只读）
bash verify-production.sh
# 期望：PROD_VERIFIER_CERT=FAIL，失败项集中在 sha256 / pin_* / helper_*

# 3.2 整组装（8 件）
bash install-tools.sh
# 期望：TOOLS_INSTALL=OK  files=cutover.sh,ops-selftest.sh,ws-prep.sh,ops-fixture-face.mjs,
#                        ws-verify-faces.sh,ws-verify-faces.sh.sha256,face-probe.mjs,release-id.mjs
#      重复执行：TOOLS_INSTALL=NOOP_ALREADY_CURRENT

# 3.3 装后认证（只读）
bash verify-production.sh
# 期望：PROD_VERIFIER_CERT_TOTAL=23  FAILS=0
#       PROD_VERIFIER_CERT=PASS

# 3.4 工具自测（只在本机起假面，不碰公网）
bash /usr/local/bin/ops-selftest.sh
# 期望：OPS_SELFTEST=PASS
```

失败语义：`FAIL_SOURCE_HASH` / `FAIL_PIN_ENTRY` / `FAIL_SYNTAX` = 零写入；
`FAIL_READBACK` = 已尝试整组回滚，按输出的 `backup_dir` 人工核对后再决定下一步。
**不要只装核验器不装配套工具**：旧 cutover 配新核验器会安全失败（`FAILED_SCENE_PRESERVED`），不关站，但永远拿不到 OK。

**手动单跑核验器只是“形状检查”**：不带 `WS_EXPECT_*` 绑定信息时，它只看面形状（200/标记/大小），
不能证明"服务的就是批准的那份字节"。决定性证据只有一个：`cutover.sh` 在重启后**带着期望身份**
调用核验器并拿到退出码 0（§7 的 `CUTOVER=OK`）。别拿手动跑出来的 0 替代它。

### 步骤 4 ·（G5）登记批准点 + 本机预演（公网不动）

```bash
export WS_REF=$RELEASE_SHA
bash /usr/local/bin/ws-prep.sh verify
# 期望：
#   GIT=PASS  发布树 <N> 个文件逐内容与 <RELEASE_SHA> 相同，无缺失、无多余（只读比对，未写发布树）
#   批准点已登记：/opt/world-space/state/approved-sha = <RELEASE_SHA>
#   目标发布身份：<RELEASE_ID>
#   current 仍指向：/opt/world-space/releases/3e8e15f…（本脚本从不改它）

RELEASE_ID=$(grep '^release_id=' $STATE/approved-meta.txt | cut -d= -f2)
node /usr/local/bin/release-id.mjs $REL     # 必须逐字等于 $RELEASE_ID

bash /usr/local/bin/ws-prep.sh emergency    # 期望：EMERGENCY_CLOSED=READY
bash /usr/local/bin/ws-prep.sh smokeenv     # 期望：OK …/world-space.v01-smoke.env（600，生产 env 未改动）
bash /usr/local/bin/ws-prep.sh failclosed   # 期望：AUTH_FAIL_CLOSED=PASS
bash /usr/local/bin/ws-prep.sh gates        # 期望：ALL_GATES=PASS（服务器真实发布树）
bash /usr/local/bin/ws-prep.sh start        # 仅 127.0.0.1:3210
curl -s http://127.0.0.1:3210/ | grep -q '你想做什么事' && echo SMOKE_FACADE=PASS
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3210/          # 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3210/login     # 200
bash /usr/local/bin/ws-prep.sh stop          # 公网从未指向 3210
```

说明：`smoke-formal.sh` 不带 `--rejudge` 会跑两次真实 LLM 回路（产生费用），归入 G7；
没有 G7 批准时，只跑上面的免费 curl 判定。

### 步骤 5 ·（G3）放 `/ai/` 静态文件（只增不删）

```bash
install -d -o root -g root -m 0755 /var/www/ymai.fun-static/ai
cp -a $REL/docs/v2/release-c500f3d/ai-entry/files/. /var/www/ymai.fun-static/ai/

# 逐文件比对（源 = 发布树；目标 = 线上目录）
( cd $REL/docs/v2/release-c500f3d/ai-entry/files && LC_ALL=C find . -type f | sort | xargs sha256sum ) > /tmp/ai.src.$TS
( cd /var/www/ymai.fun-static/ai                 && LC_ALL=C find . -type f | sort | xargs sha256sum ) > /tmp/ai.dst.$TS
diff /tmp/ai.src.$TS /tmp/ai.dst.$TS && echo AI_STATIC=PASS   # 期望 AI_STATIC=PASS，10 个文件
```

源文件是 10 个（`index.html`、`limits.html`、`safety.html`、`tools.html`、`assets/`、`paths/`），
内容即 PR #34 验收通过的那份静态树（树对象 `73726ee1…`），在发布树里的落地位置是
`docs/v2/release-c500f3d/ai-entry/files/`——发布树里**没有** `web/ai` 这个路径，别按旧说法去找。
**不删除**任何既有文件；不覆盖 `/ming/`。

### 步骤 6 ·（G4）追加 `/ai` location 并 reload

先备份，再追加，最后配置检查。**追加前先做“两个标记同时在场”的判定**：只写了 `location ^~ /ai/`
却缺 `location = /ai`（或反之）说明上一次追加被打断，此时不允许继续往里贴，先人工看清再决定。

```bash
SNIP=/etc/nginx/snippets/ming-portfolio.conf
BAK="$SNIP.bak-$TS"
cp -a "$SNIP" "$BAK"

# 两个标记必须同在或同缺；只出现一个是半套配置，停下
A=$(grep -c 'location = /ai ' "$SNIP" || true)
B=$(grep -c 'location ^~ /ai/' "$SNIP" || true)
if [ "$A" != "$B" ]; then echo "AI_SNIPPET_HALF A=$A B=$B"; nginx -t; exit 1; fi
if [ "$A" = "0" ]; then
  cat >> "$SNIP" <<'NGX'

# --- /ai/ (World Space AI beginner entry) ---
location = /ai { return 301 /ai/; }
location ^~ /ai/ {
    root /var/www/ymai.fun-static;
    charset utf-8;
    index index.html;
    try_files $uri $uri/index.html $uri/ =404;
    add_header Cache-Control "public, max-age=300";
}
NGX
fi

if ! nginx -t; then
  cp -a "$BAK" "$SNIP"            # 配置坏的：整块回滚回备份，不 reload
  echo NGINX_TEST=FAILED_ROLLED_BACK
  exit 1
fi
echo NGINX_TEST=PASS
systemctl reload nginx             # 只有上一步 PASS 才走这里
```

注意两点：

- `root` 必须是生产真实静态根 `/var/www/ymai.fun-static`（沙盘夹具里的 `/srv/static` 在生产**不存在**）；
- `charset utf-8;` 不能省：没有它，`/ai/` 的响应头是 `text/html` 而不是 `text/html; charset=utf-8`（沙盘实测 19/20）。

切流前先验证（此时应用还是旧版，`/` 仍 302，属预期）：

```bash
curl -s -o /dev/null -w '/ai/ %{http_code}\n' https://ymai.fun/ai/          # 200
curl -s https://ymai.fun/ai/ | grep -q 'AI 从零开始' && echo AI_CONTENT=PASS
curl -s -o /dev/null -w '/ai %{http_code}\n'  https://ymai.fun/ai           # 301
curl -s -o /dev/null -w 'deep %{http_code}\n' https://ymai.fun/ai/paths/make-a-picture.html   # 200
curl -s -o /dev/null -w 'asset %{http_code}\n' https://ymai.fun/ai/assets/ai.css              # 200
curl -s -o /dev/null -w 'missing %{http_code}\n' https://ymai.fun/ai/does-not-exist.html      # 404
curl -s -o /dev/null -w '/ming/ %{http_code}\n' https://ymai.fun/ming/      # 200（不受影响）
```

### 步骤 7 ·（G6）切流

```bash
bash /usr/local/bin/cutover.sh        # 默认 WS_MODE=upgrade；读 state/approved-sha
```

期望输出（关键行）：

```text
CUTOVER=OK  线上现在是 <RELEASE_SHA>（路径 upgrade，面形状 dual_face，release_id=<RELEASE_ID>）
```

`CUTOVER=OK` 的含义只有一句：**批准的这份字节正在服务**（核验器返回 0 且运行身份一致）。
其他 token 一律按 §6 处理，不重试、不手工换 `current`。

### 步骤 8 · 切流后免费验收（逐条命令 + 期望值）

```bash
BASE=https://ymai.fun
j() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);console.log(o[process.argv[1]]??"")})' "$1"; }

# 8.1 身份闭环
test "$(readlink -f /opt/world-space/current)" = "$REL" && echo CURRENT=PASS
test "$(curl -s http://127.0.0.1:3201/healthz | j release_id)" = "$RELEASE_ID" && echo IDENTITY=PASS
curl -s http://127.0.0.1:3201/healthz | j release_id_scheme   # world-release-tree-v1
curl -s http://127.0.0.1:3201/healthz | j diagnostic_face     # ops-v1

# 8.2 匿名公开首页（本次发布的核心）
curl -s -o /tmp/root.html -w '%{http_code}\n' $BASE/          # 200
grep -q '你想做什么事' /tmp/root.html && echo FACADE_MARK=PASS
grep -q 'id="btn-write"' /tmp/root.html && echo FACADE_BTN=PASS
test "$(wc -c < /tmp/root.html)" -ge 8000 && echo FACADE_BYTES=PASS
grep -q '你现在想做成什么' /tmp/root.html && echo UNEXPECTED_APP_TITLE || echo ANON_NOT_APP=PASS

# 8.3 /ai/ 与 /ming/
curl -s -o /dev/null -w '%{http_code}\n' $BASE/ai/                                  # 200
curl -s -o /dev/null -w '%{http_code}\n' $BASE/ai                                   # 301
curl -s -o /dev/null -w '%{http_code}\n' $BASE/ai/paths/make-something.html         # 200
curl -s -o /dev/null -w '%{http_code}\n' $BASE/ai/assets/ai.css                     # 200
curl -s -o /dev/null -w '%{http_code}\n' $BASE/ai/does-not-exist.html               # 404
curl -sI $BASE/ai/ | grep -i '^content-type'   # text/html; charset=utf-8
curl -s -o /dev/null -w '%{http_code}\n' $BASE/ming/                                # 200
MING_MD5=$(curl -s $BASE/ming/ | md5sum | cut -d' ' -f1)                            # 与切流前记录值相同

# 8.4 面与接口边界
curl -s -o /dev/null -w '%{http_code}\n' $BASE/healthz                              # 200（正文 {"ok":true}）
curl -s -o /dev/null -w '%{http_code}\n' $BASE/healthz/detail                       # 404
curl -s -o /dev/null -w '%{http_code}\n' $BASE/login                               # 200
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'content-type: application/json' \
     -d '{"intent":"未登录"}' $BASE/api/world                                        # 401
curl -s -o /dev/null -w '%{http_code}\n' $BASE/api/auth/me                          # 401
curl -s -o /dev/null -w '%{http_code}\n' $BASE/api/ops/roster                       # 404
curl -s $BASE/api/world                                                             # 404 + only POST /api/world exists
```

登录旅程（用真实账号，口令只在进程内，不回显）：

```bash
PW=$(sed -n 's/^A 账号.*密码: //p' /opt/world-space/etc/first-login.txt)
node -e 'require("fs").writeFileSync("/tmp/pl.json",JSON.stringify({username:"ymai",password:process.argv[1]}))' "$PW"
curl -s -c /tmp/jar -o /tmp/login.json -w '%{http_code}\n' -X POST \
     -H 'content-type: application/json' --data-binary @/tmp/pl.json $BASE/api/auth/login   # 200
rm -f /tmp/pl.json
curl -s -b /tmp/jar $BASE/ | grep -q '你现在想做成什么' && echo LOGGED_IN_APP=PASS
curl -s -b /tmp/jar -o /dev/null -w '%{http_code}\n' $BASE/api/auth/me                     # 200
curl -s -b /tmp/jar -o /dev/null -w '%{http_code}\n' -X POST -H 'content-type: application/json' -d '{}' $BASE/api/auth/logout  # 200
curl -s -b /tmp/jar -o /dev/null -w '%{http_code}\n' $BASE/                                # 200（公开首页，不再回本人页面）
```

以上全部符合后，发布在**功能面**成立。付费真实回路（G7）另行批准后：

```bash
bash $REL/docs/v2/release-c500f3d/public-smoke.sh     # 期望 PUBLIC_SMOKE=PASS
```

### 步骤 9 · 留档（回执）

```bash
cat $STATE/cutover-*.txt | tail -30      # status=OK / target_release_id=$RELEASE_ID / previous=3e8e15f…
ls -l $STATE/approved-sha $STATE/approved-meta.txt
```

把 `docs/v2/release-c500f3d/RELEASE-RECEIPT-TEMPLATE.md` **整份复制**为
`RELEASE-RECEIPT-<UTC>.md`，只填 `<…>` 处的实测值——**不是只抄下面这几行**，模板里的每个字段都要填：

```text
status=<OK | ROLLED_BACK | CLOSED | ABORTED>
at=<YYYY-MM-DDTHH:MM:SSZ>
operator=<执行人>

release_sha=<RELEASE_SHA，现读>
release_id=<RELEASE_ID，现读>
identity_verified=<yes | no>
previous_sha=<切流前 current 指向，本次 3e8e15f17bc5bae7fe78298661a5d5d14ce581c6>
previous_release_id=<本次 unidentified>

cutover_token=<CUTOVER=OK 或实际 token>
cutover_receipt=/opt/world-space/state/cutover-<stamp>.txt
verifier_sha256=<现算，须与 ws-verify-faces.sh.sha256 第一行一致>
verifier_cert=<PROD_VERIFIER_CERT=PASS/FAIL>
tools_install=<TOOLS_INSTALL=OK / NOOP_ALREADY_CURRENT>
tools_backup_dir=<install-tools.sh 输出>
ops_selftest=<OPS_SELFTEST=PASS>

ai_static=<AI_STATIC=PASS>
ai_files=<文件数，期望 10>
nginx_snippet_backup=<.bak-<TS> 路径>
nginx_test=<ok | failed>
nginx_reload=<done | not_done>

public_root=<200>
facade_mark=<PASS>
public_healthz=<200>
detail_public=<404>
ai_slash=<200>
ai_charset=<text/html; charset=utf-8>
ming_slash=<200>
unauth_world=<401>
unauth_me=<401>
login=<200>
logged_in_app=<PASS>

paid_smoke=<未跑 | PUBLIC_SMOKE=PASS | PUBLIC_SMOKE=FAIL>
notes=<异常、偏差、残留风险；没有就写 none>
```

判定规则（与模板一致）：`status=OK` 只允许出现在 `cutover_token=CUTOVER=OK` **且**
`identity_verified=yes` **且** 步骤 8 免费验收全部符合时；`identity_verified=no` 只能配
`ROLLED_BACK` 或 `CLOSED`。回执进证据分支，不改发布树。

---

## 5. 不要做的事

- 不手工 `ln -sfn` 换 `current`（那会绕过身份与重启核实）；
- 不在 `CUTOVER!=OK` 时再跑第二遍 cutover（先按 §6 判现场）；
- 不删 `releases/` 下任何目录、不删 `/ming/`、不删仓库外私有文件与备份；
- 不改 DNS、不动其他站点块、不重签证书；
- 不把 `WS_ROTATE_SECRET=1` 加进来（会让现有登录全部掉线；除非 Owner 明确要求）；
- 不在没批准花费时跑 `public-smoke.sh` / `smoke-formal.sh` 的付费段。

---

## 6. 切流失败分诊（按脚本 token，不按感觉）

**先记住两套数字，别混**：`cutover.sh` 自己的退出码只有 **0（OK）、3（ABORT_*）、1（所有 FAILED_*）**
三种；核验器的 2/3/4/5/7（以及 6=用法错误）是**诊断信号**，被 cutover 翻译成下面的 token，
不是 cutover 的退出码。

| token（cutover 退出码） | 现场 | 立即动作 |
|---|---|---|
| `CUTOVER=OK`（0） | 批准的字节正在服务 | 进步骤 8 验收 |
| `CUTOVER=ABORT_*`（3） | 零写入；`current` 未变 | 读原因（多为批准点/身份/发布线/元数据），修正后重跑 |
| `CUTOVER=FAILED_SWITCH`（1） | `current` 可能未变或已退回并核实 | 不重试；按输出的 `current_after` 核对，必要时人工恢复 |
| `CUTOVER=FAILED_RESTART_SCENE_PRESERVED`（1） | 重启失败，但已核实旧版仍在服务 | 不关站；查重启命令与日志，修好后重跑 |
| `CUTOVER=FAILED_RESTART_SCENE_UNVERIFIED`（1） | 重启失败，探测有响应但**无法证明服务的是旧版**（可能端口被别的进程占用） | 不关站；先查 `current`、端口占用与进程身份，别把它当成“旧版还在” |
| `CUTOVER=FAILED_RESTART_AND_CLOSED`（1） | 重启失败且恢复探测也失败，已按 §7.3 关站 | 人工修复；恢复用 `world-space-emergency.sh restore` |
| `CUTOVER=FAILED_AND_CLOSED`（1；核验器 5，或重启后公网面不可用） | 公网确实不可用，已关站 | 保留现场；先恢复服务能力，再查原因 |
| `CUTOVER=FAILED_IDENTITY_UNVERIFIABLE`（1；核验器 7） | 保留现场，不关站 | 说明身份能力不在线；不要手工改 `current` |
| `CUTOVER=FAILED_SCENE_PRESERVED`（1；核验器 2/3/4 及其他非 0/5/7） | 保留现场，不关站 | 读核验器输出逐项判断；关站要人决定 |

---

## 7. 回滚

### 7.1 标准回滚（只允许在"带发布身份的版本"之间）

```bash
export WS_REF=<目标 40 位>            # 必须带身份
export WS_MODE=rollback WS_ROLLBACK_TO=$WS_REF
bash /usr/local/bin/ws-prep.sh fetch
bash /usr/local/bin/ws-prep.sh verify
bash /usr/local/bin/cutover.sh
```

本次发布之前，生产上**没有任何带身份的旧版**（`3e8e15f` 起都没有），
所以首次发布的标准回滚目标不存在 —— 真正的退路是 7.2。

### 7.2 带外回退到无身份旧版（应急专用，两把钥匙）

边界：这条通道只能证明"旧版面在服务"，**不能证明是那一份字节**（旧版没有身份能力）。

```bash
WS_ALLOW_IDENTITYLESS_ROLLBACK=yes \
WS_ROOT=/opt/world-space \
WS_TARGET_SHA=3e8e15f17bc5bae7fe78298661a5d5d14ce581c6 \
WS_RESTART_CMD="systemctl restart world-space.service" \
bash /opt/world-space/releases/$RELEASE_SHA/docs/v2/release-c500f3d/emergency-rollback-identityless.sh
```

期望：`EMERGENCY_ROLLBACK=OK  target=3e8e15f…  identity=absent  public_healthz=200`。
回执写在 `/opt/world-space/state/emergency-rollback-<时间戳>.txt`，先落回执再动手。

**它要求（任一不满足就 `ABORT_*` 退出 3、零写入）**：

- 显式第二把钥匙 `WS_ALLOW_IDENTITYLESS_ROLLBACK=yes`；
- 完整 40 位 SHA，目标是 `releases/` 下的真实目录，且目标里**没有** `release_id_scheme`；
- `current` 是指向 `releases/<40位>` 的形状；
- **回退前公网 `/healthz` 必须正好是 200**（否则 `ABORT_PRE_SERVICE_NOT_HEALTHY`）。

最后一条最容易踩：**这条脚本不是用来救"站点已经挂了"的**。如果公网已经不可用，它会在动手前
拒绝，这是设计如此——不在坏现场上再叠一层。那种情况走 §7.3 关站止血，再人工排查。
常见 `ABORT_*`：`SECOND_KEY_MISSING` / `TARGET_INVALID` / `TARGET_TREE_MISSING` /
`TARGET_HAS_IDENTITY`（目标其实带身份，应改用 7.1）/ `PRE_SERVICE_NOT_HEALTHY`。
切 `current` 或重启后核实失败会以 `SWITCH_FAILED` / `SWITCH_UNVERIFIED` 退出 4；
服务起不来是 `FAILED_SERVICE_DOWN`，目标自报身份是 `FAILED_UNEXPECTED_IDENTITY`，都保留现场、不删文件。

脚本本身存放在**发布树里**（`releases/$RELEASE_SHA/docs/...`）：若现场连发布树都不可用，
先按 §7.3 关站，再从别处取同一份脚本（工具备份目录 `tools_backup_dir` 里有源文件）再执行。

回退后若要再前进：重新走 `ws-prep verify`（批准点会被重新登记为前进），再 `cutover.sh`。
演练证据：隔离环境 S9（回退）+ S10（从无身份旧版再前进）均 `CUTOVER=OK`。

### 7.3 最后手段：关站

```bash
/usr/local/bin/world-space-emergency.sh close     # 503 + 维护页
/usr/local/bin/world-space-emergency.sh restore   # 撤销
```

只有"公网确实不可用"或人判断必须止血时才用；回执与原因一并留档。
关站工具与它的 staging 文件在 §0 已核对在位（`EMERG_TOOL=YES` / `EMERG_STAGE=YES`）。

---

## 8. 授权核对单（打印出来逐项打勾）

- [ ] G1 `v2` 合并完成，`RELEASE_SHA` 现读并记录
- [ ] G2 工具整组装：`TOOLS_INSTALL=OK` + `PROD_VERIFIER_CERT=PASS` + `OPS_SELFTEST=PASS`
- [ ] G3 `/ai/` 10 个文件 `AI_STATIC=PASS`
- [ ] G4 snippet 已备份、`nginx -t` 通过、reload 完成、`/ai/` 200
- [ ] G5 `ws-prep verify` 的 `GIT=PASS` 与 `RELEASE_ID`
- [ ] G6 `CUTOVER=OK`
- [ ] 步骤 8 免费验收全绿（身份、首页、`/ai/`、`/ming/`、边界、登录）
- [ ] 回执填写完毕，`cutover-*.txt` 留档
- [ ] （可选）G7 付费回路 `PUBLIC_SMOKE=PASS`
