#!/usr/bin/env python3
"""Renders an `ab.sh` run (benchmark#23): per query, the median of every
timed run of each build across all rounds, the median of its three peak-RSS
readings, and the change from old to new. Prints the table and writes it to
<run>/report.md.

Usage:
    python3 ab_report.py results/ab_<size>_<timestamp>
"""

import json
import statistics
import sys
from pathlib import Path


def times(run, name):
    """Every timed run of each build across the query's rounds, in seconds."""
    out = {"old": [], "new": []}
    for path in sorted(run.glob(f"{name}_round*.json")):
        for result in json.loads(path.read_text())["results"]:
            out[result["command"]].extend(result["times"])
    return out


def rss_kb(run, name):
    out = {"old": [], "new": []}
    for line in (run / f"{name}_memory.txt").read_text().splitlines():
        build, _, value = line.partition(" ")
        out[build].append(int(value))
    return {build: statistics.median(v) for build, v in out.items() if v}


def change(old, new):
    return f"{(new - old) / old * 100:+.0f}%" if old else "-"


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    run = Path(argv[1])
    names = sorted({p.name.split("_round")[0] for p in run.glob("*_round*.json")})
    lines = [line.split(" ", 2) for line in (run / "binaries.txt").read_text().splitlines()]
    out = [f"# A/B: {run.name}", ""]
    out += [f"- {build}: `{path}` ({version})" for build, path, version in lines]
    out += ["", "| Query | old | new | time | old RSS | new RSS | RSS |",
            "|-------|-----|-----|------|---------|---------|-----|"]
    for name in names:
        t = {b: statistics.median(v) for b, v in times(run, name).items()}
        m = rss_kb(run, name)
        out.append(f"| {name} | {t['old'] * 1000:.1f} ms | {t['new'] * 1000:.1f} ms | "
                   f"{change(t['old'], t['new'])} | {m['old'] / 1024:.0f} MB | "
                   f"{m['new'] / 1024:.0f} MB | {change(m['old'], m['new'])} |")
    report = "\n".join(out) + "\n"
    (run / "report.md").write_text(report)
    print(report)


if __name__ == "__main__":
    main(sys.argv)
