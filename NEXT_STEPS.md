## Local

1. Run ./infra/local/launch-local.sh and monitor kubectl get pods -n ess until everything is ready.
2. Create your first user with kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user.
3. Decide if you need cert-manager/TLS customization before exposing the endpoints more broadly.

## Cloud

1. Stand up a managed PostgreSQL instance (Cloud SQL) in the ESS project: enable the Cloud SQL Admin API, select a PostgreSQL 15+ tier that supports logical replication, place it on a private VPC, and create `synapse`/`mas` databases and service accounts.
2. Wire GKE to Cloud SQL: enable the Cloud SQL connections add-on or deploy the Cloud SQL Auth Proxy, grant the GKE workload identity access to connect, and surface the instance connection string and credentials to the cluster (Secret Manager + CSI driver or Kubernetes secrets).
3. Reconfigure the Helm release: disable `postgres.enabled`, populate the `synapse.postgres` and `matrixAuthenticationService.postgres` blocks with the Cloud SQL host, port, db names, and credentials, and plumb those overrides into Terraform (e.g., new values file/secret data sources).
4. Enable change data capture: set the Cloud SQL flags for logical decoding (`cloudsql.logical_decoding=on`, `max_replication_slots`, `max_wal_senders`), add a publication for the Synapse and MAS schemas, and open a replication user with minimal permissions.
5. Stream into BigQuery: create Datastream connection profiles for Cloud SQL and BigQuery, configure a stream that targets a dedicated dataset/table prefix, and verify initial snapshot plus ongoing CDC ingestion.
6. Update Terraform to own the new pieces end-to-end (Cloud SQL instance, IAM bindings, secrets, Datastream resources) and add any required firewall or service networking resources before the next `tofu apply`.
