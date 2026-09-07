# sqlite-rs oracle parity suite

.DEFAULT_GOAL := help

.PHONY: help test run

help: ## Show this help
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

test: ## Run every value block against the sqlite-rs binary and the pinned sqlite3 (SQLITE_RS=<bin>, SQLITE_RS_REPO=<checkout>, ORACLE_SQLITE3=<sqlite3>)
	cargo test --test parity

run: ## Same as test, with per-case output
	cargo test --test parity -- --nocapture
