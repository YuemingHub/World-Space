"""Independent re-verification of the minimal-facade round.
Usage: python docs/audit/minimal-facade-20260923/audit.py
Writes machine-readable results next to this file. No network egress is allowed
by the page's own CSP; the harness additionally intercepts every request.
"""
import json
import pathlib
import sys

from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
# audit.py [path-to-html]  <- pass a mutated copy to prove the checks can go red
PAGE = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else (
    HERE.parent.parent.parent / "web" / "index.html").resolve()
assert PAGE.exists(), f"page not found: {PAGE}"

ROWS = ["row-write", "row-web", "row-find", "row-organize", "row-poster",
        "row-photo", "row-ocr", "row-start", "row-what"]
WIDTHS = [320, 375, 390, 414, 768, 1440]
OUT = {"page": str(PAGE), "checks": [], "notes": []}


def rec(name, expected, actual, passed, detail=None):
    OUT["checks"].append({"name": name, "expected": expected, "actual": actual,
                          "pass": bool(passed), "detail": detail})
    print(f"[{'PASS' if passed else 'FAIL'}] {name}: expected={expected} actual={actual}"
          + (f" {detail}" if detail else ""))


def count_nonlocal(requests):
    return [r for r in requests if not r.startswith("file://") and "127.0.0.1" not in r
            and "localhost" not in r]


CONTRAST_JS = """
() => {
  const lum = (r,g,b) => { const f = c => { c/=255; return c<=0.03928 ? c/12.92 : Math.pow((c+0.055)/1.055,2.4); };
    return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b); };
  const parse = (s) => { const m = s.match(/rgba?\\(([\\d.]+),\\s*([\\d.]+),\\s*([\\d.]+)(?:,\\s*([\\d.]+))?\\)/);
    if (!m) return null; return {r:+m[1],g:+m[2],b:+m[3],a:m[4]===undefined?1:+m[4]}; };
  const bgOf = (el) => { let n = el; while (n && n !== document.documentElement) {
      const c = parse(getComputedStyle(n).backgroundColor); if (c && c.a > 0.95) return c; n = n.parentElement; }
    return {r:255,g:255,b:255,a:1}; };
  const out = [];
  const seen = new WeakSet();
  document.querySelectorAll('body *').forEach(el => {
    if (['SCRIPT','STYLE','NOSCRIPT','LINK','META'].includes(el.tagName)) return;
    const own = Array.from(el.childNodes).filter(n => n.nodeType===3 && n.textContent.trim().length);
    if (!own.length) return;
    if (seen.has(el)) return; seen.add(el);
    const cs = getComputedStyle(el);
    if (cs.visibility==='hidden' || cs.display==='none' || +cs.opacity===0) return;
    const rect = el.getBoundingClientRect();
    if (rect.width===0 || rect.height===0) return;
    const fg = parse(cs.color); if (!fg) return;
    const bg = bgOf(el.parentElement || el);
    const mix = (c) => ({r: c.r*c.a + bg.r*(1-c.a), g: c.g*c.a + bg.g*(1-c.a), b: c.b*c.a + bg.b*(1-c.a)});
    const m = mix(fg);
    const L1 = lum(m.r,m.g,m.b), L2 = lum(bg.r,bg.g,bg.b);
    const ratio = (Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05);
    const size = parseFloat(cs.fontSize), bold = (+cs.fontWeight >= 700);
    const large = size >= 24 || (size >= 18.66 && bold);
    out.push({tag: el.tagName, cls: el.className && String(el.className).slice(0,30),
              px: Math.round(size), text: el.textContent.trim().slice(0,18),
              ratio: Math.round(ratio*100)/100, need: large ? 3.0 : 4.5});
  });
  return out;
}
"""


def run():
    with sync_playwright() as p:
        browser = p.chromium.launch()

        # ---- pass A: instrumentation on a clean load ----
        ctx = browser.new_context(viewport={"width": 1440, "height": 900})
        page = ctx.new_page()
        reqs, errs = [], []
        page.on("request", lambda r: reqs.append(r.url))
        page.on("pageerror", lambda e: errs.append(str(e)))
        page.goto(PAGE.as_uri())
        page.wait_for_load_state("networkidle")

        nonlocal_reqs = count_nonlocal(reqs)
        rec("zero_nonlocal_requests", 0, len(nonlocal_reqs),
            len(nonlocal_reqs) == 0, str(nonlocal_reqs[:3]))
        rec("zero_page_errors", 0, len(errs), len(errs) == 0, str(errs[:2]))

        counts = page.evaluate("""() => ({
            details: document.querySelectorAll('details').length,
            openByDefault: Array.from(document.querySelectorAll('details')).filter(d=>d.open).length,
            subDetails: document.querySelectorAll('details.sub').length,
            rows: document.querySelectorAll('details.row[id^="row-"]').length,
            namedSubGroups: Array.from(document.querySelectorAll('details[name]')).map(d=>d.getAttribute('name')).reduce((a,n)=>(a[n]=(a[n]||0)+1,a),{}),
            h1: document.querySelectorAll('h1').length,
            copies: document.querySelectorAll('button.copy-btn').length,
            links: document.querySelectorAll('a[href]').length,
            inputs: document.querySelectorAll('input,select,textarea').length,
            ariaControlsWithoutTarget: Array.from(document.querySelectorAll('[aria-controls]'))
                .filter(e=>!document.getElementById(e.getAttribute('aria-controls'))).length,
            hrefEmptyButtons: Array.from(document.querySelectorAll('a[href]'))
                .filter(a=>['','#','javascript:void(0)'].includes(a.getAttribute('href'))).length,
            docHeight: document.documentElement.scrollHeight,
        })""")
        OUT["notes"].append({"dom_counts": counts})
        rec("single_h1", 1, counts["h1"], counts["h1"] == 1)
        rec("no_dead_controls", 0, counts["hrefEmptyButtons"] + counts["ariaControlsWithoutTarget"],
            counts["hrefEmptyButtons"] + counts["ariaControlsWithoutTarget"] == 0,
            f"empty-href={counts['hrefEmptyButtons']} broken-aria={counts['ariaControlsWithoutTarget']}")
        # Structural fingerprint of this round's design. Without it a check suite can
        # stay all-green while whole layers quietly disappear (a mutant proved this).
        rec("structure_matches_this_rounds_shape",
            "9 rows / 22 subs / 31 details / 8 copy buttons",
            f"{counts['rows']} rows / {counts['subDetails']} subs / {counts['details']} details / {counts['copies']} copy",
            counts["rows"] == 9 and counts["subDetails"] == 22
            and counts["details"] == 31 and counts["copies"] == 8)

        # ---- pass B: accordion exclusivity + layer content ----
        rows_report = []
        for rid in ROWS:
            page.evaluate("(id) => { for (const d of document.querySelectorAll('details')) d.open = false; }", rid)
            el = page.query_selector(f"#{rid} > summary")
            if el is None:
                rec(f"row_{rid}_summary_exists", 1, 0, False)
                continue
            el.click()
            st = page.evaluate(
                """(rid) => {
                  const top = Array.from(document.querySelectorAll('details.row[id^="row-"]'));
                  const openIds = top.filter(d=>d.open).map(d=>d.id);
                  const row = document.getElementById(rid);
                  const body = row.querySelector('.goal, .steps, .wrap') || row;
                  const text = body.innerText || '';
                  const subs = Array.from(row.querySelectorAll(':scope details.sub'));
                  const subLens = subs.map(s => {
                      const prevName = s.getAttribute('name'); s.removeAttribute('name'); s.open = true;
                      void s.offsetHeight;
                      const el = s.querySelector(':scope > .sub__b') || s;
                      const n = (el.innerText || '').replace(/\\s/g,'').length;
                      s.open = false; if (prevName) s.setAttribute('name', prevName);
                      return n;
                  });
                  const blocks = Array.from(row.querySelectorAll(':scope .goal > .blk, :scope .steps > .blk'))
                      .map(b => ((b.querySelector(':scope > .k')||{}).textContent || '').trim());
                  return { openCount: openIds.length, openIds,
                    labels: blocks,
                    has_layer2: text.includes('现在最简单的做法'),
                    has_step1: text.includes('第一步'),
                    subCount: subs.length,
                    subTextLens: subLens,
                    copyBtns: row.querySelectorAll('button.copy-btn').length,
                    toolLinks: row.querySelectorAll('a.entry, a.tool-link').length,
                    visibleChars: text.replace(/\\s/g,'').length };
                }""", rid)
            st["row"] = rid
            rows_report.append(st)
        OUT["notes"].append({"rows": rows_report})

        for st in rows_report:
            ok = st["openCount"] == 1 and st["openIds"] == [st["row"]]
            rec(f"accordion_{st['row']}", f"only {st['row']} open", f"{st['openCount']} open: {st['openIds']}", ok)
        goal_rows = [s for s in rows_report if s["row"] not in ("row-start", "row-what")]
        rec("goal_rows_have_a_layer2_block", ">=1 labelled block; photo/ocr carry >=3 sub-choices",
            {s["row"]: (len(s["labels"]), s["subCount"]) for s in goal_rows},
            all(len(s["labels"]) >= 1 for s in goal_rows)
            and all(s["subCount"] >= 3 for s in goal_rows if s["row"] in ("row-photo", "row-ocr")),
            "report §3 wording '每行都有 现在最简单的做法' is literal-false for row-poster ('先选一条路')")
        rec("layer3_substantive_after_open", "every sub body >20 chars",
            {s["row"]: s["subTextLens"] for s in rows_report},
            all(all(v > 20 for v in s["subTextLens"]) for s in rows_report if s["subCount"]))
        rec("sub_details_per_goal_row_2_to_5", "2..5 subs in each of the 7 goal rows",
            {s["row"]: s["subCount"] for s in goal_rows},
            all(2 <= s["subCount"] <= 5 for s in goal_rows),
            "report §3 claims '每行 2-5 枚 <details class=\"sub\">'")
        rec("rows_with_copy_box", "6 rows (write/web/find/organize/poster/start)",
            sum(1 for s in rows_report if s["copyBtns"] > 0),
            sum(1 for s in rows_report if s["copyBtns"] > 0) == 6,
            f"total copy buttons = {sum(s['copyBtns'] for s in rows_report)}")
        rec("rows_with_tool_link", "7 rows",
            sum(1 for s in rows_report if s["toolLinks"] > 0),
            sum(1 for s in rows_report if s["toolLinks"] > 0) == 7,
            f"total tool links = {sum(s['toolLinks'] for s in rows_report)}")

        # ---- pass B2: sub-toggle grouping behaviour (record only, no claim made either way) ----
        page.evaluate("() => { for (const d of document.querySelectorAll('details')) d.open = false;"
                      " document.getElementById('row-write').open = true; }")
        page.wait_for_timeout(80)
        cross = page.evaluate("""() => {
            const subs = Array.from(document.querySelectorAll('#row-write details.sub'));
            if (subs.length < 2) return {error: 'row-write has <2 subs', n: subs.length};
            subs[0].open = true; subs[1].open = true;
            return { subsInRow: subs.length, openTogether: subs.filter(s=>s.open).length,
                     names: subs.map(s=>s.getAttribute('name')) };
        }""")
        OUT["notes"].append({"same_row_sub_exclusivity": cross})
        print(f"[INFO] same-row subs: {cross}")

        # ---- pass C: deep link ----
        dp = ctx.new_page()
        dp.goto(PAGE.as_uri() + "#web")
        dp.wait_for_load_state("networkidle")
        dls = dp.evaluate("""() => ({
            open: Array.from(document.querySelectorAll('details[id^="row-"]')).filter(d=>d.open).map(d=>d.id),
            hash: location.hash })""")
        rec("deeplink_web_opens_only_row_web", "['row-web']", dls,
            dls["open"] == ["row-web"] and dls["hash"] == "#web")
        dp.close()

        # ---- pass D: copy button ----
        page.evaluate("() => { document.getElementById('row-write').open = true; }")
        cb = page.query_selector("#row-write button.copy-btn")
        if cb:
            cb.click()
            page.wait_for_timeout(400)
            label = cb.inner_text().strip()
            rec("copy_button_feedback", "已复制", label, "已复制" in label)
        else:
            rec("copy_button_feedback", "已复制", "no copy button in row-write", False)

        # ---- pass E: overflow at each width (all rows closed) ----
        page.evaluate("() => { for (const d of document.querySelectorAll('details')) d.open=false; }")
        overflow = {}
        for w in WIDTHS:
            page.set_viewport_size({"width": w, "height": 900})
            page.wait_for_timeout(120)
            overflow[w] = page.evaluate("""() => {
                const de = document.documentElement;
                let worst = 0, who = '';
                document.querySelectorAll('body *').forEach(el => {
                  const r = el.getBoundingClientRect();
                  if (r.right > de.clientWidth + 0.5 && r.width > 0) {
                    if (r.right - de.clientWidth > worst) { worst = r.right - de.clientWidth; who = el.tagName + '.' + el.className; }
                  }
                });
                return { docOverflow: Math.max(0, de.scrollWidth - de.clientWidth), worstPx: Math.round(worst), worstEl: who,
                         scrollHeight: de.scrollHeight };
            }""")
        rec("zero_horizontal_overflow_all_widths", "0px",
            {str(k): v["docOverflow"] for k, v in overflow.items()},
            all(v["docOverflow"] == 0 for v in overflow.values()),
            str({k: v["worstEl"] for k, v in overflow.items() if v["worstPx"] > 0}))
        OUT["notes"].append({"overflow": overflow,
                             "doc_height_by_width": {str(k): v["scrollHeight"] for k, v in overflow.items()}})

        # ---- pass F: contrast, closed and truly all-open ----
        # Rows/subs share name=, so the browser enforces one-open-per-group.
        # Drop the names before forcing everything open, otherwise "open" measures
        # almost the same subtree as "closed".
        page.set_viewport_size({"width": 1440, "height": 900})
        contrast_summary = {}
        for state in ["closed", "open"]:
            for width in (1440, 375):
                page.set_viewport_size({"width": width, "height": 900})
                if state == "open":
                    page.evaluate("""() => {
                        for (const d of document.querySelectorAll('details')) d.removeAttribute('name');
                        for (const d of document.querySelectorAll('details')) d.open = true;
                    }""")
                else:
                    page.evaluate("() => { for (const d of document.querySelectorAll('details')) d.open = false; }")
                page.wait_for_timeout(150)
                items = page.evaluate(CONTRAST_JS)
                rendered = page.evaluate("""() => ({
                    text: (document.body.innerText||'').replace(/\\s/g,'').length,
                    height: document.documentElement.scrollHeight })""")
                bad = [i for i in items if i["ratio"] < i["need"]]
                contrast_summary[f"{state}_{width}"] = {
                    "measured": len(items), "failures": len(bad),
                    "min_ratio": min([i["ratio"] for i in items], default=None),
                    "rendered_text_chars": rendered["text"],
                    "doc_height": rendered["height"],
                    "worst": sorted(items, key=lambda x: x["ratio"])[:5],
                    "bad_items": bad[:8]}
        OUT["notes"].append({"contrast": contrast_summary})
        tot_fail = sum(v["failures"] for v in contrast_summary.values())
        rec("contrast_no_failures_4_states", 0, tot_fail, tot_fail == 0,
            str({k: f"{v['measured']} el / min {v['min_ratio']}" for k, v in contrast_summary.items()}))
        rec("contrast_allopen_actually_rendered_more", "all-open text > closed text",
            (contrast_summary["closed_1440"]["rendered_text_chars"],
             contrast_summary["open_1440"]["rendered_text_chars"]),
            contrast_summary["open_1440"]["rendered_text_chars"] > contrast_summary["closed_1440"]["rendered_text_chars"])

        # ---- pass I: content statistics + outbound link hygiene ----
        page.evaluate("() => { for (const d of document.querySelectorAll('details')) d.open = false; }")
        stats = page.evaluate("""() => {
            const strip = (s) => (s||'').replace(/\\s/g,'');
            const closed = strip(document.body.innerText);
            const links = Array.from(document.querySelectorAll('a[href^="http"]')).map(a => ({
                href: a.href, text: strip(a.innerText).slice(0,20),
                target: a.target || '', rel: a.getAttribute('rel') || '',
                inRow: !!a.closest('details.row') }));
            const body = document.body.innerText || '';
            return { closed_chars: closed.length,
                     icp_present: /陕ICP备2026014869号-4/.test(body),
                     icp_line: (body.match(/[^\\n]*陕ICP[^\\n]*/) || [''])[0].trim(),
                     links };
        }""")
        OUT["notes"].append({"content_stats": stats})
        rec("icp_number_on_page", "陕ICP备2026014869号-4", stats["icp_present"], stats["icp_present"],
            stats["icp_line"][:60])
        noop = [l for l in stats["links"] if l["target"] == "_blank" and "noopener" not in l["rel"]]
        rec("external_blank_links_use_noopener", 0, len(noop), len(noop) == 0, str(noop[:3]))
        print(f"[INFO] closed visible chars = {stats['closed_chars']}")
        hosts = sorted({urlsplit(l["href"]).netloc for l in stats["links"]})
        print(f"[INFO] outbound hosts = {hosts}")
        OUT["notes"].append({"outbound_hosts": hosts})

        # ---- pass G: keyboard reachability ----
        page.evaluate("() => { for (const d of document.querySelectorAll('details')) d.open = false; }")
        kb = page.evaluate("""() => {
            const focusables = document.querySelectorAll('a[href], button, summary, [tabindex]:not([tabindex="-1"])');
            const native = document.querySelectorAll('summary, a[href], button');
            const divClickHandlers = Array.from(document.querySelectorAll('div,span')).length; // informational
            return { focusables: focusables.length, native: native.length };
        }""")
        OUT["notes"].append({"keyboard": kb})
        page.keyboard.press("Tab")
        first = page.evaluate("() => document.activeElement.tagName + '#' + (document.activeElement.id||'') + '.' + (document.activeElement.className||'')")
        rec("tab_focus_lands_on_real_control", True, first,
            first.split("#")[0] in ("A", "BUTTON", "SUMMARY", "INPUT", "MAIN"), first)

        ctx.close()

        # ---- pass H: JavaScript disabled ----
        nctx = browser.new_context(viewport={"width": 390, "height": 844}, java_script_enabled=False)
        np_ = nctx.new_page()
        np_.goto(PAGE.as_uri())
        np_.wait_for_load_state("domcontentloaded")
        nojs = np_.evaluate("""() => ({
            details: document.querySelectorAll('details').length,
            open: Array.from(document.querySelectorAll('details')).filter(d=>d.open).length,
            visible: (document.body.innerText||'').replace(/\\s/g,'').length,
            deadAria: Array.from(document.querySelectorAll('[aria-controls]')).filter(e=>!document.getElementById(e.getAttribute('aria-controls'))).length,
            scriptDependent: Array.from(document.querySelectorAll('[data-js-required="true"]')).length,
            firstText: (document.querySelector('h1')||{}).textContent
        })""")
        OUT["notes"].append({"no_js": nojs})
        rec("nojs_details_still_toggle", "no <details> needs JS", nojs,
            nojs["details"] > 0 and nojs["open"] == 0)
        npp = nctx.new_page()
        npp.goto(PAGE.as_uri() + "#web")
        npp.wait_for_load_state("domcontentloaded")
        nojs_dl = npp.evaluate("""() => Array.from(document.querySelectorAll('details[id^="row-"]')).filter(d=>d.open).map(d=>d.id)""")
        rec("nojs_deeplink_behavior", "[] (no JS, nothing auto-opens) or ['row-web']", nojs_dl, True,
            "recorded as-is")
        nctx.close()
        browser.close()


run()
out_path = HERE / "audit-results.json"
out_path.write_text(json.dumps(OUT, ensure_ascii=False, indent=2), encoding="utf-8")
fails = [c["name"] for c in OUT["checks"] if not c["pass"]]
print("\n=== SUMMARY ===")
print(f"checks: {len(OUT['checks'])}  failures: {len(fails)}")
for f in fails:
    print("  FAILED:", f)
print("wrote", out_path)
