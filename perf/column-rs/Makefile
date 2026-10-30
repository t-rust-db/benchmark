# column-rs performance: A/B of two builds, per-release status (benchmark#23)

.DEFAULT_GOAL := help

SIZE ?= large
TOOLS_REPO ?= ../../../tools
COLUMN_RS ?= $(TOOLS_REPO)/target/release/column-rs

.PHONY: help ab status

help: ## Show this help
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "  env: SIZE=small|medium|large (default large), ONLY=<query>, ROUNDS (default 3), RUNS (default 10),"
	@echo "       COLUMN_RS=<binary for status> (default $(TOOLS_REPO)/target/release/column-rs), TOOLS_REPO"

ab: ## Two column-rs builds over the parity queries, alternating rounds: OLD=<binary> NEW=<binary>
	@test -n "$(OLD)" -a -n "$(NEW)" || { echo "usage: make ab OLD=<column-rs binary> NEW=<column-rs binary>" >&2; exit 2; }
	@./ab.sh "$(OLD)" "$(NEW)" "$(SIZE)" "$(ONLY)"

status: ## Run the parity suite with COLUMN_RS and record it in results/bench-status.json under its version
	@# Exit 3 is a complete run with a query over the parity bar: still recorded.
	cd ../../parity/column-rs && COLUMN_RS="$(abspath $(COLUMN_RS))" ./run.sh $(SIZE); rc=$$?; test $$rc -eq 0 -o $$rc -eq 3
	python3 status.py --binary "$(abspath $(COLUMN_RS))" --size $(SIZE) --tools-repo "$(abspath $(TOOLS_REPO))"
