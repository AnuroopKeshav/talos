#!/usr/bin/env python3
"""
Diff two testsuite JSON result files and emit a Markdown report.

Usage: testsuite_diff.py <baseline.json> <pr.json>

Exit code: 0 if no regressions, 1 if any test that passed on baseline now fails on PR.
"""
import json
import sys
from collections import defaultdict

MARKER = "<!-- talos-testsuite-diff -->"

OUTCOME_EMOJI = {
    "pass":               "✅",
    "fail":               "❌",
    "interpreter_error":  "💥",
    "out_of_fuel":        "⏱️",
    "skipped":            "⏭️",
    "decode_error":       "🔧",
    "module_unavailable": "⛓️",
    "error":              "🚨",
}

COUNTED_OUTCOMES = [
    "pass", "fail", "interpreter_error", "out_of_fuel",
    "skipped", "decode_error", "module_unavailable",
]


def load(path):
    """Load a results JSON file; return (dict keyed by (file,line,kind), raw list)."""
    with open(path) as f:
        data = json.load(f)
    entries = data if isinstance(data, list) else data.get("results", [])
    by_key = {}
    for r in entries:
        key = (r["file"], r["line"], r["kind"])
        # Last write wins if duplicate keys exist (shouldn't happen, but be safe).
        by_key[key] = r
    return by_key, entries


def count_outcomes(by_key):
    counts = defaultdict(int)
    for r in by_key.values():
        counts[r["outcome"]] += 1
    return counts


def is_real_failure(r):
    return r is not None and r["outcome"] in ("fail", "interpreter_error", "out_of_fuel")


def fmt_key(file, line, kind):
    return f"`{file}:{line}` {kind}"


def table_row(*cells):
    return "| " + " | ".join(str(c) for c in cells) + " |"


def delta_str(n):
    if n > 0:
        return f"+{n}"
    return str(n)


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} baseline.json pr.json", file=sys.stderr)
        sys.exit(2)

    baseline_path, pr_path = sys.argv[1], sys.argv[2]

    try:
        baseline, _ = load(baseline_path)
    except Exception as e:
        print(f"Warning: could not load baseline ({e}); treating as empty.", file=sys.stderr)
        baseline = {}

    try:
        pr, _ = load(pr_path)
    except Exception as e:
        print(f"Error: could not load PR results: {e}", file=sys.stderr)
        sys.exit(2)

    all_keys = sorted(set(baseline.keys()) | set(pr.keys()))

    regressions = []   # pass on baseline, real failure on PR
    fixes       = []   # real failure (or absent) on baseline, pass on PR
    still_bad   = []   # real failure on both

    for key in all_keys:
        b = baseline.get(key)
        p = pr.get(key)

        b_pass = b is not None and b["outcome"] == "pass"
        p_pass = p is not None and p["outcome"] == "pass"
        b_bad  = is_real_failure(b)
        p_bad  = is_real_failure(p)

        if b_pass and p_bad:
            regressions.append((key, b, p))
        elif (b_bad or b is None) and p_pass:
            fixes.append((key, b, p))
        elif p_bad and not b_pass:
            still_bad.append((key, b, p))

    bc = count_outcomes(baseline)
    pc = count_outcomes(pr)

    lines = [MARKER, "## Wasm Testsuite Report", ""]

    # ── Summary table ──────────────────────────────────────────────────────────
    lines += [
        "### Summary",
        "",
        "| Outcome | `main` | PR | Δ |",
        "|---------|-------:|---:|--:|",
    ]
    for cat in COUNTED_OUTCOMES:
        b_n = bc.get(cat, 0)
        p_n = pc.get(cat, 0)
        emoji = OUTCOME_EMOJI.get(cat, "")
        lines.append(table_row(f"{emoji} {cat}", b_n, p_n, delta_str(p_n - b_n)))
    lines.append("")

    # ── Regressions ────────────────────────────────────────────────────────────
    if regressions:
        lines += [
            f"### ❌ Regressions — {len(regressions)} test(s) newly broken",
            "",
            "| Test | Outcome | Detail |",
            "|------|---------|--------|",
        ]
        for (file, line, kind), _, p in regressions[:60]:
            outcome = p["outcome"] if p else "?"
            detail = (p.get("detail") or "")[:100] if p else ""
            lines.append(table_row(fmt_key(file, line, kind), outcome, detail))
        if len(regressions) > 60:
            lines.append(table_row(f"…{len(regressions)-60} more", "", ""))
        lines.append("")

    # ── Fixes ──────────────────────────────────────────────────────────────────
    if fixes:
        lines += [
            f"### ✅ Fixed — {len(fixes)} test(s) newly passing",
            "",
            "| Test | Was |",
            "|------|-----|",
        ]
        for (file, line, kind), b, _ in fixes[:60]:
            was = b["outcome"] if b else "absent"
            lines.append(table_row(fmt_key(file, line, kind), was))
        if len(fixes) > 60:
            lines.append(table_row(f"…{len(fixes)-60} more", ""))
        lines.append("")

    # ── Still failing (collapsed) ───────────────────────────────────────────────
    if still_bad:
        lines += [
            f"<details>",
            f"<summary>Still failing — {len(still_bad)} test(s)</summary>",
            "",
            "| Test | Outcome | Detail |",
            "|------|---------|--------|",
        ]
        for (file, line, kind), _, p in still_bad[:120]:
            outcome = p["outcome"] if p else "?"
            detail = (p.get("detail") or "")[:80] if p else ""
            lines.append(table_row(fmt_key(file, line, kind), outcome, detail))
        if len(still_bad) > 120:
            lines.append(table_row(f"…{len(still_bad)-120} more", "", ""))
        lines += ["", "</details>", ""]

    if not regressions and not fixes and not still_bad:
        lines += ["_No executed tests found (submodule not populated?)._", ""]
    elif not regressions and not fixes:
        lines += ["_No change in pass/fail status._", ""]

    print("\n".join(lines))

    if regressions:
        sys.exit(1)


if __name__ == "__main__":
    main()
