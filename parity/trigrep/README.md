# trigrep vs ripgrep (vs tgrep) parity benchmark

Benchmark for [trigrep](https://github.com/t-rust-db/trigrep) (`tg`): a
serverless, per-root cached alternative to
[microsoft/tgrep](https://github.com/microsoft/tgrep)'s trigram-indexed
grep. Runs every pattern in `queries/*.txt` against trigrep and
[ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) — always a cold full
scan, the baseline an index is supposed to beat — and, if a `tgrep` binary
is resolved, against tgrep's own server too.

Searches a **real** directory tree, not synthetic data: by default
`../../../sqlite-rs` — a real, single git work tree (161 `.rs` files as of
2026-09-09), so trigrep's git integration correctly respects its
`.gitignore`. The raw `t-rust-db` org checkout is *not* one git repo itself,
so a first attempt defaulting to it walked every sibling crate's `target/`
directory and never finished — found by trying it, not assumed. Point this
at anything else, including the whole org if you exclude `target/` some
other way, with `$CORPUS_ROOT`.

Unlike this repo's other parity benchmark (`../column-rs`, which targets
parity *with* DuckDB), the bar here is the opposite: trigrep exists to be
**faster** than ripgrep's always-cold scan on the queries a trigram index
can narrow, using an index ripgrep doesn't have. Two queries
(`short_class`, `case_insensitive`) have no extractable required trigram or
force a full scan by design, and `alternation` extracts zero required
trigrams across a top-level `|` by design too — all three are expected to
land near 1x, not fail.

## Usage

```bash
./run.sh                        # every query against the default corpus
./run.sh rare_literal            # one query only
CORPUS_ROOT=/some/other/tree ./run.sh   # search something else
```

Results land in `results/<timestamp>/` as hyperfine JSON, peak-RSS
readings, and cold-build timings; `report.py` renders the comparison table
and also writes it to `results/<run>/report.md`.

## Which binaries and corpus?

This repo does not build trigrep, ripgrep or tgrep, and does not generate
the corpus.

- **corpus** — `$CORPUS_ROOT` → `../../../sqlite-rs` (a real sibling repo,
  the standard layout when this repo is a sibling of `trigrep` etc. under
  `t-rust-db/`).
- **trigrep** — `$TG` → `tg` on `$PATH` → `../../../trigrep/target/release/tg`.
  Build it: `cd ../../../trigrep && cargo build --release`.
- **ripgrep** — `$RG` → `rg` on `$PATH`. Required (the baseline); install
  via your package manager or `cargo install ripgrep`.
- **tgrep** — `$TGREP` → `tgrep` on `$PATH` → skipped entirely if neither
  resolves. microsoft/tgrep is not published to crates.io: build it with
  `cargo install --git https://github.com/microsoft/tgrep tgrep-cli --locked`,
  or point `$TGREP` at an existing binary.

## The queries

Patterns are verified, real literals from the trigrep source itself (see
each `queries/*.txt` for the exact `grep -rl` command used to check them) —
re-verify if the tree has moved on and a "rare" literal has stopped being
unique; the query still runs, it just stops demonstrating a single-file
narrow.

| Query | Selectivity | What it measures |
|---|---|---|
| `common_literal` | most `.rs` files | No benefit by design: an index narrows nothing when the term is everywhere |
| `short_class` | n/a | No 3-byte literal to extract — same floor, different cause |
| `rare_literal` | 1 file in sqlite-rs (verified) | The case an index exists for |
| `alternation` | 2 files in sqlite-rs, two branches | No benefit by design: alternations extract zero required trigrams (verified) |
| `case_insensitive` | 1 file (verified) | Case-insensitive search forces a full scan even with an index built |

## Requirements

- `ripgrep` (`rg`) and `hyperfine` on `PATH`
- `python3` (standard library only, for `report.py`)
- `tgrep` optional — its columns are omitted from the report if absent

## Layout

```
trigrep/
├── run.sh              # benchmark runner
├── report.py           # renders the comparison table
└── queries/
    └── *.txt           # one grep pattern per file, run against every engine
```
