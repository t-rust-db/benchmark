# column-rs performance

Performance tracking for [column-rs](https://github.com/t-rust-db/tools/tree/main/column-rs)
across builds and releases (benchmark#23). Companion of
`../../parity/column-rs`, whose queries and data it uses: missing data for
the chosen size is generated first.

| target | what |
|---|---|
| `make ab` | two engines over the parity queries: median time and peak RSS per query, and b's change from a. DuckDB vs column-rs by default; `A=`/`B=` compare two column-rs builds |
| `make status` | runs the parity suite with column-rs and records it in `results/bench-status.json` under its version and size |

Both find column-rs through `../../lib/tool.sh` (vendored from
t-rust-db/examples): `$COLUMN_RS` as given, else built with `cargo build
--release -p column-rs` in the tools checkout next to this repo (it reports
the branch and commit), else `column-rs` on `PATH`. They need `duckdb`
(v1.5.5, which generates the data too) and `hyperfine`.

## A/B

```bash
make ab                                         # DuckDB vs column-rs, large, every query
make ab SIZE=medium ONLY=join                   # one query, smaller data
make ab A=/path/to/old/column-rs B=/path/to/new/column-rs   # two builds
```

Each query runs in `ROUNDS` rounds (default 3) of `RUNS` timed runs (default
10) per side, and the order of the two sides swaps every round, so a busy
stretch on the machine lands on both. A single back-to-back comparison once
showed a 1.5x "slowdown" that was noise. Time is the median of every run
across the rounds; peak RSS is the median of three runs per side. The two
sides must emit the same number of rows for a query, or the run stops.
Output goes to `results/ab_<size>_<timestamp>/report.md` (gitignored).

To A/B a db-core change, build column-rs against the local db-core into a
separate target directory and compare it with the released binary:

```bash
cd ../../../tools && CARGO_TARGET_DIR=/tmp/column-rs-new cargo build --release -p column-rs \
    --config 'patch."https://github.com/t-rust-db/db-core".db-core.path="../db-core"'
cd - && make ab A=../../../tools/target/release/column-rs B=/tmp/column-rs-new/release/column-rs
```

The patch only applies when tools' db-core pin has the same version as the
local db-core checkout.

## Per-release status

```bash
make status                                  # SIZE=large by default
```

`results/bench-status.json` keeps one entry per column-rs version and size: its db-core
version (read from the tools checkout's `Cargo.lock`), the date, the parity
run it came from, the binary size, the hardware, and per query the median
time and peak RSS of column-rs and DuckDB and their ratio. Re-running a
version at a size replaces its entry. Run it after each column-rs release and commit
the file; the numbers only compare across entries from the same hardware.
