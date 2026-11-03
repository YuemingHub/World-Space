# 无身份旧版应急回退（带外通道）· 设计与演练

> 适用：线上已经切到 R4（带发布身份），而唯一可信的生命线是生产旧版 `3e8e15f1…`（**没有** `release_id` 能力）。
> 本通道与"标准回滚"是两条不同的路，**不许混用、不许互相冒充**。

## 0. 一句话

标准回滚能证明"现在服务的就是我指定的那份字节"；带外应急回退**证明不了**这一点（旧版不自报身份），
所以它把"证明不了"写进回执，并且只在标准回滚不可用时使用。

## 1. 两条路的分界

| | 标准回滚 | 带外应急回退（本文） |
|---|---|---|
| 入口 | `cutover.sh`（`WS_MODE=rollback` + `WS_ROLLBACK_TO`） | `emergency-rollback-identityless.sh` |
| 两把钥匙 | 批准记录 + 回滚目标 | `WS_ALLOW_IDENTITYLESS_ROLLBACK=yes` + 完整 40 位目标提交号 |
| 目标要求 | **必须**带 `release_id_scheme` | 目标**必须没有** `release_id_scheme`，否则拒绝 |
| 成功判据 | 运行进程 `release_id` == 目标树身份 | 公网 `/healthz=200` + 旧版面形状 + 诊断面**没有** `release_id` |
| 能证明什么 | 字节身份 | 只能证明"旧版在服务" |
| 回执 | `state/cutover-*.txt`（`identity_verified=yes`） | `state/emergency-rollback-*.txt`（`identity_verified=no`） |

标准回滚**不会**静默接受无身份版本：`cutover.sh` 在换 current 之前就会因身份缺失中止（`ABORT_LIVE_IDENTITY_UNKNOWN` /
`ABORT_*` 一类，退出 3、零写入）。这是刻意的——不允许"看起来回退了"冒充"回退成功"。

## 2. 目标版本（唯一）

- 提交：`3e8e15f17bc5bae7fe78298661a5d5d14ce581c6`（生产 v2 发布线当前线上版本）
- 目录：`/opt/world-space/releases/3e8e15f17bc5bae7fe78298661a5d5d14ce581c6`
- 前置事实：该树 `server/world.mjs` 不含 `release_id_scheme`；匿名 `/` 返回 302 → `/login`（有访问门，不是公开版）。

**执行前必须现场核实**（不许沿用本文档的旧读数）：

```bash
readlink /opt/world-space/current
ls -ld /opt/world-space/releases/3e8e15f17bc5bae7fe78298661a5d5d14ce581c6
grep -c release_id_scheme /opt/world-space/releases/3e8e15f1.../server/world.mjs   # 期望 0
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3200/healthz              # 期望 200
```

## 3. 执行前先存档（只读）

回退脚本自己会记录 pre-state 并**先写回执再动手**；人工再额外留一份现场：

```bash
S=$(date -u +%Y%m%dT%H%M%SZ); D=/root/backups/world-space-pre-emergency-$S; mkdir -p "$D"
readlink /opt/world-space/current > "$D/current.txt"
cp -a /opt/world-space/state/approved-sha "$D/" 2>/dev/null || true
cp -a /opt/world-space/state/approved-meta.txt "$D/" 2>/dev/null || true
curl -s http://127.0.0.1:3201/healthz > "$D/ops-healthz.json"
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3200/healthz > "$D/public-healthz.txt"
systemctl show -p MainPID --value world-space.service > "$D/mainpid.txt"
sha256sum /opt/world-space/releases/*/server/world.mjs > "$D/release-world-mjs.sha256" 2>/dev/null || true
```

## 4. 执行（Owner 批准后，root）

```bash
sudo WS_ALLOW_IDENTITYLESS_ROLLBACK=yes \
     WS_ROOT=/opt/world-space \
     WS_TARGET_SHA=3e8e15f17bc5bae7fe78298661a5d5d14ce581c6 \
     WS_RESTART_CMD="systemctl restart world-space.service" \
     bash /opt/world-space/current/docs/v2/release-c500f3d/emergency-rollback-identityless.sh
```

> 脚本必须从**当前发布树**里取（它随发布包一起走）；也可以先把脚本复制到 `/root/` 再执行，效果相同。

期望输出（唯一成功行）：

```
EMERGENCY_ROLLBACK=OK  target=3e8e15f1…  from=<R4 SHA>  identity=absent  public_healthz=200  pid=<数字>
```

其他任何 `ABORT_*` / `SWITCH_*` / `FAILED_*` 都不是成功。

## 5. 做/不做（脚本自身写死的边界）

做：

- 只改 `current` 符号链接、`state/approved-sha`、`state/approved-meta.txt`；
- 调一次重启命令；轮询 30 秒等 `/healthz=200`；
- 写回执 `state/emergency-rollback-<UTC 时间>.txt`（先写再动手）。

不做：

- 不删任何 release 目录、不删备份、不 `rm` 任何文件；
- 不碰 nginx 配置、不 reload nginx、不改 DNS；
- 不碰 `/ming/`、不碰发布树之外的用户文件；
- 不写数据库；不自动重试第二次。

## 6. 失败时怎么办（第二恢复手段）

按失败形态分三类，**先读回执**再动手：

1. `ABORT_*`（退出 3，零写入）：什么都没变。按提示修正前置（目标是完整 40 位、目录是真实目录、目标确实无身份、当前服务健康）后重跑。
2. `SWITCH_FAILED` / `SWITCH_UNVERIFIED`（退出 4）：符号链接没换成功。现场仍指向原版本；`readlink /opt/world-space/current` 确认后用 `ln -sfn` 手工修正，或按第 3 条恢复。
3. `FAILED_SERVICE_DOWN` / `FAILED_UNEXPECTED_IDENTITY`（退出 4）：current 已指向旧版但服务没起来 / 报了不该有的身份。**不要连着重试**，按下面恢复：

```bash
# 3a) 先尝试回到回退前的 R4（回执里的 from_sha）
PREV=$(grep '^from_sha=' /opt/world-space/state/emergency-rollback-*.txt | tail -1 | cut -d= -f2)
ln -sfn "/opt/world-space/releases/$PREV" /opt/world-space/current
printf '%s' "$PREV" > /opt/world-space/state/approved-sha
printf 'sha=%s\nmode=emergency-restore\nrelease_line=v2\nrelease_id=unidentified\nrollback_to=%s\n' "$PREV" "$PREV" \
  > /opt/world-space/state/approved-meta.txt
systemctl restart world-space.service
sleep 2
curl -s -o /dev/null -w 'public=%{http_code}\n' http://127.0.0.1:3200/healthz
curl -s http://127.0.0.1:3201/healthz | head -c 200; echo
# 期望：public=200；ops 里 release_id == R4 的身份
```

3b) 若 R4 也起不来：**保持关闭**，把现场留给人工。不要为了"先让网站有东西"去指向任何没有访问门的旧版本
（`85c7b91` / `6e73725` / main Pages 都不是退路）。此时唯一正确动作是收集日志、通知 Owner。

第二恢复手段的判据（三条都要）：

- `readlink /opt/world-space/current` 指向你刚写的那个目录；
- `systemctl show -p MainPID --value world-space.service` 是新 pid，且 `curl :3200/healthz` = 200；
- 若是 R4：诊断面 `release_id` 等于该树 `release-id.mjs` 现算值；若是旧版：诊断面没有 `release_id`。

## 7. 演练证据（本轮，Docker Linux）

`r4-acceptance-inner.sh` 的 **S9** 场景在隔离环境（node:20，真进程、真核验器、真 nginx）里完整跑过：

- 正向：`EMERGENCY_ROLLBACK=OK`，current 指向基线树，`/` 302→登录，诊断面无 `release_id`，
  `approved-sha`/`approved-meta` 同步，回执 `status=OK`+`identity_verified=no`，关站脚本 **0 次**调用，pid 变化；
- 反向（第二把钥匙缺失）：退出 3、`ABORT_SECOND_KEY_MISSING`、current 不变。

同时 S10 证明"从无身份旧版再前进回 R4"仍必须走 `cutover.sh`（唯一前进通道），且身份恢复为 R4 的 `release_id`。

## 8. 与发布手册的关系

切流成功后的"一条命令回滚"是**标准回滚**（见 RUNBOOK §回滚）；本文这条通道只在
"标准回滚目标不存在 / 目标无身份"时启用，且必须 Owner 明确批准 `WS_ALLOW_IDENTITYLESS_ROLLBACK=yes`。
