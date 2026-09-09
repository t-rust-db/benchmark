# trigrep vs ripgrep (vs tgrep) parity benchmark

Benchmark for [trigrep](https://github.com/t-rust-db/trigrep) (`tg`): a
serverless, per-root cached alternative to
[microsoft/tgrep](https://github.com/microsoft/tgrep)'s trigram-indexed
grep. Runs every pattern in `queries/*.txt` against trigrep and
[ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) — always a cold full
scan, the baseline an index is supposed to beat — and, if a `tgrep` binary
is resolved, against tgrep's own server too.

Unlike this repo's other parity benchmark (`../column-rs`, which targets
parity *with* DuckDB), the bar here is the opposite: trigrep exists to be
**faster** than ripgrep's always-cold scan on the queries a trigram index
can narrow, using an index ripgrep doesn't have. Two queries
(`short_class`, `case_insensitive`) have no extractable required trigram or
force a full scan by design — they are expected to land near 1x, not fail.

## Usage

```bash
# 1. Generate the synthetic corpus (code-shaped text, no real repo to pin)
./data/generate.sh              # small + medium + large
./data/generate.sh small        # just one size

# 2. Point at binaries (see "Which binaries?" below), then run
./run.sh                        # medium (5,000 files)
./run.sh large                  # 50,000 files
./run.sh medium rare_literal    # one query only
```

Results land in `results/<size>_<timestamp>/` as hyperfine JSON, peak-RSS
readings, and cold-build timings; `report.py` renders the comparison table
and also writes it to `results/<run>/report.md`.

## Which binaries?

This repo does not build trigrep, ripgrep or tgrep for you.

- **trigrep** — `$TG` → `tg` on `$PATH` → `../../../trigrep/target/release/tg`
  (the standard layout, this repo checked out as a sibling of `trigrep`
  under `t-rust-db/`). Build it: `cd ../../../trigrep && cargo build --release`.
- **ripgrep** — `$RG` → `rg` on `$PATH`. Required (the baseline); install
  via your package manager or `cargo install ripgrep`.
- **tgrep** — `$TGREP` → `tgrep` on `$PATH` → skipped entirely if neither
  resolves. microsoft/tgrep is not published to crates.io: build it with
  `cargo install --git https://github.com/microsoft/tgrep tgrep-cli --locked`,
  or point `$TGREP` at an existing binary.

## The queries

| Query | Selectivity | What it measures |
|---|---|---|
| `common_literal` | ~100% of files | No benefit by design: an index narrows nothing when the term is everywhere |
| `short_class` | n/a | No 3-byte literal to extract — same floor, different cause |
| `rare_literal` | ~1% of files | The case an index exists for |
| `alternation` | ~1% of files, two branches | No benefit by design: alternations extract zero required trigrams (verified) |
| `case_insensitive` | ~1% of files | Case-insensitive search forces a full scan even with an index built |

## Requirements

- `ripgrep` (`rg`) and `hyperfine` on `PATH`
- `python3` (standard library only, for `report.py`)
- `tgrep` optional — its columns are omitted from the report if absent

## Layout

```
trigrep/
├── run.sh              # benchmark runner
├── report.py           # renders the comparison table
├── data/
│   └── generate.sh     # generates the synthetic corpus (not committed)
└── queries/
    └── *.txt           # one grep pattern per file, run against every engine
```
