# sqlite-rs performance benchmarks (three-tier perf regime, sqlite-rs #111/#112)

.DEFAULT_GOAL := help

.PHONY: help fixtures bench bench-crud bench-v6 bench-skip-scan bench-compile-path bench-cli point-lookup status all

help: ## Show this help
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "  env: SQLITE_RS_REPO=<sqlite-rs checkout> (default ../../../sqlite-rs), ORACLE_SQLITE3=<pinned sqlite3>,"
	@echo "       SQLITE_RS=<binary for bench-cli>, BENCH_FIXTURES_DIR (default target/bench-fixtures)"

fixtures: ## Generate the ~1MB/~50MB bench fixtures into target/bench-fixtures/ via the sqlite-rs checkout's tools/gen_fixtures.sh --bench
	@bash -c '. ./tools/bench_env.sh && "$$SQLITE_RS_REPO/tools/gen_fixtures.sh" --bench'

bench: fixtures ## Tier 1 (engine-to-engine): criterion, sqlite-rs vs rusqlite linked to the pinned oracle (benches/engine.rs)
	@bash -c '. ./tools/bench_env.sh && cargo bench --bench engine'

bench-crud: fixtures ## Tier 1 full-CRUD scenarios: reads + INSERT/UPDATE/DELETE vs oracle (benches/crud.rs)
	@bash -c '. ./tools/bench_env.sh && cargo bench --bench crud'

bench-v6: fixtures ## WAL journal-vs-WAL, concurrent read/write, checkpoint, CTE reuse (benches/v6.rs)
	@bash -c '. ./tools/bench_env.sh && cargo bench --bench v6'

bench-skip-scan: ## Skip-scan vs full scan at a low-cardinality leading index column (benches/skip_scan.rs, own fixture)
	@bash -c '. ./tools/bench_env.sh && cargo bench --bench skip_scan'

bench-compile-path: ## Tier 2 compile path (tokenize/parse/expand/codegen), sqlite-rs vs itself across revisions (no fixture or oracle)
	cargo bench --bench compile_path

bench-cli: fixtures ## Tier 2 (CLI-to-CLI): hyperfine, sqlite-rs dump/query vs sqlite3 (tools/bench_cli.sh)
	./tools/bench_cli.sh

point-lookup: ## Quick wall-clock demos: rowid seek vs scan, indexed vs unindexed JOIN lookup (tests/point_lookup.rs)
	@bash -c '. ./tools/bench_env.sh && cargo test --test point_lookup_perf -- --nocapture'

status: ## Assemble results/bench-status.json from the latest bench / bench-cli raw output
	python3 report.py

all: bench bench-cli status ## Tier 1 + tier 2, then refresh results/bench-status.json
