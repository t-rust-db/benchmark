#!/usr/bin/env python3
"""Render the column-rs vs DuckDB comparison table for a benchmark run.

Ported from column-rs's own benches/report.py (github.com/iheitlager/
column-rs, #100) into this repo's parity/column-rs harness.

Usage: python3 report.py results/<run-dir>

Reads the hyperfine JSON exports and peak-RSS readings that run.sh wrote and
prints the markdown gap table to stdout. Standard library only -- no
dependency beyond the python3 already needed to run it.
"""

import json
import pathlib
import sys

# Query order in the report, matching the gap table in #100. Anything found on
# disk but not listed here is appended afterwards rather than dropped.
ORDER = [
    "scan",
    "filter_1pct",
    "filter_50pct",
    "agg_count",
    "agg_sum",
    "group_by",
    "order_by",
    "join",
    "list_not_null_low",
    "list_not_null_mid",
    "unnest_group_by_low",
    "unnest_group_by_mid",
]

TARGET_RATIO = 1.5  # "within 50% of DuckDB" -- the pass bar set in #100.
BINARY_SIZE_LIMIT = 5 * 1024 * 1024


def median_seconds(path):
    """Median wall time from a hyperfine JSON export, or None if unusable:
    one slow outlier run moves a mean, not a median (benchmark#21)."""
    try:
        with open(path) as fh:
            results = json.load(fh)["results"]
    except (OSError, ValueError, KeyError):
        return None
    return results[0]["median"] if results else None


def peak_rss_kb(path, engine):
    """Peak RSS in KB for one engine, or None if it wasn't recorded."""
    try:
        for line in open(path):
            name, _, value = line.partition(" ")
            if name == engine:
                return int(value.strip())
    except (OSError, ValueError):
        pass
    return None


def fmt_time(seconds):
    return "-" if seconds is None else f"{seconds * 1000:.1f} ms"


def fmt_mem(kb):
    return "-" if kb is None else f"{kb / 1024:.0f} MB"


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    run = pathlib.Path(argv[1])
    if not run.is_dir():
        print(f"error: not a directory: {run}", file=sys.stderr)
        return 1

    found = {p.name[: -len("_column-rs.json")] for p in run.glob("*_column-rs.json")}
    names = [n for n in ORDER if n in found] + sorted(found - set(ORDER))
    if not names:
        print(f"error: no hyperfine exports found in {run}", file=sys.stderr)
        return 1

    rows = []
    for name in names:
        ours = median_seconds(run / f"{name}_column-rs.json")
        theirs = median_seconds(run / f"{name}_duckdb.json")
        ratio = ours / theirs if ours and theirs else None
        rows.append((name, ours, theirs, ratio,
                     peak_rss_kb(run / f"{name}_memory.txt", "column-rs"),
                     peak_rss_kb(run / f"{name}_memory.txt", "duckdb")))

    print(f"# Benchmark: {run.name}\n")
    print("| Query | column-rs | DuckDB | Ratio | Target | column-rs RSS | DuckDB RSS |")
    print("|-------|-----------|--------|-------|--------|---------------|------------|")
    for name, ours, theirs, ratio, our_rss, their_rss in rows:
        if ratio is None:
            verdict, shown = "-", "-"
        else:
            verdict = "PASS" if ratio <= TARGET_RATIO else "FAIL"
            shown = f"{ratio:.2f}x"
        print(f"| {name} | {fmt_time(ours)} | {fmt_time(theirs)} | {shown} "
              f"| {verdict} | {fmt_mem(our_rss)} | {fmt_mem(their_rss)} |")

    ratios = [r for *_, r, _, _ in rows if r is not None]
    if ratios:
        worst = max(ratios)
        print(f"\n- Worst ratio: **{worst:.2f}x** "
              f"(target <= {TARGET_RATIO}x, stretch <= 1.0x)")
        within = sum(1 for r in ratios if r <= TARGET_RATIO)
        print(f"- Within target: {within}/{len(ratios)} queries")

    size_file = run / "binary_size_bytes.txt"
    if size_file.exists():
        size = int(size_file.read_text().strip())
        ok = "PASS" if size <= BINARY_SIZE_LIMIT else "FAIL"
        print(f"- Binary size: {size / 1024 / 1024:.2f} MB (target <= 5 MB) — {ok}")

    # Non-zero exit when any query misses the bar, so a local run can be
    # scripted against: 3, apart from the errors above, so a caller can
    # still record a complete run that misses it (perf/column-rs `make
    # status`). Deliberately not wired into CI: shared runners vary too
    # much between runs to compare two engines on (`order_by` measured
    # 0.89x locally and 2.19x on a hosted runner from identical data).
    if not ratios:
        return 1
    return 0 if max(ratios) <= TARGET_RATIO else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
