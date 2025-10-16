# GCP Quickstart

Follow these steps to bring the Element Server Suite online on GKE Autopilot with Cloud SQL and Datastream.

## Prerequisites

- [OpenTofu 1.6+](https://opentofu.org/)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) with `gcloud auth application-default login` (or a service-account key exported in `GOOGLE_APPLICATION_CREDENTIALS`)
- [Helm 3.8+](https://helm.sh/)
- IAM access to create/modify GKE, Cloud SQL, Datastream, BigQuery, DNS, and Secret Manager resources in the target project
- A Cloud DNS managed zone that already serves the domain or subdomain you plan to dedicate to ESS

## 1. Set your inputs

Create `infra/cloud/terraform.tfvars` with the project and DNS details:

```hcl
project_id     = "ess-one-shot"
domain         = "mjknowles.dev"
dns_zone_name  = "mjknowles-dev-zone"
# dns_project_id = "dns-infra-474704"  # set only if the DNS zone lives in another project
```

## 2. Initialize remote state

```bash
./init-remote-state.sh \
  --project ess-one-shot \
  --bucket ess-one-shot-tfstate \
  --location us

tofu init -backend-config=backend.hcl
```

Run with your project, bucket, and region; add `--state-admin you@example.com` if someone else needs access to the bucket.

## 3. Apply the infrastructure

```bash
tofu apply -var-file=../terraform.tfvars -auto-approve

```

Configure your kubeconfig as soon as the Autopilot cluster is created (no need to wait for the full `tofu apply` to finish):

```bash
gcloud container clusters get-credentials "ess-one-shot-gke2" \
  --region "us-central1" \
  --project ess-one-shot
```

## 4. Deploy the platform charts

Once `kubectl` reaches the cluster, run the helper script to install the Element Server Suite Helm chart with the exact settings that used to live in `helm.tf`. The GKE Gateway, static IP, and Google-managed certificates are provisioned by OpenTofu:

```bash
./deploy-charts.sh
```

## 5. After apply

- Run the helper to grant Datastream access on Cloud SQL and start the streams:

  ```bash
  ./post-apply.sh
  ```

  Pass `--project` or `--tf-dir` if you applied from a different project or directory.

- Confirm BigQuery tables are receiving data from Datastream when the streams report `state: RUNNING`.

## 6. Tear down (when you are done)

```bash
# Optional: clean up the Helm releases before destroying infra
helm uninstall ess -n ess || true

# Remove the GKE and supporting resources
tofu destroy -var-file=../terraform.tfvars

# cleanup some bullcrap that's not working
gcloud compute networks peerings delete servicenetworking-googleapis-com \
  --network=ess-one-shot-vpc \
  --project=ess-one-shot

gcloud dns record-sets delete _acme-challenge.mjknowles.dev. \
  --zone="mjknowles-dev-zone" \
  --project="dns-infra-474704" \
  --type="CNAME"
```

Remove any leftover Cloud SQL data or BigQuery tables manually if you no longer need them.

## Troubleshooting the chart deployment

If the script fails, these steps usually get things moving again:

- Let the `tofu apply` finish (or fail) before retrying Helm work so the outputs the script reads stay consistent.
- Inspect the rendered values (`/tmp/.../ess-values.yaml`) referenced in the script output to confirm credentials and hostnames match expectations.
- Verify your kubeconfig context and permissions (`kubectl auth can-i create secrets -n ess`).
- If a release gets wedged, use `helm uninstall <release> -n <namespace>` and re-run `./infra/cloud/deploy-charts.sh`.
