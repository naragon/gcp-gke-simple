# Clean teardown and rebuilding with retained images

This is a reusable runbook. Names such as `your-gcp-project` and `lab.example.com`
are placeholders, not live deployment details. Review all destructive operations.
Set the target project in your shell before following any section:

```sh
export PROJECT_ID="your-gcp-project"  # Must match your local Terraform vars.
```

## 1. Remove Kubernetes workloads first

While the cluster is still running:

```sh
make teardown-app
```

The playbook deletes `hello` while cert-manager is available, then uninstalls
Traefik and cert-manager and removes their namespaces. Wait for cloud load-balancer
cleanup before deleting the cluster/network. cert-manager CRDs retained by Helm
are removed when the cluster is destroyed.

Deleting namespaces discards TLS/ACME account private keys. No certificate backup
is required for this demo; rebuilding requests new certificates and account keys.
Secret/cluster deletion does not itself revoke already-issued certificates at the CA.

## 2. Disable cluster deletion protection

```sh
terraform -chdir=terraform/infra plan -var=deletion_protection=false
terraform -chdir=terraform/infra apply -var=deletion_protection=false
```

Review the plan before applying. Apply this change before forgetting any resources
that you intend to preserve, or a normal apply could try to recreate them.

## 3. Optional: keep the private image repository

Skip this section to delete the repository and its images during normal destruction.
To retain it instead, remove automatic cleanup policies so idle images stay intact:

```sh
export PROJECT_ID="your-gcp-project"  # Use the same project as your Terraform vars.
gcloud artifacts repositories delete-cleanup-policies hello \
  --location=us-central1 --project="$PROJECT_ID" \
  --policynames=delete-old,keep-recent
terraform -chdir=terraform/infra state rm google_artifact_registry_repository.app
```

The state command **forgets ownership without deleting the repository**. Retained
images remain private, immutable and subject to storage/transfer pricing. The node's
repository-read IAM binding is still tracked and will be deleted with the node identity.

Do not run a normal infra apply after forgetting the repository unless you first
import it again. A destroy plan only removes resources remaining in state.

## 4. Destroy infrastructure and verify

```sh
terraform -chdir=terraform/infra plan -destroy -var=deletion_protection=false
terraform -chdir=terraform/infra destroy -var=deletion_protection=false

gcloud container clusters list --project="$PROJECT_ID"
gcloud compute instances list --project="$PROJECT_ID"
gcloud compute disks list --project="$PROJECT_ID"
gcloud compute addresses list --project="$PROJECT_ID"
gcloud compute forwarding-rules list --project="$PROJECT_ID"
gcloud compute backend-services list --project="$PROJECT_ID"
gcloud compute health-checks list --project="$PROJECT_ID"
gcloud compute networks list --project="$PROJECT_ID"
```

Check for orphan resources rather than assuming Terraform owns everything created
by Kubernetes. Destroying the node pool should also remove its instance groups and
boot disks. Unused default networks, firewall rules and default identities are not
managed by this Terraform stack; remove them separately only if they are unused
and you have explicitly chosen to do so.

The project, its billing link, APIs (`disable_on_destroy=false`) and protected state
bucket remain. Enabled APIs alone do not imply paid runtime; Google-managed project
service agents can remain. Never delete a shared billing account or unrelated project.

## 5. Optional: delete state/history but retain the project/images

Only after infra destruction succeeds and no managed resources remain in state:

```sh
terraform -chdir=terraform/infra state list  # Must be empty.
# DESTRUCTIVE: deletes bootstrap and infra state plus all object versions.
gcloud storage buckets update "gs://${PROJECT_ID}-tfstate" --clear-soft-delete
gcloud storage rm --recursive "gs://${PROJECT_ID}-tfstate/"
```

This deliberately bypasses the bootstrap stack's `prevent_destroy` protection with
an explicit operation. Do not use bootstrap Terraform destroy to remove the bucket
holding that stack's own state. Clearing soft-delete prevents new retained deletions;
previously soft-deleted objects may still follow provider retention rules. Choose any
required exports/backups before deletion and store them privately, never in Git.

Remove obsolete temporary saved plans locally. Historic costs may appear later in
billing reports; retained Artifact Registry images still incur applicable storage
and download charges, potentially covered by the shared storage free tier.

## 6. Rebuild with an existing repository

If the project/repository were retained but state was removed:

```sh
# Authenticate with gcloud and ADC if needed; configure local vars as in README.
export PROJECT_ID="your-gcp-project"
make setup
make bootstrap

# Set terraform/infra/terraform.tfvars: project_id and current operator IPv4 /32.
# Import before applying a fresh state to avoid duplicate repository creation.
terraform -chdir=terraform/infra import \
  google_artifact_registry_repository.app \
  "projects/${PROJECT_ID}/locations/us-central1/repositories/hello"
make plan
make apply
make deploy
```

Review the plan: the current source restores the original image cleanup policies.
Change those policies if permanent retention of every future untagged artifact is
required. Ansible reuses existing content-derived image tags when app source and
Dockerfile are unchanged.

Read the **new** ingress address from Terraform output; do not reuse an old address.
Create the DNS-only A record at your provider, then run `make staging` followed by
`make production`. New credentials replace stale cluster entries in the isolated
kubeconfig; new certificates require successful ACME validation. No project creation
or billing relinking is needed when the project was retained.
