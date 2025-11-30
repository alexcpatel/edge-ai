.PHONY: help
.DEFAULT_GOAL := help

include makefiles/firmware.mk

help: ## Show this help message
	@echo "Available targets:"
	@grep -hE '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-30s %s\n", $$1, $$2}'
