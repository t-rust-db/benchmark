# column-rs vs DuckDB parity benchmark

DuckDB parity benchmark for [column-rs](https://github.com/t-rust-db/tools/tree/main/column-rs),
ported out of column-rs's own `benches/` (originally
[iheitlager/column-rs#100](https://github.com/iheitlager/column-rs)) into
this repo so parity testing lives alongside every other t-rust-db product's
benchmarks, decoupled from any one product's own release cycle and test
suite.

Runs every query in `queries/*.sql` against both column-rs and DuckDB with
the *identical* SQL text — neither engine is handed a rewritten query.

## Usage

```bash
# 1. Generate benchmark data (needs duckdb on PATH)
./data/generate.sh              # small + medium + large
./data/generate.sh small        # just one size

# 2. Point at a column-rs binary (see "Which column-rs binary?" below),
#    then run
./run.sh                        # medium (100K rows)
./run.sh large                  # 10M rows
./run.sh medium scan            # one query only
```

Results land in `results/<size>_<timestamp>/` as hyperfine JSON plus a
peak-RSS reading per engine (the median of three runs); `report.py`
renders the comparison table, using each query's median time, and also
writes it to `results/<run>/report.md`.

`join` groups on the 3 customer tiers; `join_many_groups` runs the same
join grouped by customer, 100K groups at `large`, where merging the
per-row-group partial aggregates dominates (db-core#863).

## List queries

`bench` carries two `VARCHAR[]` columns of 0-4 elements per row (every
tenth row NULL): `tags` over 8 distinct values and `labels` over 1,000.
`list_not_null_{low,mid}` test a list for NULL without taking it apart,
and `unnest_group_by_{low,mid}` unnest it and group on the element
(db-core#802, #809). They need column-rs 0.33.0 or later (tools#80) and
data generated after they were added: regenerate with `./data/generate.sh`
if `bench` has no `tags` column.

## Which column-rs binary?

This repo does not build column-rs itself — it's a separate product with
its own release cycle. `run.sh` resolves the binary in this order:

1. **`$COLUMN_RS`** — explicit path to a column-rs binary, if set
2. **`column-rs` on `$PATH`** — a globally installed/linked build
3. **`../../../tools/target/release/column-rs`** — i.e.
   the `t-rust-db/tools` workspace built in place, the normal case when
   this benchmark repo is checked out as a sibling of `tools` under
   `t-rust-db/` (the standard layout)

The fallback does not build column-rs for you:

```bash
cd ../../../tools && cargo build --release -p column-rs
```

## Requirements

- `duckdb` and `hyperfine` on `PATH`
- `python3` (standard library only, for `report.py`)

## Layout

```
column-rs/
├── run.sh              # benchmark runner
├── report.py           # renders the comparison table
├── data/
│   └── generate.sh     # generates the Parquet fixtures (not committed)
└── queries/
    └── *.sql           # one query shape per file, run against both engines
```
