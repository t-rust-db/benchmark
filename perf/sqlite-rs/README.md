# sqlite-rs performance benchmarks

Performance benchmarks for [sqlite-rs](https://github.com/t-rust-db/sqlite-rs),
ported out of its `tests/performance/` and `tools/bench_*`
(t-rust-db/sqlite-rs#22) so performance work lives here, alongside every other
t-rust-db product's parity and performance runs, decoupled from the product's
own test suite and release cycle. Companion of `../../parity/sqlite-rs`
(oracle *correctness* parity); this package measures *speed*.

Three tiers (sqlite-rs #111/#112):

| tier | what | tool | entry |
|---|---|---|---|
| 1 | engine-to-engine: sqlite-rs vs libsqlite3 via rusqlite, in-process, prepared statements reused | criterion | `make bench`, `make bench-crud`, `make bench-v6`, `make bench-skip-scan` |
| 2 | compile path only: tokenize/parse/expand/codegen, sqlite-rs vs itself across revisions | criterion | `make bench-compile-path` |
| 2 | CLI-to-CLI: `sqlite-rs dump/query` vs `sqlite3`, process startup included | hyperfine | `make bench-cli` |

`make point-lookup` is a quick wall-clock demo (rowid seek vs scan, indexed vs
unindexed JOIN). `make status` folds the latest raw output into
`results/bench-status.json` (ratios, not samples — the committed snapshot).

## Usage

```bash
make bench          # tier 1, generates target/bench-fixtures/ on first run
make bench-cli      # tier 2 CLI (needs hyperfine)
make status         # refresh results/bench-status.json
```

## Resolution rules

| what | order |
|---|---|
| sqlite-rs checkout (`tools/gen_fixtures.sh --bench`, the pinned-oracle version in `[package.metadata.oracle]`, the committed corpus fixture `engine.rs` reuses) | `$SQLITE_RS_REPO` → `../../../sqlite-rs` (sibling under t-rust-db/) |
| pinned `sqlite3` (must report the pinned version, non-codec) | `$ORACLE_SQLITE3` → Homebrew keg paths; `tools/bench_env.sh` also exports `SQLITE3_LIB_DIR`/`SQLITE3_INCLUDE_DIR` so rusqlite links that keg, never a vendored SQLite, and `benches/engine.rs` asserts the linked version at run time |
| `sqlite-rs` binary (tier 2 CLI) | `$SQLITE_RS` → `sqlite-rs` on `$PATH` → `$SQLITE_RS_REPO/target/release/sqlite-rs` (built there if missing) |
| fixtures | `$BENCH_FIXTURES_DIR` (default `target/bench-fixtures/`, gitignored) |

The tier-1 benches link the crate under test as a pinned git dev-dependency in
`Cargo.toml`; bump the tag with each sqlite-rs release.

## Results

Latest snapshot: `results/bench-status.json` (`oracle_version`, `hardware`,
`tier1_engine`, `tier2_cli`). The narrative below carries over from sqlite-rs's
`docs/performance.md` as of 0.18.x, 1MB fixture (16,700 rows), Apple M4 Pro.

### V7.3

| Query | sqlite-rs | Oracle | Ratio | Status |
|-------|----------:|-------:|------:|--------|
| point_lookup | 295 ns | 2.88 µs | **0.10×** | 10× faster than C |
| filter_scan | 1.97 ms | 2.71 ms | **0.73×** | beats oracle |
| full_scan | 2.33 ms | 2.80 ms | **0.83×** | beats oracle |
| order_by_limit | 29.3 µs | 30.0 µs | **0.98×** | parity |
| join | 3.95 ms | 2.12 ms | 1.86× | within 2× |
| group_by_agg | 7.84 ms | 1.55 ms | 5.1× | within 5× |
| correlated_subquery | 4.96 ms | 2.60 ms | **1.91×** | within 2× |

5 of 7 queries beat or match the sqlite3 oracle.

### Progression (V4 → V7.3)

| Query | V4 | V5 | V6 | V7.2 | V7.3 |
|-------|---:|---:|---:|-----:|-----:|
| point_lookup | — | 0.42× | 0.40× | 0.12× | **0.10×** |
| filter_scan | — | 2.4× | — | 0.79× | **0.73×** |
| full_scan | 3.6× | 3.4× | 3.6× | 0.87× | **0.83×** |
| order_by_limit | — | — | — | 1.01× | **0.98×** |
| join | 15.6× | 11.1× | — | 2.09× | **1.86×** |
| group_by_agg | 23.0× | 26.2× | — | 6.7× | **5.1×** |
| correlated_subquery | — | — | 785× | 2.23× | **1.91×** |

### Key optimizations

| Version | Optimization | Impact |
|---------|--------------|--------|
| V5 | Transactions (BEGIN/COMMIT) | 24× write improvement |
| V6 | WAL mode | Concurrent readers |
| V7.1 | Lazy payload reassembly | full_scan 3.6× → 1.3× |
| V7.2 | Join ordering + Bloom filter | join 11× → 2× |
| V7.2 | Correlated subquery cache | 785× → 2× |
| V7.3 | Record encode scratch buffer | 25% improvement across writes |

## Fixture

`tools/gen_fixtures.sh --bench` (in the sqlite-rs checkout) writes `bench_1mb.db`
(16,700 rows) and `bench_50mb.db` (830,000 rows): `bench_data` indexed on `x`,
`bench_lookup` (1,000 rows), ANALYZE statistics present.
