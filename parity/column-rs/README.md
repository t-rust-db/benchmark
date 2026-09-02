# column-rs vs DuckDB parity benchmark

DuckDB parity benchmark for [column-rs](https://github.com/t-rust-db/column-rs),
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
peak-RSS reading per engine; `report.py` renders the comparison table and
also writes it to `results/<run>/report.md`.

## Which column-rs binary?

This repo does not build column-rs itself — it's a separate product with
its own release cycle. `run.sh` resolves the binary in this order:

1. **`$COLUMN_RS`** — explicit path to a column-rs binary, if set
2. **`column-rs` on `$PATH`** — a globally installed/linked build
3. **`../../../column-rs/target/release/column-rs`** — i.e.
   `t-rust-db/column-rs` built in place, the normal case when this
   benchmark repo is checked out as a sibling of `column-rs` under
   `t-rust-db/` (the standard layout)

The fallback does not build column-rs for you:

```bash
cd ../../../column-rs && cargo build --release
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
