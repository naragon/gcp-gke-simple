# Deployment validation checklist

This public guide uses placeholders, not live project identifiers or addresses.
See the [README](../README.md) for setup and [costs](costs.md) before provisioning.

## Before deploying

- Set `PROJECT_ID`, bootstrap state, and use the same ID in ignored Terraform vars.
- Restrict `admin_cidr` to your current public IPv4 `/32`.
- Put a hostname you control and your ACME contact email in `.local/deployment.yml`.
- Run `make check`, review `make plan`, and only then `make apply`/`make deploy`.

## Infrastructure and application

```sh
export PATH="$PWD/.tools/bin:$PATH"
export KUBECONFIG="$PWD/.local/kubeconfig"
kubectl get nodes -L cloud.google.com/gke-spot
kubectl get pods -A
terraform -chdir=terraform/infra output deployment
```

Expect two Ready Spot nodes, two app replicas in `hello`, two Traefik replicas in
`ingress-system`, and Ready cert-manager components in `cert-manager`. Inspect the
Traefik LoadBalancer Service and confirm its public address matches Terraform output.

At your DNS provider, set a DNS-only A record for your hostname to that address.
Remove conflicting AAAA records; allow `letsencrypt.org` in any CAA policy.

## Staging before production

```sh
make staging
kubectl -n hello get certificate,issuer,order,challenge
curl -k https://lab.example.com/  # Replace host; staging is intentionally untrusted.
curl -I http://lab.example.com/  # Replace host; expect a redirect.
make production                 # Requires the staging Certificate to be Ready.
curl --fail https://lab.example.com/  # Replace host; do not use -k in production.
```

An Issuer being Ready does not imply the website Certificate was issued. Inspect
Certificate conditions, ACME Orders/Challenges, and controller logs. A default
Traefik certificate is not evidence of successful issuance. DNS visibility from
one resolver also does not guarantee Let's Encrypt's secondary validators can
resolve A/AAAA records; inspect authoritative delegation and allow propagation.
Avoid repeated forced retries and respect ACME backoff/rate limits.

After a successful deployment, a Terraform plan should show no changes and an
Ansible rerun should reuse the immutable image and converge without changes.
Record operational status privately; redact Secret values in any shared diagnostics.

## When finished

Use [clean teardown](teardown.md). Remove the DNS record before releasing its IP,
and verify that no orphan load balancer, public IP, VM or disk remains billable.
