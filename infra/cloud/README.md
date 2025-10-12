# GCP Quickstart

Follow these steps to bring the Element Server Suite online on GKE Autopilot with Cloud SQL and Datastream.

## Prerequisites

- [OpenTofu 1.6+](https://opentofu.org/)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) with `gcloud auth application-default login` (or a service-account key exported in `GOOGLE_APPLICATION_CREDENTIALS`)
- [Helm 3.8+](https://helm.sh/)
- IAM access to create/modify GKE, Cloud SQL, Datastream, BigQuery, DNS, and Secret Manager resources in the target project
- A Cloud DNS managed zone that already serves the domain or subdomain you plan to dedicate to ESS

## 1. Set your inputs

Create `infra/cloud/tofu.tfvars` with the project, DNS, and ACME details:

```hcl
project_id     = "ess-one-shot"
domain         = "mjknowles.dev"
dns_zone_name  = "mjknowles-dev-zone"
# dns_project_id = "dns-infra-474704"  # set only if the DNS zone lives in another project
acme_email     = "you@example.com"
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

## 3. Deploy

```bash
# One-time: enable core APIs and create the Autopilot cluster
tofu apply \
  -target=google_project_service.compute \
  -target=google_project_service.container \
  -target=google_container_cluster.autopilot \
  -var-file=tofu.tfvars -auto-approve

# One-time: create CRDs
tofu apply -target=helm_release.cert_manager -var-file=tofu.tfvars -auto-approve
# If it times out
tofu apply -target=helm_release.cert_manager -var-file=tofu.tfvars -auto-approve -refresh-only

# Full rollout for everything else
tofu plan -var-file=tofu.tfvars
tofu apply -var-file=tofu.tfvars -auto-approve
```

Wait for the command to finish. Terraform will reserve the ingress IP, publish DNS for your ESS subdomains, install cert-manager, and request Let's Encrypt certificates via DNS-01. Use `kubectl get ingress -n ess -w` to watch for the load-balancer status.

Configure your kubeconfig as soon as the Autopilot cluster is created (no need to wait for the full `tofu apply` to finish):

```bash
gcloud container clusters get-credentials "ess-one-shot-gke" \
  --region "us-central1" \
  --project ess-one-shot
```

Update the cluster name or region if you customized them in `infra/cloud/locals.tf`. `kubectl config current-context` should now point at the Autopilot cluster so you can tail Helm resources immediately.

## 4. After apply

- Capture the outputs you need for follow-up tasks: `tofu output`.
- TLS is provisioned automatically by cert-manager. Watch `kubectl describe certificate ess-wildcard-certificate -n ess` for status; the `ingress-nginx` load balancer presents the issued certificate once it reports `Ready: True`.
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

## 5. Tear down (when you are done)

```bash
tofu destroy -target=helm_release.ess -var-file=tofu.tfvars
tofu destroy -refresh=false -var-file=tofu.tfvars
```

Remove any leftover Cloud SQL data or BigQuery tables manually if you no longer need them.

## Troubleshooting Helm Deploy

The playbook:

- Let the original tofu apply finish or fail. If Helm gets wedged and needs tearing down, run `tofu destroy -target=helm_release.ess -var-file=tofu.tfvars` so Terraform records the delete, instead of helm uninstall.
- After fixing the chart values, rerun the full `tofu apply -var-file=tofu.tfvars -auto-approve`; Terraform will reinstall the
  release cleanly.
- If you do ever remove something manually, immediately reconcile state (tofu state rm helm_release.ess or rerun destroy)
  so Terraform isn’t left holding a pointer to something that’s gone.
- `helm uninstall ess -n ess`
