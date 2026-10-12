# Security and local configuration

This repository contains a reusable example, not a live deployment inventory.
Example domains/emails use `example.com`; public IPv4 examples use the documentation
range `203.0.113.0/24`. Choose your own globally unique GCP project ID.

## Keep private inputs local

- Use ignored `terraform/infra/terraform.tfvars` for the project ID/operator CIDR.
- Use ignored `.local/deployment.yml` for the hostname and ACME contact email.
  Deployment scripts load it automatically; explicit CLI extra variables win.
- Keep Terraform state/plans, kubeconfig, snapshots and logs under `.local/` or
  outside the checkout. Terraform caches, local tools and Python environments are
  ignored. Provider/dependency lockfiles are public integrity metadata, not secrets.
- Never commit service-account JSON keys, tokens, `.env` files, private keys,
  certificate backups, Kubernetes Secret dumps or credential-bearing URLs.
- Prefer short-lived gcloud credentials or identity federation, not static keys.
  Restrict remote-state bucket IAM and Kubernetes namespace/Secret access.

`.gitignore` prevents common mistakes but does not protect files already tracked,
and scanning cannot guarantee detection of every secret. Inspect the exact staged
files before committing; never force-add ignored local configuration.

```sh
git status --short
git diff --cached --check
git diff --cached
# With Gitleaks installed, scan the staged content and all reachable history:
git diff --cached --no-ext-diff --unified=0 | gitleaks stdin --redact
gitleaks git --redact .
```

If a credential leaks, revoke/rotate it immediately, then remove it from reachable
history and consider forks/caches. Deleting a file in a later commit is insufficient.

## Reporting vulnerabilities

Report security issues privately using GitHub's **Security → Report a vulnerability**
feature when enabled. Do not open a public issue containing credentials, private
keys, exploitable private endpoints or sensitive deployment details.
