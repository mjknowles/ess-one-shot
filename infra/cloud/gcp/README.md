# GCP Quickstart

Follow these steps to bring the Element Server Suite online on GKE Autopilot with Cloud SQL.

## Prerequisites

- [OpenTofu 1.6+](https://opentofu.org/)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) with `gcloud auth application-default login` (or a service-account key exported in `GOOGLE_APPLICATION_CREDENTIALS`)
- [Helm 3.8+](https://helm.sh/)
- IAM access to create/modify GKE, Cloud SQL, DNS, and Secret Manager resources in the target project
- A Cloud DNS managed zone that already serves the domain or subdomain you plan to dedicate to ESS
- `helm repo add element-hq https://element-hq.github.io/helm-charts`

## 1. Set your inputs

Create `infra/cloud/gcp/terraform.tfvars` with the project and DNS details:

```hcl
project_id     = "ess-one-shot"
domain         = "mjknowles.dev"
dns_zone_name  = "mjknowles-dev-zone"
# dns_project_id = "dns-infra-474704"  # set only if the DNS zone lives in another project
```

## 2. Initialize remote state

One bucket, two prefixes—one per stack. Run these once to write backend files:

- Base backend (`infra/cloud/gcp/base/backend.hcl`, prefix `opentofu/base`):

  ```bash
  ./init-remote-state.sh \
    --project ess-one-shot \
    --bucket ess-one-shot-tfstate \
    --location us \
    --backend-file base/backend.hcl
  ```

- Gateway backend (`infra/cloud/gcp/gateway/backend.hcl`, prefix `opentofu/gateway`):
  ```bash
  ./init-remote-state.sh \
    --project ess-one-shot \
    --bucket ess-one-shot-tfstate \
    --location us \
    --prefix opentofu/gateway \
    --backend-file gateway/backend.hcl
  ```

Use your project, bucket, and region; add `--state-admin you@example.com` if someone else needs bucket access. Never share a prefix between stacks.

## 3. Apply the infrastructure

```bash
cd base
tofu init -backend-config=backend.hcl
tofu apply -var-file=../terraform.tfvars -auto-approve

```

Configure your kubeconfig as soon as the Autopilot cluster is created (no need to wait for the full `tofu apply` to finish):

```bash
gcloud container clusters get-credentials "ess-one-shot-gke2" \
  --region "us-central1" \
  --project ess-one-shot
```

## 4. Deploy the platform charts

Once `kubectl` reaches the cluster, drop the mautrix-signal bridge configuration into `infra/mautrix-signal/config/` (the directory is ignored by Git) and run the helper script. The deploy helper renders those files into a ConfigMap inside the `ess` namespace, deploys the Element Server Suite, and then upgrades the mautrix-signal bridge against that same ConfigMap:

```bash
./deploy-charts.sh
```

The Synapse release automatically references the generated ConfigMap (`registration.yaml`) under `synapse.appservices`, so the bridge appears as an application service without manual edits.

## 5. After apply

Deploy gateway:

```bash
  cd gateway
  tofu init -reconfigure -backend-config=backend.hcl
  tofu apply -var-file=../terraform.tfvars -auto-approve
```

## 6. Tear down (when you are done)

- Optional: clean up the Helm releases before destroying infra.

  ```bash
  helm uninstall ess -n ess || true
  ```

- Destroy the Gateway stack first so the certificate map is released:

  ```bash
  tofu destroy -auto-approve -var-file=../terraform.tfvars
  ```

  It can take ~60 seconds for the managed load balancer to detach from the certificate map. If you see `RESOURCE_STILL_IN_USE`, retry once `gcloud compute target-https-proxies list` no longer shows the proxy.

- Finally destroy the base stack:

  ```bash
  tofu destroy -var-file=../terraform.tfvars
  ```

- Clean up remaining networking or DNS bits if required:

  ```bash
  gcloud compute networks peerings delete servicenetworking-googleapis-com \
    --network=ess-one-shot-vpc \
    --project=ess-one-shot

  gcloud dns record-sets delete _acme-challenge.mjknowles.dev. \
    --zone="mjknowles-dev-zone" \
    --project="dns-infra-474704" \
    --type="CNAME"
  ```

Remove any leftover Cloud SQL data manually if you no longer need it.

### If you delete Cloud SQL manually

If you remove the Cloud SQL instance or databases outside of OpenTofu, prune the state so subsequent destroys succeed:

```bash
tofu state rm google_sql_database_instance.ess
```

Adjust the list if you only removed a subset (for example, omit the instance line if you deleted just the databases). After the state is updated, rerun `tofu destroy` for the base stack so the remaining resources are cleaned up.

For the gateway stack, remove the Kubernetes manifests and helper resources from state so Tofu does not try to manage objects that no longer exist:

```bash
tofu state rm \
  kubernetes_manifest.gateway \
  kubernetes_manifest.healthcheckpolicy_haproxy \
  kubernetes_manifest.healthcheckpolicy_matrix_rtc_auth \
  kubernetes_manifest.healthcheckpolicy_synapse \
  kubernetes_manifest.healthcheckpolicy_well_known \
  kubernetes_manifest.route_element_admin \
  kubernetes_manifest.route_element_web \
  kubernetes_manifest.route_matrix \
  kubernetes_manifest.route_matrix_auth \
  kubernetes_manifest.route_matrix_rtc \
  kubernetes_manifest.route_well_known \
  time_sleep.wait_for_gateway_api
```

Leave `data.google_client_config.default` and `data.terraform_remote_state.base` untouched; they are data-only references and do not affect state drift. Once the state is cleaned up, rerun `tofu -chdir=infra/cloud/gcp/gateway destroy` to validate nothing remains.

If the base stack state has already been deleted, the remote-state data source in the gateway module no longer has outputs and `tofu destroy` will fail. In that case, remove the remaining data-only entries and skip the destroy step:

```bash
pushd infra/cloud/gcp/gateway
tofu state rm data.google_client_config.default data.terraform_remote_state.base || true
popd
```

With every managed resource removed from state, the gateway stack is effectively dismantled.

## Troubleshooting the chart deployment

If the script fails, these steps usually get things moving again:

- Let the `tofu apply` finish (or fail) before retrying Helm work so the outputs the script reads stay consistent.
- Inspect the rendered values (`/tmp/.../ess-values.yaml`) referenced in the script output to confirm credentials and hostnames match expectations.
- Verify your kubeconfig context and permissions (`kubectl auth can-i create secrets -n ess`).
- If a release gets wedged, use `helm uninstall <release> -n <namespace>` and re-run `./infra/cloud/gcp/deploy-charts.sh`.

```

```
