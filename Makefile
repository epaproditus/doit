# Doit project makefile
# Common development and deployment tasks.

.PHONY: help test test-model deploy-prod deploy-dev verify-prod verify-dev

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

test: test-model ## Run all tests

test-model: ## Run connector model apply tests
	python3 -m pytest runner/tests/test_connector_model_apply.py -v

deploy-prod: ## Deploy agent-settings Edge Function to production
	@echo ""
	@echo "=== Deploy agent-settings -> PRODUCTION ==="
	@echo "Project: nportxmsauhezjdubsma"
	@echo ""
	@echo "Prerequisites: SUPABASE_PAT with Management API access to the prod org"
	@echo ""
	@if [ -z "$${SUPABASE_PAT}" ]; then \
		echo "ERROR: SUPABASE_PAT is not set."; \
		echo ""; \
		echo "Get a PAT from: https://supabase.com/dashboard/account/tokens"; \
		echo "Then run: SUPABASE_PAT=sbp_xxx make deploy-prod"; \
		exit 1; \
	fi
	@./scripts/deploy-prod-curl.sh

deploy-dev: ## Deploy agent-settings Edge Function to dev project
	@echo ""
	@echo "=== Deploy agent-settings -> DEV ==="
	@echo "Project: qjeutitqgdsasccxfxdy"
	@echo ""
	@echo "Prerequisites: SUPABASE_PAT with Management API access"
	@echo ""
	@if [ -z "$${SUPABASE_PAT}" ]; then \
		echo "ERROR: SUPABASE_PAT is not set."; \
		echo ""; \
		echo "Get a PAT from: https://supabase.com/dashboard/account/tokens"; \
		echo "Then run: SUPABASE_PAT=sbp_xxx make deploy-dev"; \
		exit 1; \
	fi
	@SUPABASE_PROJECT_REF=qjeutitqgdsasccxfxdy ./scripts/deploy-prod-curl.sh

verify-prod: ## Check if production function is deployed
	@echo "=== Check production agent-settings ==="
	@STATUS=$$(curl -s -o /dev/null -w "%{http_code}" \
		-X POST "https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings" \
		-H "Content-Type: application/json" \
		-d '{"action":"get"}'); \
	if [ "$$STATUS" = "401" ]; then \
		echo "  LIVE (HTTP 401 - JWT verification active)"; \
	elif [ "$$STATUS" = "200" ]; then \
		echo "  LIVE (HTTP 200)"; \
	elif [ "$$STATUS" = "404" ]; then \
		echo "  NOT DEPLOYED (HTTP 404)"; \
		echo ""; \
		echo "  To deploy: SUPABASE_PAT=sbp_xxx make deploy-prod"; \
	else \
		echo "  Unexpected status: HTTP $$STATUS"; \
	fi

verify-dev: ## Check if dev function is deployed
	@echo "=== Check dev agent-settings ==="
	@STATUS=$$(curl -s -o /dev/null -w "%{http_code}" \
		-X POST "https://qjeutitqgdsasccxfxdy.supabase.co/functions/v1/agent-settings" \
		-H "Content-Type: application/json" \
		-d '{"action":"get"}'); \
	if [ "$$STATUS" = "401" ]; then \
		echo "  LIVE (HTTP 401 - JWT verification active)"; \
	elif [ "$$STATUS" = "200" ]; then \
		echo "  LIVE (HTTP 200)"; \
	elif [ "$$STATUS" = "404" ]; then \
		echo "  NOT DEPLOYED (HTTP 404)"; \
	else \
		echo "  Unexpected status: HTTP $$STATUS"; \
	fi
