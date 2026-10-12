.PHONY: setup bootstrap plan apply deploy staging production check teardown-app

setup:
	./scripts/setup.sh
bootstrap:
	./scripts/bootstrap.sh
plan:
	mkdir -p .local && chmod 700 .local
	terraform -chdir=terraform/infra plan -out=../../.local/infra.tfplan
apply:
	terraform -chdir=terraform/infra apply ../../.local/infra.tfplan
deploy:
	./scripts/deploy.sh
staging:
	./scripts/deploy.sh -e wait_for_certificate=true
production:
	./scripts/deploy.sh -e acme_environment=production -e wait_for_certificate=true
check:
	./scripts/check.sh
teardown-app:
	PLAYBOOK=teardown.yml ./scripts/deploy.sh
