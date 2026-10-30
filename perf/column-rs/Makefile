# column-rs performance: A/B of two engines or builds, per-release status (benchmark#23)

.DEFAULT_GOAL := help

SIZE ?= large
TOOLS_REPO ?= ../../../tools
PARITY := ../../parity/column-rs

.PHONY: help ab status

help: ## Show this help
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "  env: A=duckdb|<column-rs binary> (default duckdb), B=<column-rs binary> (default: found by lib/tool.sh),"
	@echo "       COLUMN_RS=<binary> (else built in $(TOOLS_REPO)), SIZE=small|medium|large (default large),"
	@echo "       ONLY=<query>, ROUNDS (default 3), RUNS (default 10)"

ab: ## A/B over the parity queries in alternating rounds: DuckDB vs column-rs by default; A=/B= for two builds
	@./ab.sh "$(A)" "$(B)" "$(SIZE)" "$(ONLY)"

status: ## Run the parity suite with column-rs and record it in results/bench-status.json under its version
	@test -f $(PARITY)/data/$(SIZE).parquet || $(PARITY)/data/generate.sh $(SIZE)
	@# Exit 3 is a complete run with a query over the parity bar: still recorded.
	@bin="$$(. ../../lib/tool.sh && find_tool column-rs column-rs COLUMN_RS)" || exit 1; \
	(cd $(PARITY) && COLUMN_RS="$$bin" ./run.sh $(SIZE)); rc=$$?; \
	test $$rc -eq 0 -o $$rc -eq 3 || exit $$rc; \
	python3 status.py --binary "$$bin" --size $(SIZE) --tools-repo "$(abspath $(TOOLS_REPO))"
