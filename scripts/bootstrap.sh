#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
project="${PROJECT_ID:?Set PROJECT_ID to your GCP project ID before running bootstrap}"
bucket="${project}-tfstate"
# Project creation/billing is deliberately explicit; never choose a billing account silently.
gcloud projects describe "$project" >/dev/null
if ! gcloud storage buckets describe "gs://$bucket" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$bucket" --project="$project" --location=us-central1 \
    --uniform-bucket-level-access --public-access-prevention
fi
gcloud storage buckets update "gs://$bucket" --versioning
terraform -chdir=terraform/bootstrap init -backend-config="bucket=$bucket" -backend-config=prefix=bootstrap
if ! terraform -chdir=terraform/bootstrap state list | grep -qx google_storage_bucket.state; then
  terraform -chdir=terraform/bootstrap import -var="project_id=$project" google_storage_bucket.state "$bucket"
fi
terraform -chdir=terraform/bootstrap apply -var="project_id=$project" "$@"
terraform -chdir=terraform/infra init -backend-config="bucket=$bucket" -backend-config=prefix=infra
