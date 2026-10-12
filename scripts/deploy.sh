#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/.tools/bin:$PATH"
# Use an isolated kubeconfig rather than changing the user's current context.
mkdir -p .local
chmod 700 .local
export KUBECONFIG="$PWD/.local/kubeconfig"
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
export ANSIBLE_COLLECTIONS_PATH="$PWD/.tools/collections"
export HELM_CACHE_HOME="$PWD/.tools/helm/cache"
export HELM_CONFIG_HOME="$PWD/.tools/helm/config"
export HELM_DATA_HOME="$PWD/.tools/helm/data"
# Keep site-specific hostname/email outside tracked source. CLI overrides win.
if [[ -f .local/deployment.yml ]]; then
  set -- -e "@$PWD/.local/deployment.yml" "$@"
fi
exec .venv/bin/ansible-playbook -i ansible/inventory.yml "ansible/${PLAYBOOK:-deploy.yml}" "$@"
