#!/usr/bin/env python3
"""Render the trigrep vs ripgrep (vs optional tgrep) comparison table for a
benchmark run.

Usage: python3 report.py results/<run-dir>

Reads the hyperfine JSON exports and peak-RSS readings that run.sh wrote and
prints the markdown comparison table to stdout. Standard library only.

Unlike the column-rs/DuckDB parity benchmark (same repo, ../column-rs),
"pass" here isn't parity with the baseline -- it's the opposite: trigrep
exists to be *faster* than ripgrep's always-cold full scan by using an
index ripgrep doesn't have. The bar is a minimum speedup, not a ceiling.
"""

import json
import pathlib
import sys

# Query order in the report; anything found on disk but not listed here is
# appended afterwards rather than dropped.
ORDER = [
    "common_literal",
    "short_class",
    "rare_literal",
    "alternation",
    "case_insensitive",
]

# Minimum acceptable speedup over ripgrep's always-cold scan. A query with
# no extractable required trigram (short_class) or that forces a full scan
# by design (case_insensitive) is expected to land near 1x -- see the SKIP
# set below, not a failure of the tool.
TARGET_SPEEDUP = 1.5
# Only rare_literal is a genuine index-benefit query in this set; the other
# four are deliberately the floor, for four distinct reasons (see
# ../queries/*.txt): too common to narrow, no extractable literal, an
# alternation (extracts nothing, by design), and -i (bypasses the index
# entirely). Graded here as "no benefit expected", not "FAIL".
NO_INDEX_BENEFIT_EXPECTED = {"common_literal", "short_class", "case_insensitive", "alternation"}


def mean_seconds(path):
    """Mean wall time from a hyperfine JSON export, or None if unusable."""
    try:
        with open(path) as fh:
            results = json.load(fh)["results"]
    except (OSError, ValueError, KeyError):
        return None
    return results[0]["mean"] if results else None


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


def fmt_kb_file(path):
    try:
        return f"{int(path.read_text().strip()) / 1024:.1f} MB"
    except (OSError, ValueError):
        return "-"


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    run = pathlib.Path(argv[1])
    if not run.is_dir():
        print(f"error: not a directory: {run}", file=sys.stderr)
        return 1

    found = {p.name[: -len("_trigrep.json")] for p in run.glob("*_trigrep.json")}
    names = [n for n in ORDER if n in found] + sorted(found - set(ORDER))
    if not names:
        print(f"error: no hyperfine exports found in {run}", file=sys.stderr)
        return 1

    has_tgrep = any((run / f"{n}_tgrep.json").exists() for n in names)

    print(f"# Benchmark: {run.name}\n")
    header = ["Query", "trigrep", "ripgrep", "Speedup", "Target"]
    if has_tgrep:
        header.insert(3, "tgrep")
    print("| " + " | ".join(header) + " |")
    print("|" + "|".join(["---"] * len(header)) + "|")

    ratios = []
    for name in names:
        ours = mean_seconds(run / f"{name}_trigrep.json")
        theirs = mean_seconds(run / f"{name}_ripgrep.json")
        ratio = theirs / ours if ours and theirs else None  # >1 means trigrep is faster
        expect_benefit = name not in NO_INDEX_BENEFIT_EXPECTED
        if ratio is None:
            verdict = "-"
        elif not expect_benefit:
            verdict = "N/A (no index benefit expected)"
        else:
            verdict = "PASS" if ratio >= TARGET_SPEEDUP else "FAIL"
            ratios.append(ratio)
        row = [name, fmt_time(ours), fmt_time(theirs)]
        if has_tgrep:
            row.append(fmt_time(mean_seconds(run / f"{name}_tgrep.json")))
        row += [f"{ratio:.2f}x" if ratio is not None else "-", verdict]
        print("| " + " | ".join(row) + " |")

    if ratios:
        worst = min(ratios)
        print(f"\n- Worst speedup (index-benefit queries only): **{worst:.2f}x** "
              f"(target >= {TARGET_SPEEDUP}x over ripgrep's always-cold scan)")
        within = sum(1 for r in ratios if r >= TARGET_SPEEDUP)
        print(f"- Meeting target: {within}/{len(ratios)} queries")

    build_time = run / "build_trigrep_time.txt"
    if build_time.exists():
        # `/usr/bin/time -p` prints `real N.NN` on its own line.
        real = next((l.split()[1] for l in build_time.read_text().splitlines()
                     if l.startswith("real")), None)
        print(f"\n- trigrep cold build time: {real or '-'}s")
    build_mem_trigrep = peak_rss_kb(run / "build_memory.txt", "trigrep")
    if build_mem_trigrep is not None:
        print(f"- trigrep cold build peak RSS: {fmt_mem(build_mem_trigrep)}")
    idx_size = run / "index_size_kb_trigrep.txt"
    if idx_size.exists():
        print(f"- trigrep index size on disk: {fmt_kb_file(idx_size)}")

    if has_tgrep:
        build_mem_tgrep = peak_rss_kb(run / "build_memory.txt", "tgrep")
        if build_mem_tgrep is not None:
            print(f"- tgrep cold build peak RSS: {fmt_mem(build_mem_tgrep)}")
        idx_size_tgrep = run / "index_size_kb_tgrep.txt"
        if idx_size_tgrep.exists():
            print(f"- tgrep index size on disk: {fmt_kb_file(idx_size_tgrep)}")
    else:
        print("\n_tgrep not found -- comparison limited to trigrep vs ripgrep. "
              "See run.sh's header for how to point at a tgrep binary._")

    # Non-zero exit when any index-benefit query misses the bar. Not wired
    # into CI (see column-rs's report.py for why: shared runners vary too
    # much between runs to compare two tools' wall-clock time on).
    return 0 if not ratios or min(ratios) >= TARGET_SPEEDUP else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
