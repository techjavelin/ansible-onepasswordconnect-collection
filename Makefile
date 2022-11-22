export MAIN_BRANCH ?= main

.DEFAULT_GOAL := help
.PHONY: test test/unit test/integration build clean release/prepare release/tag .check_bump_type .check_git_clean help

GIT_BRANCH := $(shell git symbolic-ref --short HEAD)
WORKTREE_CLEAN := $(shell git status --porcelain 1>/dev/null 2>&1; echo $$?)
SCRIPTS_DIR := $(CURDIR)/scripts

ENV ?= opconnect_collection
OP_VAULT_ID ?= $(shell op vault get $(OP_CONNECT_VAULT_NAME)  --format json | jq -r .id)

curVersion := $$(sed -n -E 's/^version: "([0-9]+\.[0-9]+\.[0-9]+)"$$/\1/p' galaxy.yml)

test/unit:	## Run unit tests in a Docker container
	$(SCRIPTS_DIR)/run-tests.sh units

test/integration:	## Run integration tests inside a Docker container
	$(SCRIPTS_DIR)/run-tests.sh integration

test/sanity:	## Run ansible sanity tests in a Docker container
	$(SCRIPTS_DIR)/run-tests.sh sanity

build: clean	## Build collection artifact
	ansible-galaxy collection build --output-path dist/

clean:	## Removes dist/ directory
	@rm -rf ./dist

help:	## Prints this help message
	@grep -E '^[\/a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

## Release functions =====================

release/prepare: .check_git_clean	## Bumps version and creates release branch (call with 'release/prepare version=<new_version_number>')

	@test $(version) || (echo "[ERROR] version argument not set."; exit 1)
	@git fetch --quiet origin $(MAIN_BRANCH)

	@sed -i.tmp -E 's/^(version:) ([0-9]+\.[0-9]+\.[0-9]+)$$/\1 "$(version)"/' galaxy.yml
	@sed -i.tmp -E 's/^(COLLECTION_VERSION) = "(.+)"$$/\1 = "$(version)"/' plugins/module_utils/const.py

	@NEW_VERSION=$(version) $(SCRIPTS_DIR)/prepare-release.sh
	@rm -f galaxy.yml.tmp plugins/module_utils/const.py.tmp


release/tag: .check_git_clean	## Creates git tag using version from package.json
	@git pull --ff-only
	@echo "Applying tag 'v$(curVersion)' to HEAD..."
	@git tag --sign "v$(curVersion)" -m "Release v$(curVersion)"
	@echo "[OK] Success!"
	@echo "Remember to call 'git push --tags' to persist the tag."

test/docker: 
	@echo "Create a session token for op cli"
	@op signin --raw > .op_session
	@echo "Creating OP Connect Server"
	@echo "Using Environment $(ENV) and Vault $(OP_VAULT_ID)"
	@op connect server create $(ENV) --vaults $(OP_VAULT_ID) --session "$(cat .op_session)"
	@chmod 777 1password-credentials.json
	@echo "Creating OP Connect Token for ansible"
	@op connect token create ansible --server $(ENV) --vault $(OP_VAULT_ID) --session "$(cat .op_session)" > .op_connect_token_ansible 
	@echo "Creating OP Connect Containers"
	@docker-compose up --no-start
	@echo "Starting OP Connect Server"
	@docker-compose start
	@OP_CONNECT_HOST="http://op-connect-api:8080" OP_CONNECT_TOKEN="$(cat .op_connect_token_ansible)" OP_VAULT_ID=$(OP_VAULT_ID) OP_VAULT_NAME=$(OP_CONNECT_VAULT_NAME) $(SCRIPTS_DIR)/run-tests.sh integration

test/teardown:
	@echo "Tearing Down OnePassword Connect Server"
	@docker-compose down -v --remove-orphans
	@echo "Cleaning up op cli and connect"
	@rm -rf 1password-credentials.json .op_connect_token_ansible .op_session
	@op connect server delete $(ENV)	
	@unset OP_TOKEN

## Helper functions =====================

.check_git_clean:
ifneq ($(GIT_BRANCH), $(MAIN_BRANCH))
	@echo "[ERROR] Please checkout default branch '$(MAIN_BRANCH)' and re-run this command."; exit 1;
endif
ifneq ($(WORKTREE_CLEAN), 0)
	@echo "[ERROR] Uncommitted changes found in worktree. Address them and try again."; exit 1;
endif
