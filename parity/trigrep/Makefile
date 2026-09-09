# trigrep parity benchmark

.DEFAULT_GOAL := help

.PHONY: help test run

help: ## Show this help
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} \
	  /^# === .* ===$$/  { sub(/^# === /, ""); sub(/ ===$$/, ""); printf "\n\033[33m%s\033[0m\n", $$0 } \
	  /^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2 }' \
	  $(MAKEFILE_LIST)
	@echo ""

# === Test ===

test: ## Smoke-run one query, no warmup, 1 run. Set TG/CORPUS_ROOT=<path> to override
	WARMUP=0 MIN_RUNS=1 ./run.sh rare_literal

# === Run ===

run: ## Run every query against the default corpus (the t-rust-db org checkout). Set TG/RG/TGREP/CORPUS_ROOT=<path> to override
	./run.sh
