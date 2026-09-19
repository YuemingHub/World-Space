#!/usr/bin/env python3
"""Fixture A：虚构数字截图 → OCR / 结构化表格。

全虚构，不含任何真实个人数据（DATA_BOUNDARY.md §4）。

故意埋的易错点（不是随机噪声，是现实里最容易看错的那几类）：
  8/3 相邻      8,300.00 与 380.00
  0/O          103.50、1,806.00
  1/l          1,806.00
  日期          09-06 / 09-08 / 09-16 / 09-19 混排
  小数点        103.50（少了小数点就变成 10350）
  千分位逗号     1,806.00
  相似人名       张伟 / 张玮
  合计校验       合计等于五行之和，任何一行被读错都会让合计对不上

用法：
  python make_fixture_a_ocr.py          # 生成图片并识别
  python make_fixture_a_ocr.py --no-ocr # 只生成图片
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)

# Ground truth：脚本不"生成数字"，这些数字是写死的，作为比对基准。
ROWS = [
    ("1", "张伟", "2026-09-08", "1,806.00", "差旅报销"),
    ("2", "李鸣", "2026-09-16", "380.00", "办公用品"),
    ("3", "王芳", "2026-09-06", "1,080.00", "会务费"),
    ("4", "张玮", "2026-09-19", "8,300.00", "设备采购"),
    ("5", "陈可", "2026-09-01", "103.50", "快递费"),
]
TOTAL = "11,669.50"  # = 1806 + 380 + 1080 + 8300 + 103.50
HEADER = ("序号", "姓名", "日期", "金额(元)", "备注")


def pick_font(size):
    """系统里找一个能画中文的字体；找不到就退回默认（会画成方块，脚本会提示）。"""
    for p in (
        "C:/Windows/Fonts/simhei.ttf",
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/simsun.ttc",
    ):
        if Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default(size=size)


def build_image():
    """原始干净样本：白底印刷体，相当于"自己电脑上截的图"。"""
    W, H = 900, 420
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    f = pick_font(26)
    fs = pick_font(22)

    d.rectangle([20, 20, W - 20, 60], fill="#f2f2f2")
    d.text((36, 30), "九月费用明细（虚构样本）", font=f, fill="black")

    cols = [40, 120, 260, 470, 660]
    y = 90
    for x, name in zip(cols, HEADER):
        d.text((x, y), name, font=fs, fill="black")
    d.line([30, y + 32, W - 30, y + 32], fill="#888888", width=1)

    y += 45
    for row in ROWS:
        for x, cell in zip(cols, row):
            d.text((x, y), cell, font=fs, fill="black")
        d.line([30, y + 32, W - 30, y + 32], fill="#dddddd", width=1)
        y += 38

    d.text((cols[0], y + 8), "合计", font=fs, fill="black")
    d.text((cols[3], y + 8), TOTAL, font=fs, fill="black")
    return img


def build_variants(img):
    """三个变体，对应三种真实的"图是怎么到用户手里的"。

    v1 clean   自己电脑/手机上原图截图
    v2 jpeg45  微信转发后的图（微信会重压缩，quality 大约在这个量级）
    v3 lowres  从聊天记录里存的缩略图 / 被缩放过的老图
    """
    paths = {}

    p1 = OUT / "fixture_a_v1_clean.png"
    img.save(p1)
    paths["v1 clean"] = p1

    p2 = OUT / "fixture_a_v2_jpeg45.jpg"
    img.save(p2, quality=45)
    paths["v2 jpeg45"] = p2

    small = img.resize((img.width // 2, img.height // 2), Image.BILINEAR)
    p3 = OUT / "fixture_a_v3_lowres.png"
    small.resize(img.size, Image.BILINEAR).save(p3)
    paths["v3 lowres"] = p3

    return paths


def ocr(path):
    from rapidocr_onnxruntime import RapidOCR

    engine = RapidOCR()
    result, _ = engine(str(path))
    lines = []
    for item in result or []:
        text = item[1]
        score = item[2]
        lines.append(f"{score}\t{text}")
    return lines


def main():
    img = build_image()
    paths = build_variants(img)

    print("=== GROUND TRUTH ===")
    for r in ROWS:
        print(" | ".join(r))
    print("TOTAL:", TOTAL)

    if "--no-ocr" in sys.argv:
        for k, v in paths.items():
            print(f"IMAGE {k}: {v}")
        return

    report = []
    for label, path in paths.items():
        print(f"\n=== OCR [{label}] :: {path.name} ===")
        lines = ocr(path)
        for ln in lines:
            print(ln)
        report.append(f"## {label} — {path.name}\n" + "\n".join(lines))

    txt = OUT / "fixture_a_ocr_output.txt"
    txt.write_text(
        "GROUND TRUTH\n"
        + "\n".join(" | ".join(r) for r in ROWS)
        + f"\nTOTAL: {TOTAL}\n\n"
        + "\n\n".join(report),
        encoding="utf-8",
    )
    print(f"\nSAVED: {txt}")


if __name__ == "__main__":
    main()
