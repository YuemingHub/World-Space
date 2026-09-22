"""Pixel-anchored contrast, worst-glyph-pair method.

Two full-page shots of the same state:
  A = normal
  B = glyphs erased (color transparent), every background left exactly as painted
Any pixel that differs is a real ink pixel as painted; its background is the
pixel at the same coordinate in B. Ratios are reported for the core of the stroke
(the pixels that differ most from what is behind them) plus the 10th percentile of
all ink pixels — this is what a pixel method should show, and it is the only way to
check text painted on top of the hero artwork.
Usage: python docs/audit/minimal-facade-20260923/pixel_contrast.py
"""
import io
import json
import pathlib

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
PAGE = (HERE.parent.parent.parent / "web" / "index.html").resolve()

# the text that overlaps the artwork, plus everything else via the rows
BOXES = [(".hero-h", 0), (".hero__one", 0), (".hero-kicker", 0), (".label", 0),
         ("details.row > summary .nm", "all"), ("details.row > summary .ds", "all")]

# Erase ONLY the glyphs. background-image must stay painted: the hero's readability
# comes from a radial-gradient scrim, and killing it compares ink against a brighter
# picture than the user ever sees. `animation: none` is also forbidden here — the
# rows use an entrance animation to become visible at all, so removing it erases the
# whole panel instead of the text. Only the colour transition needs freezing.
ERASE = """* { color: transparent !important; -webkit-text-fill-color: transparent !important;
      text-shadow: none !important; transition: none !important; }"""


def rects_of(pg, selector, which):
    js = """([sel, which]) => {
        const lum = (r,g,b) => { const f = c => { c/=255; return c<=0.03928 ? c/12.92 : Math.pow((c+0.055)/1.055,2.4); };
            return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b); };
        const parse = s => { const m = s.match(/rgba?\\(([\\d.]+),\\s*([\\d.]+),\\s*([\\d.]+)(?:,\\s*([\\d.]+))?\\)/);
            return m ? {r:+m[1],g:+m[2],b:+m[3],a:m[4]===undefined?1:+m[4]} : null; };
        const bgOf = el => { let n = el; while (n && n !== document.documentElement) {
                const c = parse(getComputedStyle(n).backgroundColor); if (c && c.a > 0.95) return c; n = n.parentElement; }
            return {r:18,g:16,b:12,a:1}; };
        const els = Array.from(document.querySelectorAll(sel));
        const list = which === 'all' ? els : els.slice(0, 1);
        return list.map(el => {
            const r = el.getBoundingClientRect();
            const cs = getComputedStyle(el);
            let computed = null;
            const fg = parse(cs.color), bgr = bgOf(el.parentElement || el);
            if (fg && r.width > 1 && r.height > 1) {
                const m = {r: fg.r*fg.a + bgr.r*(1-fg.a), g: fg.g*fg.a + bgr.g*(1-fg.a), b: fg.b*fg.a + bgr.b*(1-fg.a)};
                const L1 = lum(m.r,m.g,m.b), L2 = lum(bgr.r,bgr.g,bgr.b);
                computed = Math.round(((Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05))*100)/100;
            }
            return { x: Math.round(r.x), y: Math.round(r.y + window.scrollY),
                     w: Math.round(r.width), h: Math.round(r.height),
                     computed, color: cs.color,
                     text: (el.textContent||'').trim().slice(0,14) };
        }).filter(b => b.w > 2 && b.h > 2);
    }"""
    return pg.evaluate(js, [selector, which])


def lum(r, g, b):
    def f(c):
        c /= 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def ratio(fg, bg):
    l1, l2 = lum(*fg), lum(*bg)
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)


def analyse(imgA, imgB, box, step=1):
    """Ink pixels = where the two shots differ. Edge pixels of a glyph are an
    anti-aliased blend of ink and background, so the per-pixel worst case is
    meaningless (~1:1 for any text). Use the core of the stroke: the pixels that
    differ most from what is behind them, averaged — then also report how far the
    10th percentile sits below that, so a thin/low-coverage glyph can't hide."""
    a, b = imgA.crop(box_area(box)), imgB.crop(box_area(box))
    pa, pb = a.load(), b.load()
    pairs = []
    for y in range(a.height):
        for x in range(0, a.width, step):
            p1, p2 = pa[x, y], pb[x, y]
            d = abs(p1[0] - p2[0]) + abs(p1[1] - p2[1]) + abs(p1[2] - p2[2])
            if d < 30:
                continue
            pairs.append((d, p1[:3], p2[:3]))
    if len(pairs) < 12:
        return {"ink_px": len(pairs), "core_ratio": None, "p10_ratio": None,
                "note": "too few ink pixels"}
    pairs.sort(key=lambda t: -t[0])
    core = pairs[:max(12, len(pairs) // 10)]
    mf = tuple(sum(p[1][k] for p in core) / len(core) for k in range(3))
    mb = tuple(sum(p[2][k] for p in core) / len(core) for k in range(3))
    per = sorted(ratio(p[1], p[2]) for p in pairs)
    return {"ink_px": len(pairs),
            "core_ratio": round(ratio(mf, mb), 2),
            "p10_ratio": round(per[max(0, int(len(per) * 0.10))], 2),
            "core_fg": [round(v) for v in mf], "core_bg": [round(v) for v in mb]}


def box_area(box):
    return (max(0, box["x"]), max(0, box["y"]), box["x"] + box["w"], box["y"] + box["h"])


results = []
with sync_playwright() as p:
    b = p.chromium.launch()
    for width, height in [(1440, 900), (375, 812)]:
        ctx = b.new_context(viewport={"width": width, "height": height},
                            device_scale_factor=1)
        pg = ctx.new_page()
        pg.goto(PAGE.as_uri())
        pg.wait_for_load_state("networkidle")
        pg.wait_for_timeout(1800)          # entrance animations must have settled
        # boxes + computed ratios must be read BEFORE the glyphs are erased
        boxes = [(sel, box) for sel, which in BOXES for box in rects_of(pg, sel, which)]
        shotA = pg.screenshot(full_page=True)
        pg.add_style_tag(content=ERASE)
        pg.wait_for_timeout(450)
        shotB = pg.screenshot(full_page=True)
        imA, imB = Image.open(io.BytesIO(shotA)).convert("RGB"), Image.open(io.BytesIO(shotB)).convert("RGB")
        print(f"--- {width}px  shot {imA.size} ---")
        for sel, box in boxes:
            r = analyse(imA, imB, box, step=1 if "summary" not in sel else 2)
            entry = {"width": width, "sel": sel, "text": box["text"],
                     "computed_ratio": box.get("computed"), "color": box.get("color")}
            entry.update(r)
            results.append(entry)
            v = r["core_ratio"]
            verdict = "n/a" if v is None else ("ok" if v >= 3.0 else "LOW")
            agree = "" if (v is None or box.get("computed") is None) else \
                ("  <-- disagrees with computed" if abs(v - box["computed"]) > 2.0 else "")
            print(f"  {sel:34} {box['text']:14} ink={r['ink_px']:6} pixel={v} "
                  f"computed={box.get('computed')} p10={r.get('p10_ratio')} {verdict}{agree}")
        ctx.close()
    b.close()

scored = [r for r in results if r["core_ratio"] is not None]
low = [r for r in scored if r["core_ratio"] < 3.0]
print(f"\nboxes measured={len(scored)}  min_core_ratio={min((r['core_ratio'] for r in scored), default=None)}"
      f"  min_p10={min((r['p10_ratio'] for r in scored), default=None)}  boxes_below_3.0={len(low)}")
(HERE / "pixel-contrast.json").write_text(json.dumps(
    {"method": "two-shot pixel diff; core-ink mean vs the pixels behind it; p10 of per-pixel ratios",
     "boxes": scored, "min_core": min((r["core_ratio"] for r in scored), default=None),
     "min_p10": min((r["p10_ratio"] for r in scored), default=None),
     "below_3": low}, ensure_ascii=False, indent=2), encoding="utf-8")
print("wrote", HERE / "pixel-contrast.json")
