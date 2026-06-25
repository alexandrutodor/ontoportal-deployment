SHELL := /usr/bin/env bash

PROFILE ?= ontoportal-clean
NAMESPACE ?= ontoportal
RELEASE ?= ontoportal
COMPOSE_PROFILE ?= $(PROFILE)

.PHONY: validate validate-generated validate-shell validate-ui-tests validate-yaml validate-environments check-gates watch-gates compose-config production-check terraform-validate compose compose-all deploy smoke smoke-deep ui-test keda-check vpa-check render environment image-build-matrix clean-generated

validate:
	python3 scripts/lint-values.py
	python3 scripts/validate-yaml.py
	python3 scripts/validate-examples.py
	python3 scripts/validate-environments.py
	$(MAKE) validate-shell

validate-shell:
	bash -n scripts/*.sh scripts/addons/*.sh

validate-generated:
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	cp -a compose/generated "$$tmp/generated"; \
	$(MAKE) compose-all; \
	diff -ru "$$tmp/generated" compose/generated

validate-ui-tests:
	command -v node >/dev/null
	node --check playwright.config.mjs
	find tests/ui -name '*.mjs' -print0 | xargs -0 -n1 node --check

validate-yaml:
	python3 scripts/validate-yaml.py

validate-environments:
	python3 scripts/validate-environments.py

check-gates:
	python3 scripts/gate-check.py --gate-file docs/deployment-gates.tsv

watch-gates:
	python3 scripts/gate-check.py --gate-file docs/deployment-gates.tsv --watch --interval $${VALIDATION_INTERVAL:-300} --status-file $${VALIDATION_STATUS_FILE:-/tmp/ontoportal-validation-status.md}

compose-config: compose-all
	command -v docker >/dev/null
	for profile in ontoportal-clean agroportal-clean matportal; do \
		docker compose --env-file compose/generated/.env.$$profile.sample -f compose/generated/docker-compose.$$profile.yml config >/tmp/compose-$$profile.yml; \
	done

production-check:
	python3 scripts/production-readiness-check.py -f values/profiles/$(PROFILE).yaml -f values/profiles/production-recommended.yaml $${EXTRA_VALUES_ARGS:-}

terraform-validate:
	command -v terraform >/dev/null
	terraform -chdir=terraform fmt -check -recursive
	terraform -chdir=terraform init -backend=false -lockfile=readonly
	terraform -chdir=terraform validate

compose:
	python3 scripts/render-compose.py -f values/profiles/$(COMPOSE_PROFILE).yaml -f values/profiles/docker-compose.yaml

compose-all:
	python3 scripts/render-compose.py -f values/profiles/ontoportal-clean.yaml -f values/profiles/docker-compose.yaml
	python3 scripts/render-compose.py -f values/profiles/agroportal-clean.yaml -f values/profiles/docker-compose.yaml
	python3 scripts/render-compose.py -f values/profiles/matportal.yaml -f values/profiles/docker-compose.yaml

deploy:
	scripts/deploy.sh $(PROFILE) $(NAMESPACE) $(RELEASE)

smoke:
	scripts/smoke.sh $(NAMESPACE) $(RELEASE)

smoke-deep:
	SMOKE_DEEP=true FAIL_ON_RESTARTS=true scripts/smoke.sh $(NAMESPACE) $(RELEASE)

ui-test:
	scripts/ui-e2e.sh $(NAMESPACE) $(RELEASE)

keda-check:
	scripts/keda-check.sh $(NAMESPACE) $(RELEASE)

vpa-check:
	scripts/vpa-check.sh $(NAMESPACE) $(RELEASE)

render:
	helm template $(RELEASE) chart/ontoportal --namespace $(NAMESPACE) -f values/profiles/$(PROFILE).yaml $${HELM_EXTRA_ARGS:-}

environment:
	python3 scripts/render-environment.py environments/$(ENV).yaml $${ENV_RENDER_ARGS:-}

image-build-matrix:
	python3 scripts/image-build-matrix.py $${IMAGE_BUILD_ARGS:-}

clean-generated:
	rm -f compose/generated/docker-compose.*.yml compose/generated/.env.*.sample
