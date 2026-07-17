# Doit project makefile
# Common development and deployment tasks.

.PHONY: help test deploy-prod deploy-dev verify-prod verify-dev status

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

test: ## Run all runner tests
	cd runner && source .venv/bin/activate && python3 -m pytest tests/ -v --tb=short -k "not test_mirror_memory_cli"

status: ## Show edge function deployment status for both projects
	@./scripts/verify-deploy-status.sh

verify-prod: ## Check if production agent-settings function is deployed
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

verify-dev: ## Check if dev agent-settings function is deployed
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

deploy-prod: ## Deploy agent-settings to production (needs SUPABASE_PAT)
	@echo ""
	@echo "=== Deploy agent-settings -> PRODUCTION ==="
	@echo "Project: nportxmsauhezjdubsma"
	@echo ""
	@if [ -z "$${SUPABASE_PAT}" ]; then \
		echo "ERROR: SUPABASE_PAT is not set."; \
		echo ""; \
		echo "Get a PAT from: https://supabase.com/dashboard/account/tokens"; \
		echo "Then run: SUPABASE_PAT=sbp_xxx make deploy-prod"; \
		exit 1; \
	fi
	@./scripts/deploy-prod-curl.sh

deploy-dev: ## Deploy agent-settings to dev project (needs SUPABASE_PAT)
	@echo ""
	@echo "=== Deploy agent-settings -> DEV ==="
	@echo "Project: qjeutitqgdsasccxfxdy"
	@echo ""
	@if [ -z "$${SUPABASE_PAT}" ]; then \
		echo "ERROR: SUPABASE_PAT is not set."; \
		echo ""; \
		echo "Get a PAT from: https://supabase.com/dashboard/account/tokens"; \
		echo "Then run: SUPABASE_PAT=sbp_xxx make deploy-dev"; \
		exit 1; \
	fi
	@SUPABASE_PROJECT_REF=qjeutitqgdsasccxfxdy ./scripts/deploy-prod-curl.sh
