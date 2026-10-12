#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/*.sh
if [[ -n "$(gofmt -l app/*.go)" ]]; then
  echo 'Run gofmt -w app/*.go' >&2
  exit 1
fi
(cd app && go test -race ./... && go vet ./...)
.venv/bin/python - <<'PY'
import pathlib
import jinja2
import yaml
root = pathlib.Path('.')
variables = yaml.safe_load((root / 'ansible/vars.yml').read_text())
variables.update(infra={'image_name': 'example.com/hello'}, image_digest={'stdout': 'sha256:' + 'a' * 64})
template = jinja2.Environment(undefined=jinja2.StrictUndefined).from_string(
    (root / 'ansible/templates/app.yml.j2').read_text()
)
for mode in ['staging', 'production']:
    variables['acme_environment'] = mode
    resources = list(yaml.safe_load_all(template.render(**variables)))
    assert len(resources) == 10
    certificate = next(r for r in resources if r['kind'] == 'Certificate')
    assert certificate['spec']['issuerRef']['name'] == 'letsencrypt-' + mode
    deployment = next(r for r in resources if r['kind'] == 'Deployment')
    assert deployment['spec']['template']['spec']['automountServiceAccountToken'] is False
    print(mode, 'manifest rendering passed')
PY
terraform fmt -check -recursive
terraform -chdir=terraform/bootstrap validate
terraform -chdir=terraform/infra validate
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
export ANSIBLE_COLLECTIONS_PATH="$PWD/.tools/collections"
for playbook in deploy teardown; do
  .venv/bin/ansible-playbook -i ansible/inventory.yml "ansible/$playbook.yml" --syntax-check
done
