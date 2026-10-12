# Monthly cost estimate

Planning estimate checked 2026-10-11: USD, 730 hours/month, `us-central1`, two
`e2-small` Spot nodes, two 20 GiB standard persistent boot disks, one regional
external passthrough Network Load Balancer, negligible traffic. Not a quote.

| Component | Approximate monthly cost |
| --- | ---: |
| Two e2-small Spot nodes | $3–10 (variable Spot discount; ordinary on-demand total about $24.46) |
| Two 20 GiB pd-standard boot disks at $0.04/GiB-month | $1.60 |
| Two Spot-node public IPv4 addresses at $0.0025/hour each | $3.65 |
| Load balancer's first five forwarding rules at $0.025/hour total | $18.25 |
| Reserved ingress IPv4 attached to a forwarding rule | $0 |
| Artifact Registry and versioned GCS state (tiny usage) | Usually under $1 |
| Zonal GKE management at $0.10/hour | $73 before free-tier credit |

**Budget $30–40/month** for low traffic if this billing account has its GKE
free-tier credit available. Otherwise **budget $103–113/month**. The $74.40/month
GKE credit is shared by the entire billing account, not granted per project. Other
clusters on this account may already consume it. We have not assumed availability.

Excluded: tax, internet egress, load balancer processing ($0.008/GiB inbound and
outbound), substantial logs/metrics, DNS provider charges, and temporary bootstrap
or maintenance resources. Spot pricing can change daily. Standard VM IPv4 charges
apply briefly to the initial non-Spot bootstrap node. An ingress IP reserved but
not yet attached to a forwarding rule costs $0.01/hour while unused. Artifact
Registry storage has a 0.5 GB free tier then $0.10/GB-month. No Cloud NAT or extra
Application Load Balancer is provisioned. No paid GKE Enterprise features are enabled.

Set a billing budget/alert in the Cloud console; **budgets are alerts, not spending
caps**. Do not leave the cluster running when the lab is no longer needed.

Sources (verify the region selector and current rates before relying on them):

- [GKE pricing and free tier](https://cloud.google.com/kubernetes-engine/pricing)
- [Spot VM pricing](https://cloud.google.com/spot-vms/pricing)
- [Compute and persistent disk pricing](https://cloud.google.com/compute/all-pricing)
- [Network, forwarding rules and IPv4 pricing](https://cloud.google.com/vpc/network-pricing)
- [Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing)
- [Cloud Storage pricing](https://cloud.google.com/storage/pricing)
