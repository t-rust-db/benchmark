# trigrep parity benchmark

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

data: ## Generate small+medium+large synthetic corpora
	./data/generate.sh

# === Test ===

test: ## Smoke-run one query at small size (200 files, no warmup, 1 run). Set TG=<path> to pick a binary
	WARMUP=0 MIN_RUNS=1 ./run.sh small rare_literal

# === Run ===

run: ## Run the parity benchmark at medium size (5,000 files). Set TG/RG/TGREP=<path> to pick binaries
	./run.sh medium

run-large: ## Run the parity benchmark at large size (50,000 files)
	./run.sh large
