# sqlite-rs oracle parity suite

Oracle parity suite for [sqlite-rs](https://github.com/t-rust-db/sqlite-rs),
ported out of sqlite-rs's own `tests/parity/` (t-rust-db/sqlite-rs#72 and
onwards) so full oracle parity testing lives here, alongside every other
t-rust-db product's parity and performance runs, decoupled from the
product's own test suite and release cycle. sqlite-rs keeps its fixture-diff
corpus, sqllogictest slice and tier contracts as regression gates; this is
the only place the two engines are run side by side.

One integration target per value block (`tests/parity/v01.rs` … `v12.rs`)
runs the *identical* SQL through `sqlite-rs` and a pinned real `sqlite3`
(3.53.4, sqlite-rs ADR-0005) and compares acceptance, output and schema
dimensions per case (`driver.rs`). A block whose engine surface does not
exist yet is `#[ignore]`d with the ticket that will flip it.

## Usage

```bash
# 1. Build the binary under test (any sqlite-rs checkout; release build)
(cd ../../../sqlite-rs && cargo build --release)

# 2. Run
make test          # or: cargo test --test parity
make run           # with per-case output
```

## Resolution rules

| what | order |
|---|---|
| `sqlite-rs` binary | `$SQLITE_RS` → `sqlite-rs` on `$PATH` → `$SQLITE_RS_REPO/target/release/sqlite-rs` |
| sqlite-rs checkout (fixtures, `tools/gen_fixtures.sh`) | `$SQLITE_RS_REPO` → `../../../sqlite-rs` (sibling under t-rust-db/) |
| oracle `sqlite3` | `$ORACLE_SQLITE3` → Homebrew paths → `sqlite3` on `$PATH`; must report 3.53.4 and not be a codec build, else every case is skipped, not failed |

The library-level checks (v01's dump comparison) link `sqlite-rs` as a
pinned git dev-dependency in `Cargo.toml`; bump the tag with each sqlite-rs
release.
