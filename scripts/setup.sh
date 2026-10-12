#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in gcloud terraform docker helm kubectl uv; do
  command -v "$tool" >/dev/null || { echo "Install $tool first (see README.md)." >&2; exit 1; }
done
uv venv --allow-existing --python 3.13 .venv
uv pip sync --python .venv/bin/python --require-hashes ansible/requirements.lock
ANSIBLE_COLLECTIONS_PATH="$PWD/.tools/collections" .venv/bin/ansible-galaxy collection install -r ansible/requirements.yml -p .tools/collections
if ! command -v gke-gcloud-auth-plugin >/dev/null && [[ ! -x .tools/bin/gke-gcloud-auth-plugin ]]; then
  echo 'Install gke-gcloud-auth-plugin using your SDK/package manager (see README.md).' >&2
  exit 1
fi
