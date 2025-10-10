## GCP (GKE) Deployment with OpenTofu

Use this configuration to spin up an Autopilot GKE cluster, configure Google-managed HTTPS ingress, provision Cloud SQL for PostgreSQL, and deploy the Element Server Suite with BigQuery-ready CDC via Datastream in a single apply.

### Prerequisites

- [OpenTofu 1.6+](https://opentofu.org/)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) authenticated for your project (`gcloud auth application-default login` or a service-account key in `GOOGLE_APPLICATION_CREDENTIALS`)
- IAM permissions to enable `compute.googleapis.com`, `container.googleapis.com`, `servicenetworking.googleapis.com`, `sqladmin.googleapis.com`, `secretmanager.googleapis.com`, `datastream.googleapis.com`, and `bigquery.googleapis.com`
- Project-level rights to create/modify Cloud SQL instances, BigQuery datasets, Datastream streams, GCP service accounts, and Kubernetes secrets
- [Helm 3.8+](https://helm.sh/) (required by the Helm provider)
- A Cloud DNS managed zone that serves the domain or subdomain you’ll dedicate to ESS (delegated NS records already in place)

### Configure once

Create `infra/cloud/tofu.tfvars` with the required inputs, then override the optional knobs as needed for Cloud SQL sizing or CDC placement:

```hcl
project_id    = "ess-one-shot"
domain        = "matrix.mjknowles.dev"
dns_zone_name = "mjknowles-dev-zone"
dns_project_id = "dns-infra"   # optional; defaults to project_id
# region = "us-central1"            # optional override
# vpc_network_name = "default"      # existing VPC shared by GKE + Cloud SQL

# cloudsql_instance_name      = "ess-matrix-postgres"
# cloudsql_tier               = "db-custom-2-8192"
# cloudsql_disk_size_gb       = 100
# cloudsql_availability_type  = "ZONAL"
# cloudsql_backup_start_time  = "03:00"
# cloudsql_deletion_protection = true
# synapse_db_name             = "synapse"
# synapse_db_user             = "synapse_app"
# matrix_auth_db_name         = "mas"
# matrix_auth_db_user         = "mas_app"
# analytics_dataset_id        = "ess_matrix_cdc"
# analytics_location          = "us-central1"
# datastream_stream_id        = "ess-postgres-to-bq"
```

### Bootstrap remote state

```bash
./init-remote-state.sh \
  --project ess-one-shot \
  --bucket ess-one-shot-tfstate \
  --location us

tofu init -backend-config=backend.hcl
```

The script creates (or validates) the GCS bucket, enables versioning, applies uniform bucket-level access, and writes `backend.hcl` with the supplied settings. Pass `--state-admin you@example.com` or a service account email to grant bucket access for OpenTofu.

### Deploy

```bash

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

During `apply` OpenTofu enables the required APIs, creates an Autopilot cluster, reserves a global static IP, provisions a Google-managed certificate, builds a private Cloud SQL for PostgreSQL instance (with `synapse`/`mas` databases plus per-service users), writes Kubernetes secrets that surface those credentials to the chart, binds Workload Identity service accounts, installs the ESS Helm release with `postgres.enabled=false`, creates the BigQuery dataset, and seeds Datastream connection profiles/streams (created in the paused `NOT_STARTED` state so you can verify connectivity). DNS records (in `dns_project_id` when provided) are published for:

- `chat.${domain}`
- `admin.${domain}`
- `matrix.${domain}`
- `account.${domain}`
- `rtc.${domain}`

All five hostnames share the reserved static IP, so as soon as DNS propagates the ManagedCertificate will transition to `Active` (typically within 15 minutes).

Monitor `kubectl get ingress -n ess -w` until the IP shows up and watch the managed certificate become `Active`. Run `tofu output` to capture the Cloud SQL connection information, generated service account emails, Kubernetes secret names, and Datastream stream IDs for follow-up tasks.

### Post-deploy database + CDC checklist

1. **Grant replication privileges once.** Connect as the `postgres` admin (for example `gcloud sql connect ${CLOUDSQL_INSTANCE} --user=postgres --project ${PROJECT_ID}`) and run:

   ```sql
   ALTER ROLE datastream_replica WITH REPLICATION;
   GRANT CONNECT ON DATABASE synapse TO datastream_replica;
   GRANT CONNECT ON DATABASE mas TO datastream_replica;
   GRANT USAGE ON SCHEMA public TO datastream_replica;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream_replica;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO datastream_replica;
   ```

   Repeat the `GRANT` statements for any additional schemas the applications create (e.g. `synapse_main`, `mas_public`). This is only required after the initial deployment or when new schemas are added.

2. **Start Datastream ingestion.** Streams launch in `NOT_STARTED`. After validating database grants, start them:

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

   > Datastream needs private connectivity to reach the Cloud SQL private IP. If you have not yet approved a Private Service Connect or VPC peering attachment for Datastream, create it first (the streams were created with `create_without_validation = true`, so you can fill in the networking pieces before turning them on).

   Monitor `gcloud datastream streams describe ... --location ...` for `state: RUNNING` and confirm the initial snapshot completes.

3. **Validate BigQuery objects.** The dataset configured via `analytics_dataset_id` receives tables per source schema. Query a few tables (for example `SELECT COUNT(*) ...`) to confirm change events arrive.

### Cleanup

```bash
tofu destroy -var-file=tofu.tfvars
```

This tears down the Helm release, DNS records, Cloud SQL instance, Datastream connection profiles/streams, the BigQuery dataset, and the Autopilot cluster. BigQuery tables populated by Datastream are not deleted automatically; remove them manually if desired.

### Infracost

```bash
# Terraform variables can be set using --terraform-var-file or --terraform-var
infracost breakdown --path .
```
