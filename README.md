# benchmark
all performance benchmarks

## Layout

| dir | what |
|---|---|
| `parity/column-rs` | column-rs vs DuckDB performance parity |
| `parity/trigrep` | trigrep vs ripgrep (vs optional tgrep) grep-with-an-index parity |
| `parity/sqlite-rs` | sqlite-rs vs pinned sqlite3 oracle parity suite (the only home of full oracle parity testing for sqlite-rs) |
| `perf/column-rs` | `make ab`: DuckDB vs column-rs, or two column-rs builds, in alternating rounds; `make status`: per-release snapshot in `results/bench-status.json` |
| `lib/tool.sh` | finds or builds a t-rust-db tool binary (vendored from t-rust-db/examples) |
| `perf/sqlite-rs` | sqlite-rs performance benchmarks: tier 1 criterion vs libsqlite3, tier 2 hyperfine CLI vs sqlite3, `results/bench-status.json` snapshot |
