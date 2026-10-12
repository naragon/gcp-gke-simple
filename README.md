# Tiny GKE lab

> **Public example:** Configure your own project, domain, email and operator CIDR.
> No live deployment state or credentials are included. See
> [teardown and rebuilding with retained images](docs/teardown.md) and
> [safe handling of local configuration](SECURITY.md).

Hello world in Go on a **zonal GKE Standard cluster with exactly two Spot nodes**.
Terraform owns GCP resources; Ansible owns images and Kubernetes workloads.

Defaults: region `us-central1`, zone `us-central1-a`. The project ID is required.
The sample hostname `lab.example.com`, email `admin@example.com`, and documented
`203.0.113.10/32` are reserved examples: replace them before deployment.

```
app/                  Go server, tests, pinned multi-stage Dockerfile
terraform/bootstrap/  Private, versioned GCS Terraform state bucket
terraform/infra/      APIs, VPC, GKE, node IAM, Artifact Registry, static ingress IP
ansible/              Pinned collections/dependencies, deployment and teardown
scripts/              Local setup, bootstrap, deployment and checks
```

## Design and trade-offs

- Two `e2-small` Spot nodes, 20 GiB standard disks, regular release channel,
  automatic repair/upgrades, Shielded nodes, secure boot and Workload Identity.
- Two app replicas and two Traefik replicas spread across nodes where possible.
  Spot eviction and a single zone **can cause complete downtime**. cert-manager
  components each have one replica. Rollouts use no surge nodes/pods. The unused
  persistent-disk CSI add-on is disabled to leave memory for certificate solvers;
  this stateless lab does not support PVCs unless you re-enable it.
  This is a cheap lab, not a production HA design.
- Public node IPs avoid Cloud NAT cost. A custom VPC has no generic SSH or other
  inbound allow rule; GKE creates required cluster and load-balancer firewall rules.
  The public Kubernetes API is restricted to `admin_cidr`, preferably your `/32`.
  For production, use private nodes, controlled egress, and private/IAM DNS API access.
- Traefik terminates HTTPS behind one regional passthrough Network Load Balancer.
  HTTP redirects apply only to the app, leaving HTTP-01 challenges reachable.
  No public dashboard, no ingress-nginx dependency, no second L7 load balancer.
- cert-manager is installed in namespace **`cert-manager`**. Namespace-scoped
  Let's Encrypt `Issuer` resources in `hello` avoid exposing a shared ClusterIssuer.
  Staging is the default; production promotion requires a Ready staging certificate.
- App image: tested, digest-pinned deployment, static binary in `scratch`, non-root,
  read-only root filesystem, no service-account token, dropped capabilities,
  runtime seccomp, health probes, resource bounds, graceful shutdown, no dependencies.
- App NetworkPolicy denies all egress and allows ingress only from Traefik.
  GKE Dataplane V2 enforces it. Solver pods are not selected by the app policy.
- Component namespaces enforce restricted Pod Security. `hello` enforces baseline
  for cert-manager's generated solver pods, while the app meets restricted rules.
- Private Artifact Registry replaces the retired Google Container Registry.
  Immutable content-derived tags and deployment by digest. Cleanup removes untagged
  images after 30 days while keeping five recent images. Immutable tagged releases
  are retained until repository teardown (Google cannot auto-clean those tags).
  Never deploy `latest`.
- Dedicated node service account gets GKE's default node role and **repository-only**
  image-read permission. No service-account keys, passwords or certs in source.
- GCS state uses locking, versioning, uniform access, public-access prevention,
  Google-managed encryption, and deletion protection. Bootstrap and infra have
  separate state prefixes. State and plans remain sensitive; restrict bucket IAM
  to trusted operators (`roles/storage.objectAdmin` on this bucket for state users).
  GCP project creation/billing link are explicit bootstrap operations outside Terraform.

**Estimated cost: $30–40/month with available GKE credit, $103–113 without it.**
See [the breakdown and caveats](docs/costs.md) and the
[deployment validation checklist](docs/deployment.md).

## Prerequisites

Install `gcloud`, Terraform >=1.10 (<2), Docker with a running daemon, Helm 3 or 4,
`kubectl`, `gke-gcloud-auth-plugin`, `uv`, and Go >=1.26 for local tests.
`uv` installs isolated Python 3.13 and pinned Ansible dependencies; no system Python
packages are modified. Node architecture and image build are `linux/amd64`.

Install the GKE auth plugin with your SDK/package manager (for a standalone SDK:
`gcloud components install gke-gcloud-auth-plugin`; Debian/Ubuntu packages commonly
use `google-cloud-cli-gke-gcloud-auth-plugin`). A repo-local plugin may alternatively
be placed in `.tools/bin/`; scripts add that directory to PATH. Do not commit it.

Authenticate **both** command-line and Terraform credentials:

```sh
gcloud auth login
gcloud auth application-default login
make setup
```

The bootstrap operator needs permission to create projects/link billing and manage
GKE, compute networks, Artifact Registry, service accounts/IAM, API enablement and
GCS state. Deployment needs cluster-admin for controller CRDs/RBAC plus repository
writer and GKE credential access. Use a trusted temporary bootstrap operator; do
not grant Owner/Editor to nodes or application service accounts. For future CI,
use identity federation and separate scoped infra/deploy identities, not JSON keys.
Bootstrap uses the operator's authenticated gcloud and ADC credentials.

## 1. Project and state bootstrap

Use an existing project or explicitly create one and choose a billing account
(never blindly select the first). Project IDs must be globally unique:

```sh
export PROJECT_ID="your-gcp-project"  # Replace with your own unique project ID.
gcloud projects create "$PROJECT_ID" --name="GKE demo"  # Skip if it already exists.
gcloud billing accounts list
gcloud billing projects link "$PROJECT_ID" --billing-account=YOUR_BILLING_ACCOUNT
```

```sh
make bootstrap
```

This creates the state bucket once, enables versioning, immediately imports it
into its own remote Terraform state, applies protective settings, and initializes
infra's backend. No local-state migration, backend secrets, or hard-coded credentials.
It is safe to repeat. The bucket is `${PROJECT_ID}-tfstate`, with prefixes
`bootstrap` and `infra`. Bootstrap requires `PROJECT_ID`; use the same ID in the
infra variables below.

## 2. Infrastructure

```sh
cp terraform/infra/terraform.tfvars.example terraform/infra/terraform.tfvars
# Set project_id to $PROJECT_ID and admin_cidr to your public IP/32.
# To check your public IP: curl -fsS https://api.ipify.org
make plan
make apply
```

Review the saved plan before applying. Cluster creation normally takes several
minutes. `.tfvars`, plans, kubeconfig, tokens and Terraform caches are gitignored;
commit both `.terraform.lock.hcl` files. `make check` runs Go tests/race checks/vet,
formatting, Terraform validation and Ansible syntax checks after setup/bootstrap.

## 3. App and staging certificate

Keep your actual hostname and ACME contact email in an ignored local override,
not in `ansible/vars.yml`. All deployment Make targets load this file automatically;
explicit command-line extra variables take precedence.

```sh
mkdir -p .local && chmod 700 .local
cat > .local/deployment.yml <<'YAML'
hostname: lab.example.com       # Replace with a hostname you control.
acme_email: admin@example.com   # Replace with your actual ACME contact email.
YAML
chmod 600 .local/deployment.yml
make deploy
terraform -chdir=terraform/infra output deployment
```

Ansible reads Terraform outputs directly, fetches credentials into `.local/kubeconfig`,
builds/tests the app, pushes with a short-lived token in a temporary Docker config,
then deploys controllers, the app and its staging certificate request. Existing
immutable source images are reused; changed sources produce new tags. Credentials
are cleaned even on push failure. No normal kubeconfig context is changed.

At your existing DNS provider, create a **DNS-only/unproxied A record**:

```
lab.example.com -> ingress_ip from Terraform output
```

Remove any conflicting AAAA record unless you've separately configured IPv6. Keep
ports 80 and 443 public; HTTP-01 renewals require port 80. Existing CAA policy must
allow `letsencrypt.org`. DNS itself is deliberately not automated: the DNS provider
and API permissions were not supplied.

```sh
# Once public DNS resolves to the correct ingress IP:
make staging
export PATH="$PWD/.tools/bin:$PATH"
export KUBECONFIG="$PWD/.local/kubeconfig"
kubectl -n hello get certificate,issuer,order,challenge
curl -k https://lab.example.com/  # Replace host; staging CA is NOT browser-trusted.
curl -I http://lab.example.com/  # Expect HTTPS redirect.
```

Without DNS, deployment still finishes but the Certificate stays unready. The
`make staging` command waits up to ten minutes and fails if issuance is incomplete.
Do not treat a default/self-signed Traefik certificate as successful issuance.

## 4. Promote to a trusted production certificate

After the staging Certificate is Ready and you have verified the endpoint:

```sh
make production
curl --fail https://lab.example.com/   # Replace host; no -k for production.
```

Promotion preserves the staging certificate, creates a separate production
certificate/secret, and switches the HTTPS ingress to it. cert-manager renews it
automatically. Issuer account keys and TLS private keys live only in Kubernetes
Secrets; namespace access must be restricted. Re-running `make deploy` defaults
back to staging; use `make production` for subsequent production deployments, or
intentionally change `acme_environment` in `ansible/vars.yml` after testing.

## Operations

```sh
export PATH="$PWD/.tools/bin:$PATH" KUBECONFIG="$PWD/.local/kubeconfig"
kubectl get nodes -L cloud.google.com/gke-spot
kubectl get pods -A
kubectl -n cert-manager logs deploy/cert-manager
kubectl -n hello describe certificate hello-staging
terraform -chdir=terraform/infra plan
```

Failed ACME issuance uses exponential retry backoff (1–32 hours). `make staging`
waits for readiness but does not bypass that backoff. After resolving a DNS or
validation failure, an optional installed `cmctl` can trigger one immediate retry:
`cmctl renew -n hello hello-staging`. Do not repeatedly force retries or bypass
staging readiness to issue a production certificate. Check Order/Challenge status
and cert-manager logs for the actual failure reason.

If your public IP changes, update `admin_cidr` and apply Terraform before deploying.
If memory becomes tight, set `node_machine_type = "e2-medium"`, review/apply the plan;
that raises costs and rotates the node pool. Application log collection and managed
Prometheus are off to limit expense; app logs remain available with `kubectl logs`.
Refresh builder digests, charts, provider locks and Python dependency locks deliberately
for security updates. Source tags change when the pinned Dockerfile changes.

## Teardown (stop ongoing charges)

First remove Kubernetes resources **while the cluster still exists**, so GKE can
clean up the load balancer before Terraform deletes its IP/network:

```sh
make teardown-app
terraform -chdir=terraform/infra apply -var=deletion_protection=false
terraform -chdir=terraform/infra plan -destroy -var=deletion_protection=false
terraform -chdir=terraform/infra destroy -var=deletion_protection=false
```

Review and confirm each destructive operation. cert-manager CRDs are deliberately
kept on uninstall; destroying the cluster removes them. APIs, project, billing
link and protected state bucket are deliberately retained. Artifact Registry
images are deleted when its repository is destroyed. Confirm no forwarding rules,
VMs, disks or unused IPs remain in the project. To remove everything including
state/history, separately and explicitly delete the lab project after exporting
any state you need; don't use the bootstrap stack's destroy to remove its own state.
