# 发布回执（模板）

> 用法：发布结束后复制本文件为 `RELEASE-RECEIPT-<UTC 时间>.md`，只填 `<…>` 处的实测值。
> 回执进证据分支（不修改发布树）；值必须来自当轮命令输出，不凭记忆填写。

```text
status=<OK | ROLLED_BACK | CLOSED | ABORTED>
at=<YYYY-MM-DDTHH:MM:SSZ>
operator=<执行人>

release_sha=<40 位提交号，现读>
release_id=<64 位发布身份，现读>
identity_verified=<yes | no>
previous_sha=<切流前 current 指向>
previous_release_id=<unidentified | 64 位>

cutover_token=<CUTOVER=OK 或实际 token>
cutover_receipt=/opt/world-space/state/cutover-<stamp>.txt
verifier_sha256=<64 位，与 ws-verify-faces.sh.sha256 第一行一致>
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

## 判定规则

- `status=OK` 只允许出现在 `cutover_token=CUTOVER=OK` **且** `identity_verified=yes`
  **且** 步骤 8 免费验收全部符合时；其余任何组合写 `ABORTED` / `ROLLED_BACK` / `CLOSED`。
- `identity_verified=no` 只能配 `ROLLED_BACK`（带外回退）或 `CLOSED`，
  不得与 `status=OK` 同时出现。
- `paid_smoke=未跑` 不代表失败；它只是"这一轮没有真实模型/搜索费用"的事实记录。
