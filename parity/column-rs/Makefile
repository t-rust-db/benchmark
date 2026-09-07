# column-rs parity benchmark

.DEFAULT_GOAL := help

.PHONY: help data test run run-large

help: ## Show this help
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} \
	  /^# === .* ===$$/  { sub(/^# === /, ""); sub(/ ===$$/, ""); printf "\n\033[33m%s\033[0m\n", $$0 } \
	  /^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2 }' \
	  $(MAKEFILE_LIST)
	@echo ""

# === Data ===

data: ## Generate small+medium+large benchmark datasets (requires duckdb on PATH)
	./data/generate.sh

# === Test ===

test: ## Smoke-run one parity query at small size (1K rows, no warmup, 1 run). Set COLUMN_RS=<path> to pick a binary
	WARMUP=0 MIN_RUNS=1 ./run.sh small scan

# === Run ===

run: ## Run the parity benchmark at medium size (100K rows). Set COLUMN_RS=<path> to pick a binary
	./run.sh medium

run-large: ## Run the parity benchmark at large size (10M rows). Set COLUMN_RS=<path> to pick a binary
	./run.sh large
