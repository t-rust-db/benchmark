#!/usr/bin/env python3
"""Renders an `ab.sh` run (benchmark#23): per query, the median of every
timed run of each side across all rounds, the median of its three peak-RSS
readings, and b's change from a. Prints the table and writes it to
<run>/report.md.

Usage:
    python3 ab_report.py results/ab_<size>_<timestamp>
"""

import json
import statistics
import sys
from pathlib import Path


def times(run, name):
    """Every timed run of each side across the query's rounds, in seconds."""
    out = {"a": [], "b": []}
    for path in sorted(run.glob(f"{name}_round*.json")):
        for result in json.loads(path.read_text())["results"]:
            out[result["command"]].extend(result["times"])
    return out


def rss_kb(run, name):
    out = {"a": [], "b": []}
    for line in (run / f"{name}_memory.txt").read_text().splitlines():
        side, _, value = line.partition(" ")
        out[side].append(int(value))
    return {side: statistics.median(v) for side, v in out.items() if v}


def change(a, b):
    return f"{(b - a) / a * 100:+.0f}%" if a else "-"


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    run = Path(argv[1])
    names = sorted({p.name.split("_round")[0] for p in run.glob("*_round*.json")})
    lines = [line.split(" ", 2) + [""] for line in (run / "sides.txt").read_text().splitlines()]
    out = [f"# A/B: {run.name}", ""]
    out += [f"- {side}: `{path}` {version}".rstrip() for side, path, version, *_ in lines]
    out += ["", "| Query | a | b | b vs a | a RSS | b RSS | b vs a |",
            "|-------|---|---|--------|-------|-------|--------|"]
    for name in names:
        t = {b: statistics.median(v) for b, v in times(run, name).items()}
        m = rss_kb(run, name)
        out.append(f"| {name} | {t['a'] * 1000:.1f} ms | {t['b'] * 1000:.1f} ms | "
                   f"{change(t['a'], t['b'])} | {m['a'] / 1024:.0f} MB | "
                   f"{m['b'] / 1024:.0f} MB | {change(m['a'], m['b'])} |")
    report = "\n".join(out) + "\n"
    (run / "report.md").write_text(report)
    print(report)


if __name__ == "__main__":
    main(sys.argv)
