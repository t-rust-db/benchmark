#!/usr/bin/env python3
"""Records the latest parity run in results/bench-status.json under the
column-rs version and data size that produced it (benchmark#23): the
committed, release-to-release history `../../parity/column-rs/results/`
(gitignored) doesn't keep. One entry per column-rs version and size;
re-running one replaces its entry.

Usage (normally via `make status`, which runs the parity suite first):
    python3 status.py --binary <column-rs> [--size large] [--tools-repo ../../../tools]
"""

import argparse
import datetime
import json
import os
import platform
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PARITY_RESULTS = ROOT / "../../parity/column-rs/results"
STATUS = ROOT / "results" / "bench-status.json"


def column_rs_version(binary):
    out = subprocess.run([binary, "--version"], capture_output=True, text=True, check=True)
    return out.stdout.split()[-1]


def db_core_version(tools_repo):
    """The db-core version the tools checkout pins, from its Cargo.lock, or
    None when there is no checkout to read."""
    try:
        lock = (Path(tools_repo) / "Cargo.lock").read_text()
    except OSError:
        return None
    m = re.search(r'name = "db-core"\nversion = "([^"]+)"', lock)
    return m.group(1) if m else None


def hardware():
    cpu = "unknown"
    if platform.system() == "Darwin":
        cpu = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"],
                             capture_output=True, text=True).stdout.strip() or cpu
    elif Path("/proc/cpuinfo").exists():
        m = re.search(r"model name\s*:\s*(.+)", Path("/proc/cpuinfo").read_text())
        cpu = m.group(1).strip() if m else cpu
    return {"platform": platform.platform(), "cpu": cpu, "cpu_count": os.cpu_count()}


def median_ms(path):
    results = json.loads(path.read_text())["results"]
    return round(results[0]["median"] * 1000, 2)


def rss_mb(path):
    out = {}
    for line in path.read_text().splitlines():
        engine, _, kb = line.partition(" ")
        out[engine] = round(int(kb) / 1024)
    return out


def latest_run(size):
    runs = sorted(PARITY_RESULTS.glob(f"{size}_*"))
    if not runs:
        raise SystemExit(f"no parity run for size {size} under {PARITY_RESULTS}")
    return runs[-1]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--binary", required=True)
    ap.add_argument("--size", default="large")
    ap.add_argument("--tools-repo", default=str(ROOT / "../../../tools"))
    args = ap.parse_args()

    run = latest_run(args.size)
    queries = []
    for ours in sorted(run.glob("*_column-rs.json")):
        name = ours.name.removesuffix("_column-rs.json")
        ours_ms, theirs_ms = median_ms(ours), median_ms(run / f"{name}_duckdb.json")
        rss = rss_mb(run / f"{name}_memory.txt")
        queries.append({
            "query": name,
            "column_rs_ms": ours_ms,
            "duckdb_ms": theirs_ms,
            "ratio": round(ours_ms / theirs_ms, 2),
            "column_rs_rss_mb": rss.get("column-rs"),
            "duckdb_rss_mb": rss.get("duckdb"),
        })
    entry = {
        "column_rs": column_rs_version(args.binary),
        "db_core": db_core_version(args.tools_repo),
        "date": datetime.date.today().isoformat(),
        "size": args.size,
        "parity_run": run.name,
        "binary_size_bytes": int((run / "binary_size_bytes.txt").read_text()),
        "hardware": hardware(),
        "queries": queries,
    }

    status = json.loads(STATUS.read_text()) if STATUS.exists() else {"releases": []}
    key = (entry["column_rs"], entry["size"])
    releases = [r for r in status["releases"] if (r["column_rs"], r["size"]) != key]
    releases.append(entry)
    releases.sort(key=lambda r: (tuple(int(p) for p in r["column_rs"].split(".")), r["size"]))
    STATUS.parent.mkdir(exist_ok=True)
    STATUS.write_text(json.dumps({"releases": releases}, indent=2) + "\n")
    worst = max(queries, key=lambda q: q["ratio"])
    print(f"recorded column-rs {entry['column_rs']} (db-core {entry['db_core']}): "
          f"{len(queries)} queries, worst {worst['query']} {worst['ratio']}x -> {STATUS}")


if __name__ == "__main__":
    main()
