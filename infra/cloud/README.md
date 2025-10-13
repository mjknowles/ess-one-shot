# GCP Quickstart

Follow these steps to bring the Element Server Suite online on GKE Autopilot with Cloud SQL and Datastream.

## Prerequisites

- [OpenTofu 1.6+](https://opentofu.org/)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) with `gcloud auth application-default login` (or a service-account key exported in `GOOGLE_APPLICATION_CREDENTIALS`)
- [Helm 3.8+](https://helm.sh/)
- IAM access to create/modify GKE, Cloud SQL, Datastream, BigQuery, DNS, and Secret Manager resources in the target project
- A Cloud DNS managed zone that already serves the domain or subdomain you plan to dedicate to ESS

## 1. Set your inputs

Create `infra/cloud/tofu.tfvars` with the project and DNS details:

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
# One-time: enable core APIs and create the Autopilot cluster
tofu apply \
  -target=google_project_service.compute \
  -target=google_project_service.container \
  -target=google_container_cluster.autopilot \
  -var-file=tofu.tfvars -auto-approve

# Full rollout for everything else
tofu plan -var-file=tofu.tfvars
tofu apply -var-file=tofu.tfvars -auto-approve
```

Configure your kubeconfig as soon as the Autopilot cluster is created (no need to wait for the full `tofu apply` to finish):

```bash
gcloud container clusters get-credentials "ess-one-shot-gke" \
  --region "us-central1" \
  --project ess-one-shot
```

## 4. Deploy the platform charts

Once `kubectl` reaches the cluster, run the helper script to install the Element Server Suite Helm chart with the exact settings that used to live in `helm.tf`. The GKE Gateway, static IP, and Google-managed certificates are provisioned by OpenTofu:

```bash
./deploy-charts.sh
```

## 5. After apply

- Grant Datastream access to Cloud SQL (run once as the `postgres` user):

  ```sql
  ALTER ROLE datastream_replica WITH REPLICATION;
  GRANT CONNECT ON DATABASE synapse TO datastream_replica;
  GRANT CONNECT ON DATABASE mas TO datastream_replica;
  GRANT USAGE ON SCHEMA public TO datastream_replica;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream_replica;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO datastream_replica;
  ```

- Start the Datastream jobs after the grants succeed:

  ```bash
  ANALYTICS_LOC="$(tofu output -raw analytics_location)"

  gcloud datastream streams update "$(tofu output -json datastream_stream_ids | jq -r '.synapse')" \
    --location "${ANALYTICS_LOC}" \
    --desired-state=RUNNING \
    --project "${PROJECT_ID}"

  gcloud datastream streams update "$(tofu output -json datastream_stream_ids | jq -r '.mas')" \
    --location "${ANALYTICS_LOC}" \
    --desired-state=RUNNING \
    --project "${PROJECT_ID}"
  ```

- Confirm BigQuery tables are receiving data from Datastream when the streams report `state: RUNNING`.

## 6. Tear down (when you are done)

```bash
# Optional: clean up the Helm releases before destroying infra
helm uninstall ess -n ess || true

# Remove the GKE and supporting resources
tofu destroy -var-file=tofu.tfvars -refresh=false
```

Remove any leftover Cloud SQL data or BigQuery tables manually if you no longer need them.

## Troubleshooting the chart deployment

If the script fails, these steps usually get things moving again:

- Let the `tofu apply` finish (or fail) before retrying Helm work so the outputs the script reads stay consistent.
- Inspect the rendered values (`/tmp/.../ess-values.yaml`) referenced in the script output to confirm credentials and hostnames match expectations.
- Verify your kubeconfig context and permissions (`kubectl auth can-i create secrets -n ess`).
- If a release gets wedged, use `helm uninstall <release> -n <namespace>` and re-run `./infra/cloud/deploy-charts.sh`.
