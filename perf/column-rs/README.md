# column-rs performance

Performance tracking for [column-rs](https://github.com/t-rust-db/tools/tree/main/column-rs)
across builds and releases (benchmark#23). Companion of
`../../parity/column-rs`, which compares column-rs with DuckDB at one moment;
this package compares column-rs with itself. Both use the parity queries and
data, so generate the data once with `../../parity/column-rs/data/generate.sh`.

| target | what |
|---|---|
| `make ab OLD=<binary> NEW=<binary>` | two column-rs builds over the parity queries: median time and peak RSS per query, and the change |
| `make status` | runs the parity suite with `COLUMN_RS` and records it in `results/bench-status.json` under its column-rs version |

## A/B two builds

```bash
make ab OLD=/path/to/old/column-rs NEW=../../../tools/target/release/column-rs
make ab OLD=... NEW=... SIZE=medium ONLY=join   # one query, smaller data
```

Each query runs in `ROUNDS` rounds (default 3) of `RUNS` timed runs (default
10) per build, and the order of the two builds swaps every round, so a busy
stretch on the machine lands on both sides. A single back-to-back comparison
once showed a 1.5x "slowdown" that was noise. Time is the median of every
run across the rounds; peak RSS is the median of three runs per build. The
two builds must emit the same number of lines for a query, or the run stops.
Output goes to `results/ab_<size>_<timestamp>/report.md` (gitignored).

To A/B a db-core change, build column-rs against the local db-core into a
separate target directory and compare it with the released binary:

```bash
cd ../../../tools && CARGO_TARGET_DIR=/tmp/column-rs-new cargo build --release -p column-rs \
    --config 'patch."https://github.com/t-rust-db/db-core".db-core.path="../db-core"'
```

The patch only applies when tools' db-core pin has the same version as the
local db-core checkout.

## Per-release status

```bash
make status                                  # COLUMN_RS defaults to ../../../tools/target/release/column-rs
```

`results/bench-status.json` keeps one entry per column-rs version: its db-core
version (read from the tools checkout's `Cargo.lock`), the date, the parity
run it came from, the binary size, the hardware, and per query the median
time and peak RSS of column-rs and DuckDB and their ratio. Re-running a
version replaces its entry. Run it after each column-rs release and commit
the file; the numbers only compare across entries from the same hardware.
