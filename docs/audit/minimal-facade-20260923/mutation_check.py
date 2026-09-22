"""Mutation check: prove the harness can actually go red.

A green checklist means nothing until the same checks fail on a page that is
deliberately broken. Each mutant changes exactly one thing in a copy of the page,
then runs audit.py against that copy and reports which checks caught it.
Usage: python docs/audit/minimal-facade-20260923/mutation_check.py
"""
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REAL = HERE.parent.parent.parent / "web" / "index.html"
AUDIT = HERE / "audit.py"
SCRATCH = HERE / ".mutants"

MUTANTS = {
    "M1_copy_button_removed": lambda s: s.replace(
        '<button type="button" class="copy-btn js-only" data-copy>',
        '<button type="button" class="js-only" data-nocopy>', 1),
    "M2_external_script_added": lambda s: s.replace(
        "</head>", '<script src="https://example.invalid/x.js"></script>\n</head>', 1),
    "M3_h1_removed": lambda s: s.replace("<h1", "<div data-h1", 1).replace("</h1>", "</div>", 1),
    # empties the whole third layer of the first sub (.sub__b holds only <p>, so the
    # first </div> is its own close)
    "M4_layer3_emptied": lambda s: re.sub(r'<div class="sub__b">.*?</div>',
                                          '<div class="sub__b"></div>', s, count=1, flags=re.S),
    "M5_icp_removed": lambda s: s.replace("陕ICP备2026014869号-4", "备案号待补", 1),
    "M6_fixed_width_overflow": lambda s: s.replace(
        "</head>", '<style>body::after{content:"";display:block;width:4000px;height:2px}</style>\n</head>', 1),
    "M7_one_sub_layer_deleted": lambda s: s.replace(
        '<details class="sub" name="ws-goal-more">', "<div>", 1),
}

src = REAL.read_text(encoding="utf-8")
SCRATCH.mkdir(exist_ok=True)
rows = []
for name, fn in MUTANTS.items():
    mutated = fn(src)
    caught_edit = mutated != src
    path = SCRATCH / f"{name}.html"
    path.write_text(mutated, encoding="utf-8")
    r = subprocess.run([sys.executable, str(AUDIT), str(path)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    results = json.loads((HERE / "audit-results.json").read_text(encoding="utf-8"))
    failed = [c["name"] for c in results["checks"] if not c["pass"]]
    rows.append({"mutant": name, "edit_applied": caught_edit, "failing_checks": failed})
    print(f"{name:38} edit_applied={caught_edit}  red_checks={len(failed)}  {failed[:4]}")

# the baseline page must stay green after the mutant runs wrote over results.json
base = subprocess.run([sys.executable, str(AUDIT), str(REAL)],
                      capture_output=True, text=True, encoding="utf-8", errors="replace")
base_res = json.loads((HERE / "audit-results.json").read_text(encoding="utf-8"))
base_fail = [c["name"] for c in base_res["checks"] if not c["pass"]]
undetected = [r["mutant"] for r in rows if not r["failing_checks"] or not r["edit_applied"]]
print(f"\nbaseline real page: {len(base_res['checks'])} checks, failures={base_fail}")
print(f"mutants with NO red check: {undetected}")
(HERE / "mutation-results.json").write_text(json.dumps(
    {"mutants": rows, "baseline_failures": base_fail, "undetected": undetected},
    ensure_ascii=False, indent=2), encoding="utf-8")
print("wrote", HERE / "mutation-results.json")
sys.exit(1 if (undetected or base_fail) else 0)
