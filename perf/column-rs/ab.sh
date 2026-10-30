#!/usr/bin/env bash
# A/B two column-rs builds over the parity queries and data (benchmark#23).
#
#   ./ab.sh <old-binary> <new-binary> [size] [query]
#
# Each query runs in ROUNDS rounds of RUNS timed runs per build, the order
# of the two builds swapping every round, so a busy stretch on the machine
# lands on both sides instead of one (a single back-to-back run showed a
# "slowdown" of 1.5x that was noise, db-core#841). Peak RSS is the median
# of three runs per build. Both builds must emit the same number of rows.
#
# Results land in results/ab_<size>_<timestamp>/ (gitignored), with the
# table in report.md.
set -euo pipefail

OLD="${1:?usage: ab.sh <old-binary> <new-binary> [size] [query]}"
NEW="${2:?usage: ab.sh <old-binary> <new-binary> [size] [query]}"
SIZE="${3:-large}"
ONLY="${4:-}"
ROUNDS="${ROUNDS:-3}"
RUNS="${RUNS:-10}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
PARITY="$ROOT/../../parity/column-rs"
FACT="$PARITY/data/${SIZE}.parquet"
DIM="$PARITY/data/${SIZE}_customers.parquet"

for bin in "$OLD" "$NEW"; do
    [ -x "$bin" ] || { echo "error: not an executable: $bin" >&2; exit 1; }
done
command -v hyperfine >/dev/null || { echo "error: hyperfine not on PATH" >&2; exit 1; }
[ -f "$FACT" ] || { echo "error: $FACT missing -- run $PARITY/data/generate.sh" >&2; exit 1; }

# The parity suite's table names come from the file stems.
LINKS="$(mktemp -d)"
trap 'rm -rf "$LINKS"' EXIT
ln -sf "$FACT" "$LINKS/bench.parquet"
ln -sf "$DIM" "$LINKS/bench_customers.parquet"
TABLES="$LINKS/bench.parquet $LINKS/bench_customers.parquet"

OUT="$ROOT/results/ab_${SIZE}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
{ echo "old $OLD $("$OLD" --version)"; echo "new $NEW $("$NEW" --version)"; } > "$OUT/binaries.txt"

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

cat "$OUT/binaries.txt"
echo "size=$SIZE  rounds=$ROUNDS x $RUNS runs  results=$OUT"
echo

for query in "$PARITY"/queries/*.sql; do
    name="$(basename "$query" .sql)"
    [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
    sql="$(grep -v '^[[:space:]]*--' "$query" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
    echo "=== $name"

    # shellcheck disable=SC2086
    old_rows="$("$OLD" -c "$sql" $TABLES | wc -l | tr -d ' ')"
    # shellcheck disable=SC2086
    new_rows="$("$NEW" -c "$sql" $TABLES | wc -l | tr -d ' ')"
    if [ "$old_rows" != "$new_rows" ]; then
        echo "error: $name: old emitted $old_rows lines, new $new_rows -- not comparable" >&2
        exit 1
    fi

    for round in $(seq 1 "$ROUNDS"); do
        old_cmd=(-n old "$OLD -c \"$sql\" $TABLES")
        new_cmd=(-n new "$NEW -c \"$sql\" $TABLES")
        if [ $((round % 2)) -eq 1 ]; then order=("${old_cmd[@]}" "${new_cmd[@]}"); else order=("${new_cmd[@]}" "${old_cmd[@]}"); fi
        hyperfine -N --style none --warmup 2 --runs "$RUNS" \
            --export-json "$OUT/${name}_round${round}.json" "${order[@]}" >/dev/null
    done

    {
        # shellcheck disable=SC2086
        for _ in 1 2 3; do echo "old $(peak_rss_kb "$OLD" -c "$sql" $TABLES)"; echo "new $(peak_rss_kb "$NEW" -c "$sql" $TABLES)"; done
    } > "$OUT/${name}_memory.txt"
done

python3 "$ROOT/ab_report.py" "$OUT"
