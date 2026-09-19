#!/usr/bin/env python3
"""Fixture C：虚构手写页 → OCR / 转录。

全虚构，不含任何真实个人数据（DATA_BOUNDARY.md §4）。

本机没有手写字体，所以用**楷体 + 逐字抖动**近似"比较工整的手写"。
这与真实潦草手写仍有差距，会在结论里如实写明，不拿它冒充真手写。

故意埋的易错点：
  8/3        "8 月 3 日"、"8,300"、"8 号 3 单元"
  0/O        "l38OOl3lO08" 里的 0 与 O、1 与 l 混排
  1/l        同上，且金额 "l03.50" 开头是小写 L 不是 1
  日期       1987 年 8 月 3 日（没有分隔符号，靠上下文断句）
  小数点     l03.50（少一个点就成 10350）
  单位       元
  相似名字   张伟（本页）/ 张玮（Fixture A 里那个人）

用法：
  python make_fixture_c_handwriting.py
"""

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)

LINES = [
    "爸留下的笔记本 · 第 3 页（虚构样本）",
    "",
    "1987 年 8 月 3 日",
    "今天买了两袋水泥，花了 l03.50 元",
    "张伟借去 8,300 元，说年底还",
    "李鸣家在西安路 8 号 3 单元",
    "电话：l38OOl3lO08",
    "",
    "记着：0 是零，不是字母 O",
]


def pick_font(size):
    # 楷体比黑体更接近手写；找不到就退回 simhei
    for p in ("C:/Windows/Fonts/simkai.ttf", "C:/Windows/Fonts/simhei.ttf"):
        if Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default(size=size)


def build_image(seed=7):
    """逐字抖动，模拟手写的不齐：每个字随机偏移、轻微旋转、墨色深浅不一。"""
    rng = random.Random(seed)
    W, H = 900, 520
    img = Image.new("RGB", (W, H), "#f7f4ec")  # 略黄的纸
    base = pick_font(30)

    y = 45
    for line in LINES:
        if not line.strip():
            y += 34
            continue
        x = 60
        for ch in line:
            if ch == " ":
                x += 16
                continue
            # 单字图层：旋转 + 抖动，模拟手写
            pad = 8
            try:
                box = base.getbbox(ch)
                cw, ch_h = box[2] - box[0], box[3] - box[1]
            except Exception:
                cw, ch_h = 30, 30
            tile = Image.new("RGBA", (cw + pad * 2, ch_h + pad * 2), (0, 0, 0, 0))
            td = ImageDraw.Draw(tile)
            ink = rng.randint(20, 70)
            td.text((pad, pad), ch, font=base, fill=(ink, ink, ink, 255))
            rot = rng.uniform(-6, 6)
            tile = tile.rotate(rot, resample=Image.BICUBIC, expand=True)
            img.paste(
                tile,
                (int(x + rng.uniform(-2, 2)), int(y + rng.uniform(-3, 3))),
                tile,
            )
            x += cw + rng.randint(0, 4)
        y += 46

    return img


def build_variants(img):
    paths = {}
    p1 = OUT / "fixture_c_v1_clean.png"
    img.save(p1)
    paths["v1 clean"] = p1

    # 手机随手拍的便条：压缩 + 略暗
    p2 = OUT / "fixture_c_v2_photo.jpg"
    img.save(p2, quality=55)
    paths["v2 photo"] = p2
    return paths


def ocr(path):
    from rapidocr_onnxruntime import RapidOCR

    engine = RapidOCR()
    result, _ = engine(str(path))
    return [f"{item[2]}\t{item[1]}" for item in (result or [])]


def main():
    img = build_image()
    paths = build_variants(img)

    print("=== GROUND TRUTH ===")
    for ln in LINES:
        print(ln)

    report = []
    for label, path in paths.items():
        print(f"\n=== OCR [{label}] :: {path.name} ===")
        lines = ocr(path)
        for ln in lines:
            print(ln)
        report.append(f"## {label} — {path.name}\n" + "\n".join(lines))

    txt = OUT / "fixture_c_ocr_output.txt"
    txt.write_text(
        "GROUND TRUTH\n" + "\n".join(LINES) + "\n\n" + "\n\n".join(report),
        encoding="utf-8",
    )
    print(f"\nSAVED: {txt}")


if __name__ == "__main__":
    main()
