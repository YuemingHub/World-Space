# 证据分支说明

本分支只放**验收证据与冻结清单**，不是发布树，不会被合并进 `v2`，也不参与发布身份计算。

- 发布候选：`8e10fd0c79536549607c856bf475323378c6aee8`（冻结，接受进一步审计，不再修改）
- 发布身份：`80a92a7a4a4587385ff62691bef04353432e5f0e6b08ac938078fdb250b31d84`
- 冻结清单：`EVIDENCE/RELEASE-MANIFEST.md`
- 验收矩阵：`EVIDENCE/ACCEPTANCE-MATRIX.md`
- 原始日志：`EVIDENCE/logs/`
- 独立终审报告：`EVIDENCE/DEEP-AUDIT-P9.md`（完成后追加）

复现入口：

```bash
git -c core.autocrlf=false archive 8e10fd0c79536549607c856bf475323378c6aee8 | tar -x -C /tmp/rel
node /tmp/rel/docs/v2/release-c500f3d/release-id.mjs /tmp/rel
# 80a92a7a4a4587385ff62691bef04353432e5f0e6b08ac938078fdb250b31d84
```

> 日志里的容器名、端口、合成提交号随每次运行变化；判断验收只看结论行与逐项 PASS/FAIL，
> 不要拿日志里的临时编号当发布编号。
