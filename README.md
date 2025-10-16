## ess-one-shot

Pick the path that matches your goal:

- `infra/local` – spin up ESS on a local kind cluster for fast experiments.
- `infra/cloud` – provision the managed GKE stack (OpenTofu + GCP).

See `docs/` for supporting guides like domain registration.

### Connect `kubectl` to the GKE cluster

Run these after `terraform apply` finishes provisioning the cluster:

1. `gcloud auth login` (or use the service account key you normally work with) so the CLI can talk to GCP.
2. `gcloud config set project <PROJECT_ID>` and `gcloud config set compute/zone <ZONE>` to point at the project and zone the cluster lives in.
3. `gcloud container clusters get-credentials ess-one-shot-gke` to pull the cluster credentials into your local kubeconfig. Add `--zone` or `--region` if it differs from your defaults.
4. Verify the connection with `kubectl get nodes`.

### Handy URLs

- `https://chat.mjknowles.dev` – Element Web client
- `https://matrix.mjknowles.dev/_matrix/client/versions` – quick Synapse health check
- `https://mjknowles.dev/.well-known/matrix/client` – well-known delegation payload
- `https://mjknowles.dev/.well-known/matrix/server` – homeserver discovery response
- `https://account.mjknowles.dev` – Matrix Authentication Service (MAS) UI
