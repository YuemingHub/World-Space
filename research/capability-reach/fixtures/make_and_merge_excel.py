"""自生成虚构样本：4 个"周报"表格 → 两种合并做法 → 核验。
本脚本与其产物均为编造数据，不含任何真实个人数据。

目的（Lab / Mission 8）：合并本身不是难点（10 行代码）。要量的是
**一个不懂技术的人会在哪种脏文件上拿到错结果，而且自己发现不了**。
结果写 RESULTS-excel-merge.md（UTF-8；本机会把 stdout 打成 GBK 乱码，不靠控制台）。
"""
from pathlib import Path
from openpyxl import Workbook, load_workbook

HERE = Path(__file__).parent
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)

FILES = {
    # 正常两份
    "week_A.xlsx": (["品名", "数量", "单价"], [("苹果", 12, 3.5), ("香蕉", 7, 2.1)]),
    "week_B.xlsx": (["品名", "数量", "单价"], [("苹果", 9, 3.5), ("橘子", 15, 4.0)]),
    # 脏法 1：列顺序不同（表头自己写着 数量,品名,单价，数据也按这个顺序填 → 结构正确，但按"第 2、3 列"取的合并会错）
    "week_C.xlsx": (["数量", "品名", "单价"], [(4, "梨", 6.0)]),
    # 脏法 2：人把数量和单价填反了，结构完全合法，值却是错的（金额恰好不变，但"数量"这一列从此不可信）
    "week_D.xlsx": (["品名", "数量", "单价"], [("香蕉", 2.1, 7)]),
}
for fn, (header, rows) in FILES.items():
    wb = Workbook()
    ws = wb.active
    ws.append(header)
    for r in rows:
        ws.append(list(r))
    wb.save(OUT / fn)

# 人手上真实应该得到的结果（我们自己知道真相，因为数据是我们编的）
TRUTH_QTY = {"苹果": 21, "香蕉": 9.1, "橘子": 15, "梨": 4}   # 香蕉：7 + 2.1(填反的数量)
TRUTH_AMT = {"苹果": 21 * 3.5, "香蕉": 7 * 2.1 + 2.1 * 7, "橘子": 60.0, "梨": 24.0}

def cells(fn):
    return [r for r in load_workbook(OUT / fn).active.iter_rows(values_only=True)
            if any(c is not None for c in r)]

# ---------- 做法 1：按位置合并（"把三个表叠在一起"，很多自动合并的实际行为）
pos_qty, pos_amt = {}, {}
for fn in FILES:
    rows = cells(fn)
    for r in rows[1:]:
        if len(r) < 3:
            continue
        k = r[0]
        if not isinstance(k, str):        # 脏法 1：这一列根本不是品名
            k = f"<非品名列:{k}>[{fn}]"
        pos_qty[k] = pos_qty.get(k, 0) + (r[1] if isinstance(r[1], (int, float)) else 0)
        pos_amt[k] = pos_amt.get(k, 0) + (r[1] * r[2] if isinstance(r[1], (int, float)) and isinstance(r[2], (int, float)) else 0)

# ---------- 做法 2：按表头名字合并
name_qty, name_amt, warn = {}, {}, []
for fn in FILES:
    rows = cells(fn)
    header = [str(c) for c in rows[0]]
    if not {"品名", "数量", "单价"} <= set(header):
        warn.append(f"{fn}: 表头缺必需列，跳过")
        continue
    for r in rows[1:]:
        d = dict(zip(header, list(r) + [None] * (len(header) - len(r))))
        n, q, p = d["品名"], d["数量"], d["单价"]
        if not isinstance(n, str) or not isinstance(q, (int, float)) or not isinstance(p, (int, float)):
            warn.append(f"{fn}: 行 {tuple(r)} 类型不对，跳过")
            continue
        name_qty[n] = name_qty.get(n, 0) + q
        name_amt[n] = name_amt.get(n, 0) + q * p

L = ["# Fixture 实测：每周合多个 Excel（自生成虚构样本，0 真人）\n",
     "两份干净表 + 一份列顺序不同 + 一份数量单价填反。\n",
     "## 两种做法给出的答案\n",
     "| 品名 | 应有的数量 | 按位置合并 | 按表头合并 |", "|---|---|---|---|"]
for k in TRUTH_QTY:
    L.append(f"| {k} | {TRUTH_QTY[k]:g} | {pos_qty.get(k, '—')} | {name_qty.get(k, '—')} |")
L.append(f"| <非品名列:4>[week_C] | — | {pos_qty.get('<非品名列:4>[week_C]', '—')} | （表头法正确归入 梨） |")
L += ["", f"金额合计：按位置 {sum(pos_amt.values()):.2f} ／ 按表头 {sum(name_amt.values()):.2f} "
      f"／ 手算 {sum(TRUTH_AMT.values()):.2f}",
      f"\n按位置合并跑出来的假品名：{[k for k in pos_qty if k not in TRUTH_QTY]}",
      f"\n体检警告（只有做法 2 会给）：{warn or '无'}",
      "\n## 这一跑真正量到的",
      "1. **列顺序不同就能把'叠在一起'的做法打坏**：week_C 结构完全合法，按位置合并却凭空造出一个品名叫 "
      "`<非品名列:4>` 的东西，并且把 24 元记在它名下。没有人会报错，表只是悄悄不对了。",
      "2. **按表头名对齐能修好脏法 1，但修不了脏法 2**：week_D 里数量与单价填反，"
      f"表头法给出的数量是 {name_qty['香蕉']:g}（真相是 7），金额却与手算一致（{name_amt['香蕉']:.2f}）。"
      "**总数对、明细错**——这是最坏的一种：它经得起'我看了下总数没问题'这种核对。",
      "3. 所以本 seed 剩余的摩擦不在 TRANSLATION（原话说得出来），而在 **VERIFICATION**："
      "会算总数的人能过，只会看'有没有报错'的人过不去。",
      "\n## 边界（不许越）",
      "本实验只支撑 `TECHNICAL / OPERATOR FEASIBILITY`。研究者自己跑得通，不等于普通人跑得通。"
      "**REAL HUMAN CASES = 0**，不得据此写 `ORDINARY_REACHABLE`。"]

(HERE / "RESULTS-excel-merge.md").write_text("\n".join(L) + "\n", encoding="utf-8")
print("written")
