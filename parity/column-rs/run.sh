#!/usr/bin/env bash
# DuckDB parity benchmark for column-rs, adapted from column-rs's own
# benches/run.sh (github.com/iheitlager/column-rs, #100) into this separate
# `benchmark` repo so parity testing lives alongside every other t-rust-db
# product's benchmarks, decoupled from any one product's own release cycle.
#
#   ./run.sh                 # medium (100K rows)
#   ./run.sh large           # 10M rows
#   ./run.sh medium scan     # one query only
#
# Runs every queries/*.sql against both column-rs and DuckDB with the
# *identical* SQL text: DuckDB gets views named after the tables column-rs
# derives from the file stems (`bench`, `bench_customers`), so neither engine
# is handed a rewritten query.
#
# Results land in results/<size>_<timestamp>/ as hyperfine JSON plus a
# peak-RSS reading per engine, and report.py renders the comparison table.
#
# ## Which column-rs binary?
#
# This repo does not build column-rs itself (it's a separate product with
# its own release cycle) -- it needs a binary to point at, resolved in this
# order:
#   1. $COLUMN_RS       -- explicit path to a column-rs binary, if set
#   2. `column-rs` on $PATH -- a globally installed/linked build
#   3. ../../../column-rs/target/release/column-rs -- i.e. t-rust-db/column-rs
#      built in place, the normal case when this benchmark repo is checked
#      out as a sibling of column-rs under t-rust-db/ (the standard layout)
#
# The fallback does NOT try to `cargo build` column-rs on your behalf --
# build it yourself first (`cd ../../../column-rs && cargo build --release`)
# so this script stays a pure benchmark runner, not a build orchestrator for
# a product it doesn't own.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SIZE="${1:-medium}"
ONLY="${2:-}"
WARMUP="${WARMUP:-3}"
MIN_RUNS="${MIN_RUNS:-10}"

DATA="data"
FACT="$DATA/${SIZE}.parquet"
DIM="$DATA/${SIZE}_customers.parquet"

# --- Resolve the column-rs binary (see header comment for the order) ------
if [ -n "${COLUMN_RS:-}" ]; then
    BIN="$COLUMN_RS"
elif command -v column-rs >/dev/null 2>&1; then
    BIN="$(command -v column-rs)"
else
    BIN="$ROOT/../../../column-rs/target/release/column-rs"
fi

if [ ! -x "$BIN" ]; then
    echo "error: no column-rs binary found at '$BIN'" >&2
    echo "  set \$COLUMN_RS to an explicit binary path, or put column-rs on \$PATH," >&2
    echo "  or build it in place: (cd ../../../column-rs && cargo build --release)" >&2
    exit 1
fi

for tool in duckdb hyperfine; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found on PATH" >&2; exit 1; }
done

if [ ! -f "$FACT" ] || [ ! -f "$DIM" ]; then
    echo "error: missing benchmark data for size '$SIZE'" >&2
    echo "  generate it with: ./data/generate.sh $SIZE" >&2
    exit 1
fi

# column-rs names a table after its file stem, so the data files are linked
# under stable names and the queries can hardcode `bench`/`bench_customers`.
LINKS="$(mktemp -d)"
trap 'rm -rf "$LINKS"' EXIT
ln -sf "$ROOT/$FACT" "$LINKS/bench.parquet"
ln -sf "$ROOT/$DIM" "$LINKS/bench_customers.parquet"

# Give DuckDB the same table names via views over the same files.
INIT="$LINKS/init.sql"
cat > "$INIT" <<EOF
CREATE VIEW bench AS SELECT * FROM read_parquet('$LINKS/bench.parquet');
CREATE VIEW bench_customers AS SELECT * FROM read_parquet('$LINKS/bench_customers.parquet');
EOF

RESULTS="results/${SIZE}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS"

# Peak resident set size in KB. GNU time reports `Maximum resident set size
# (kbytes)`; BSD/macOS `time -l` reports `maximum resident set size` in bytes.
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

echo "column-rs binary: $BIN"
echo "size=$SIZE  fact=$(du -h "$FACT" | cut -f1)  results=$RESULTS"
echo

for query in queries/*.sql; do
    name="$(basename "$query" .sql)"
    [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue

    # Strip the leading `--` commentary so both CLIs get a bare statement.
    sql="$(grep -v '^[[:space:]]*--' "$query" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"

    echo "=== $name ==="
    echo "    $sql"

    hyperfine --warmup "$WARMUP" --min-runs "$MIN_RUNS" \
        --command-name "column-rs" \
        --export-json "$RESULTS/${name}_column-rs.json" \
        "$BIN -c \"$sql\" $LINKS/bench.parquet $LINKS/bench_customers.parquet"

    hyperfine --warmup "$WARMUP" --min-runs "$MIN_RUNS" \
        --command-name "duckdb" \
        --export-json "$RESULTS/${name}_duckdb.json" \
        "duckdb -init $INIT -batch -noheader -c \"$sql\""

    {
        echo "column-rs $(peak_rss_kb "$BIN" -c "$sql" "$LINKS/bench.parquet" "$LINKS/bench_customers.parquet")"
        echo "duckdb $(peak_rss_kb duckdb -init "$INIT" -batch -noheader -c "$sql")"
    } > "$RESULTS/${name}_memory.txt"

    echo
done

# Binary size is a headline metric (target: <= 5MB) -- tracked here since
# it's a parity/product-comparison concern, not something column-rs's own
# test suite needs to assert on every build.
wc -c < "$BIN" | tr -d ' ' > "$RESULTS/binary_size_bytes.txt"

python3 report.py "$RESULTS" | tee "$RESULTS/report.md"
