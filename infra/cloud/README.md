## GCP (GKE) Deployment with OpenTofu

Use this configuration to spin up an Autopilot GKE cluster, configure Google-managed HTTPS ingress, and deploy the Element Server Suite with a single apply.

### Prerequisites

- [OpenTofu 1.6+](https://opentofu.org/)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) authenticated for your project (`gcloud auth application-default login` or a service-account key in `GOOGLE_APPLICATION_CREDENTIALS`)
- IAM permissions to enable `compute.googleapis.com` / `container.googleapis.com`, create Autopilot clusters, and manage load balancers
- [Helm 3.8+](https://helm.sh/) (required by the Helm provider)
- A Cloud DNS managed zone that serves the domain or subdomain you’ll dedicate to ESS (delegated NS records already in place)

### Configure once

Create `infra/cloud/tofu.tfvars` with the required inputs:

```hcl
project_id    = "ess-one-shot"
domain        = "matrix.mjknowles.dev"
dns_zone_name = "mjknowles-dev-zone"
dns_project_id = "dns-infra"   # optional; defaults to project_id
# region = "us-central1"            # optional override
```

### Bootstrap remote state

```bash
./init-remote-state.sh \
  --project ess-one-shot \
  --bucket ess-one-shot-tfstate \
  --location us
```

The script creates (or validates) the GCS bucket, enables versioning, applies uniform bucket-level access, and writes `backend.hcl` with the supplied settings. Pass `--state-admin you@example.com` or a service account email to grant bucket access for OpenTofu.

### Deploy

```bash
tofu init -backend-config=backend.hcl

# First run: create the GKE cluster so the Kubernetes provider has a live endpoint
tofu apply \
  -target=google_project_service.compute \
  -target=google_project_service.container \
  -target=google_container_cluster.autopilot \
  -var-file=tofu.tfvars

# After the cluster exists you can plan/apply the rest
tofu plan -var-file=tofu.tfvars
tofu apply -var-file=tofu.tfvars
```

During `apply` OpenTofu will enable the necessary APIs, create an Autopilot cluster, reserve a global static IP, provision a Google-managed certificate, install the ESS Helm chart, and publish DNS records (in `dns_project_id` when provided) for:

- `chat.${domain}`
- `admin.${domain}`
- `matrix.${domain}`
- `account.${domain}`
- `rtc.${domain}`

All five hostnames share the reserved static IP, so as soon as DNS propagates the ManagedCertificate will transition to `Active` (typically within 15 minutes).

Monitor `kubectl get ingress -n ess -w` until the IP shows up and watch the managed certificate become `Active`.

### Cleanup

```bash
tofu destroy -var-file=tofu.tfvars
```

This tears down the Helm release, DNS records, and Autopilot cluster.

### Infracost

```bash
# Terraform variables can be set using --terraform-var-file or --terraform-var
infracost breakdown --path .
```
