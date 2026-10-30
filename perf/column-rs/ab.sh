#!/usr/bin/env bash
# A/B two engines over the parity queries and data (benchmark#23).
#
#   ./ab.sh [a] [b] [size] [query]
#
# A side is `duckdb` or a column-rs binary. By default a is DuckDB and b is
# column-rs, found by lib/tool.sh: $COLUMN_RS, else built in the tools
# checkout next to this repo, else the one on PATH. Give two column-rs
# binaries to compare builds. Missing data for `size` (default large) is
# generated first.
#
# Each query runs in ROUNDS rounds of RUNS timed runs per side, the order
# of the two sides swapping every round, so a busy stretch on the machine
# lands on both instead of one (a single back-to-back run showed a
# "slowdown" of 1.5x that was noise, db-core#841). Peak RSS is the median
# of three runs per side. Both sides must emit the same number of rows.
#
# Results land in results/ab_<size>_<timestamp>/ (gitignored), with the
# table in report.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PARITY="$ROOT/../../parity/column-rs"
. "$ROOT/../../lib/tool.sh"

A="${1:-duckdb}"
B="${2:-}"
SIZE="${3:-large}"
ONLY="${4:-}"
ROUNDS="${ROUNDS:-3}"
RUNS="${RUNS:-10}"
FACT="$PARITY/data/${SIZE}.parquet"
DIM="$PARITY/data/${SIZE}_customers.parquet"

for tool in duckdb hyperfine; do
    command -v "$tool" >/dev/null || { echo "error: $tool not on PATH" >&2; exit 1; }
done
[ -n "$B" ] || B="$(find_tool column-rs column-rs COLUMN_RS)"
for side in "$A" "$B"; do
    [ "$side" = duckdb ] || [ -x "$side" ] || { echo "error: not duckdb or an executable: $side" >&2; exit 1; }
done
if [ ! -f "$FACT" ] || [ ! -f "$DIM" ]; then
    echo "no $SIZE parity data: generating it" >&2
    "$PARITY/data/generate.sh" "$SIZE"
fi

# The parity suite's table names come from the file stems; DuckDB gets
# views of the same names.
LINKS="$(mktemp -d)"
trap 'rm -rf "$LINKS"' EXIT
ln -sf "$FACT" "$LINKS/bench.parquet"
ln -sf "$DIM" "$LINKS/bench_customers.parquet"
TABLES="$LINKS/bench.parquet $LINKS/bench_customers.parquet"
INIT="$LINKS/init.sql"
cat > "$INIT" <<SQL
CREATE VIEW bench AS SELECT * FROM read_parquet('$LINKS/bench.parquet');
CREATE VIEW bench_customers AS SELECT * FROM read_parquet('$LINKS/bench_customers.parquet');
SQL

# One side's command line for `sql`, as one string for hyperfine.
command_for() {
    if [ "$1" = duckdb ]; then
        echo "duckdb -init $INIT -batch -noheader -csv -c \"$2\""
    else
        echo "$1 -c \"$2\" $TABLES"
    fi
}

# The rows one side emits for `sql`: column-rs prints a header line first.
# DuckDB's `-csv` prints every row, where its default mode stops at 40
# (benchmark#10).
rows_for() {
    if [ "$1" = duckdb ]; then
        duckdb -init "$INIT" -batch -noheader -csv -c "$2" 2>/dev/null | wc -l | tr -d ' '
    else
        # shellcheck disable=SC2086
        "$1" -c "$2" $TABLES | tail -n +2 | wc -l | tr -d ' '
    fi
}

version_of() {
    "$1" --version 2>/dev/null | head -1
}

# Peak resident set size in KB (GNU `time -v` or BSD/macOS `time -l`).
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

rss_for() {
    if [ "$1" = duckdb ]; then
        peak_rss_kb duckdb -init "$INIT" -batch -noheader -csv -c "$2"
    else
        # shellcheck disable=SC2086
        peak_rss_kb "$1" -c "$2" $TABLES
    fi
}

OUT="$ROOT/results/ab_${SIZE}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
{ echo "a $A $(version_of "$A")"; echo "b $B $(version_of "$B")"; } > "$OUT/sides.txt"

cat "$OUT/sides.txt"
echo "size=$SIZE  rounds=$ROUNDS x $RUNS runs  results=$OUT"
echo

for query in "$PARITY"/queries/*.sql; do
    name="$(basename "$query" .sql)"
    [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
    sql="$(grep -v '^[[:space:]]*--' "$query" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
    echo "=== $name"

    a_rows="$(rows_for "$A" "$sql")"
    b_rows="$(rows_for "$B" "$sql")"
    if [ "$a_rows" != "$b_rows" ]; then
        echo "error: $name: a emitted $a_rows rows, b $b_rows -- not comparable" >&2
        exit 1
    fi

    for round in $(seq 1 "$ROUNDS"); do
        a_cmd=(-n a "$(command_for "$A" "$sql")")
        b_cmd=(-n b "$(command_for "$B" "$sql")")
        if [ $((round % 2)) -eq 1 ]; then order=("${a_cmd[@]}" "${b_cmd[@]}"); else order=("${b_cmd[@]}" "${a_cmd[@]}"); fi
        hyperfine -N --style none --warmup 2 --runs "$RUNS" \
            --export-json "$OUT/${name}_round${round}.json" "${order[@]}" >/dev/null
    done

    for _ in 1 2 3; do
        echo "a $(rss_for "$A" "$sql")"
        echo "b $(rss_for "$B" "$sql")"
    done > "$OUT/${name}_memory.txt"
done

python3 "$ROOT/ab_report.py" "$OUT"
