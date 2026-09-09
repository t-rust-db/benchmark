#!/usr/bin/env bash
# trigrep vs ripgrep (always-cold baseline) vs microsoft/tgrep (optional,
# not built for you) parity benchmark.
#
# Searches a REAL directory tree, not synthetic data: by default
# ../../../sqlite-rs -- a real, single git work tree (so trigrep's git
# integration correctly respects its .gitignore, unlike the raw t-rust-db
# org root, which isn't one git repo itself and made a first draft of
# this default walk every crate's target/ directory across every sibling
# -- found by trying it: the run never finished). 161 .rs files as of
# 2026-09-09. Point it at anything else with $CORPUS_ROOT -- including
# the whole org checkout, if you also exclude target/ some other way.
#
#   ./run.sh                        # every query against the default corpus
#   ./run.sh rare_literal            # one query only
#   CORPUS_ROOT=/some/other/tree ./run.sh
#
# Two phases:
#   1. Cold build: `tg index` (and `tgrep index`, if tgrep is resolved)
#      timed once each -- a one-time setup cost, not something hyperfine's
#      repeated-run averaging is the right tool for -- plus the resulting
#      index/cache size on disk.
#   2. Warm search: every pattern in queries/*.txt run against trigrep
#      (cache already built in phase 1), tgrep (server already warm, if
#      present) and ripgrep (no index exists for ripgrep to warm --
#      that's the point of the comparison: what does the index buy you
#      over a tool that is always doing a full scan).
#
# Results land in results/<timestamp>/ as hyperfine JSON plus a peak-RSS
# reading per engine; report.py renders the comparison table.
#
# ## Which binaries and corpus?
#
# This repo does not build trigrep, tgrep or ripgrep, and does not
# generate the corpus -- it needs a real tree, resolved in this order:
#   corpus:  $CORPUS_ROOT -> ../../../sqlite-rs  (a real sibling repo, the
#            standard layout when this repo is a sibling of trigrep etc.)
#   trigrep: $TG on PATH-as-set -> `tg` on $PATH -> ../../../trigrep/target/release/tg
#   ripgrep: $RG               -> `rg` on $PATH (required -- the baseline)
#   tgrep:   $TGREP            -> `tgrep` on $PATH -> skipped entirely if absent
#            (microsoft/tgrep is not published to crates.io; build it
#            yourself: cargo install --git https://github.com/microsoft/tgrep
#            tgrep-cli --locked, or point $TGREP at an existing binary)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ONLY="${1:-}"
WARMUP="${WARMUP:-3}"
MIN_RUNS="${MIN_RUNS:-10}"

CORPUS="${CORPUS_ROOT:-$ROOT/../../../sqlite-rs}"
if [ ! -d "$CORPUS" ]; then
    echo "error: corpus directory not found: '$CORPUS'" >&2
    echo "  set \$CORPUS_ROOT to a real directory tree to search" >&2
    exit 1
fi
CORPUS="$(cd "$CORPUS" && pwd)"

# --- Resolve binaries (see header comment for the order) ------------------
if [ -n "${TG:-}" ]; then
    TG_BIN="$TG"
elif command -v tg >/dev/null 2>&1; then
    TG_BIN="$(command -v tg)"
else
    TG_BIN="$ROOT/../../../trigrep/target/release/tg"
fi
if [ ! -x "$TG_BIN" ]; then
    echo "error: no trigrep binary found at '$TG_BIN'" >&2
    echo "  set \$TG to an explicit path, put 'tg' on \$PATH, or build in place:" >&2
    echo "  (cd ../../../trigrep && cargo build --release)" >&2
    exit 1
fi

if [ -n "${RG:-}" ]; then
    RG_BIN="$RG"
elif command -v rg >/dev/null 2>&1; then
    RG_BIN="$(command -v rg)"
else
    echo "error: ripgrep ('rg') not found on PATH -- it is the always-cold baseline, required" >&2
    exit 1
fi

TGREP_BIN=""
if [ -n "${TGREP:-}" ]; then
    TGREP_BIN="$TGREP"
elif command -v tgrep >/dev/null 2>&1; then
    TGREP_BIN="$(command -v tgrep)"
fi
if [ -n "$TGREP_BIN" ] && [ ! -x "$TGREP_BIN" ]; then
    echo "warning: \$TGREP set to '$TGREP_BIN' but it is not executable -- skipping tgrep" >&2
    TGREP_BIN=""
fi

# Independent, disposable cache/index dirs per run so this script never
# touches a real ~/.cache/{trigrep,tgrep} and two runs never collide.
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
export TRIGREP_CACHE_DIR="$WORKDIR/trigrep-cache"
mkdir -p "$TRIGREP_CACHE_DIR"

RESULTS="results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS"

# Peak resident set size in KB. GNU time reports `Maximum resident set size
# (kbytes)`; BSD/macOS `time -l` reports `maximum resident set size` in
# bytes. Ported from ../column-rs/run.sh.
peak_rss_kb() {
    local out
    if /usr/bin/time -v true >/dev/null 2>&1; then
        out="$(/usr/bin/time -v "$@" 2>&1 >/dev/null | awk '/Maximum resident set size/ {print $NF}')"
        echo "${out:-0}"
    else
        out="$(/usr/bin/time -l "$@" 2>&1 >/dev/null | awk '/maximum resident set size/ {print $1}')"
        echo $(( ${out:-0} / 1024 ))
    fi
}

dir_size_kb() {
    du -sk "$1" 2>/dev/null | cut -f1 || echo 0
}

echo "trigrep: $TG_BIN"
echo "ripgrep: $RG_BIN"
if [ -n "$TGREP_BIN" ]; then echo "tgrep:   $TGREP_BIN"; else echo "tgrep:   (not found -- skipped)"; fi
echo "corpus=$CORPUS ($(find "$CORPUS" -name '*.rs' -not -path '*/target/*' 2>/dev/null | wc -l | tr -d ' ') .rs files)  results=$RESULTS"
echo

# === Phase 1: cold build =====================================================

echo "=== build ==="
{
    /usr/bin/time -p "$TG_BIN" index "$CORPUS" 2> "$RESULTS/build_trigrep_time.txt" >/dev/null
    echo "trigrep $(peak_rss_kb "$TG_BIN" index "$CORPUS")" > "$RESULTS/build_memory.txt"
} || true
echo "trigrep index size: $(dir_size_kb "$TRIGREP_CACHE_DIR") KB"
echo "$(dir_size_kb "$TRIGREP_CACHE_DIR")" > "$RESULTS/index_size_kb_trigrep.txt"

if [ -n "$TGREP_BIN" ]; then
    TGREP_INDEX="$WORKDIR/tgrep-index"
    (
        cd "$CORPUS"
        /usr/bin/time -p "$TGREP_BIN" index --index-dir "$TGREP_INDEX" . 2> "$ROOT/$RESULTS/build_tgrep_time.txt" >/dev/null
    ) || true
    echo "tgrep $(peak_rss_kb "$TGREP_BIN" index --index-dir "$TGREP_INDEX" "$CORPUS")" >> "$RESULTS/build_memory.txt"
    echo "tgrep index size: $(dir_size_kb "$TGREP_INDEX") KB"
    echo "$(dir_size_kb "$TGREP_INDEX")" > "$RESULTS/index_size_kb_tgrep.txt"
fi
echo

# === Phase 2: warm search ====================================================

for query in queries/*.txt; do
    name="$(basename "$query" .txt)"
    [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue

    pattern="$(grep -v '^[[:space:]]*#' "$query" | sed '/^[[:space:]]*$/d')"
    flag=""
    [ "$name" = "case_insensitive" ] && flag="-i"

    echo "=== $name ==="
    echo "    pattern: $pattern  flags: ${flag:-<none>}"

    # hyperfine takes each positional as a full shell command STRING to
    # compare, not `--`-separated argv for one command; build one quoted
    # string per invocation (same convention ../column-rs's run.sh uses).
    hyperfine --warmup "$WARMUP" --min-runs "$MIN_RUNS" \
        --command-name "trigrep" \
        --export-json "$RESULTS/${name}_trigrep.json" \
        "$TG_BIN $flag \"$pattern\" $CORPUS"

    hyperfine --warmup "$WARMUP" --min-runs "$MIN_RUNS" \
        --command-name "ripgrep" \
        --export-json "$RESULTS/${name}_ripgrep.json" \
        "$RG_BIN $flag \"$pattern\" $CORPUS"

    {
        echo "trigrep $(peak_rss_kb "$TG_BIN" $flag "$pattern" "$CORPUS")"
        echo "ripgrep $(peak_rss_kb "$RG_BIN" $flag "$pattern" "$CORPUS")"
    } > "$RESULTS/${name}_memory.txt"

    if [ -n "$TGREP_BIN" ]; then
        hyperfine --warmup "$WARMUP" --min-runs "$MIN_RUNS" \
            --command-name "tgrep" \
            --export-json "$RESULTS/${name}_tgrep.json" \
            "$TGREP_BIN $flag \"$pattern\" $CORPUS"
        echo "tgrep $(peak_rss_kb "$TGREP_BIN" $flag "$pattern" "$CORPUS")" >> "$RESULTS/${name}_memory.txt"
    fi

    echo
done

python3 report.py "$RESULTS" | tee "$RESULTS/report.md"
