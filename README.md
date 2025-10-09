# ess-one-shot

Spin up a local Kubernetes cluster and deploy the Element Server Suite (ESS) community Helm chart in one shot.

## Prerequisites

- Docker (or another container runtime that kind can talk to)
- [kind](https://kind.sigs.k8s.io/) (pre-installed as requested)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (pre-installed as requested)
- [Helm 3.8+](https://helm.sh/) (required for OCI registry support)

## Quick start

```bash
./launch-local.sh
```

The script will:
- Verify that `kind`, `kubectl`, and `helm` are available.
- Create or reuse a `kind` cluster named `ess-one-shot` (one control-plane + one worker node) and expose ingress ports `8080`/`8443` to your host.
- Install the [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) controller tailored for `kind`.
- Generate `.ess-values/hostnames.yaml` with a set of hostnames that point at `127-0-0-1.nip.io` (no `/etc/hosts` edits required).
- Run `helm upgrade --install` against `oci://ghcr.io/element-hq/ess-helm/matrix-stack` in the `ess` namespace and wait for resources to become ready.

Once pods settle, the endpoints will be available through ingress on the following HTTPS hostnames (self-signed certificates unless you customise TLS):

- Element Web: `https://chat.127-0-0-1.nip.io:8443`
- Admin console: `https://admin.127-0-0-1.nip.io:8443`
- Synapse (Matrix): `https://matrix.127-0-0-1.nip.io:8443`
- Matrix Authentication Service: `https://account.127-0-0-1.nip.io:8443`
- Matrix RTC: `https://rtc.127-0-0-1.nip.io:8443`

## Customising the launch

```
./launch-local.sh --help
```

- `--domain your.domain.test` – use custom hostnames (`chat.your.domain.test`, etc.). Be sure to route them to `127.0.0.1` (edit `/etc/hosts` or configure DNS) and browse via `https://…:8443`.
- `--values-file /path/to/values.yaml` – point at your own chart values. Use `--force-values` to overwrite the generated file.
- `--skip-cluster` – deploy into an already-selected Kubernetes context (no kind cluster creation or ingress install).
- `-- <helm args>` – pass additional flags straight to `helm upgrade --install`. Example: `./launch-local.sh -- --set synapse.resources.requests.cpu=1`.

The script reuses the generated values file on subsequent runs unless `--force-values` is supplied, making it easy to tweak hostnames or append additional overrides alongside `helm`’s `-f` or `--set` options.

## What happens next?

- ESS disables open registration. Create an initial user once the pods are up:
  ```
  kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user
  ```
- TLS is self-signed by default. For proper certificates, follow the [cert-manager instructions in the upstream README](https://github.com/element-hq/ess-helm#preparing-the-environment).
- Review the [official ESS Helm documentation](https://github.com/element-hq/ess-helm#installation) for advanced configuration (external PostgreSQL, TLS, storage, etc.).

## Tearing it down

- Remove the release: `helm uninstall ess -n ess`
- Delete the kind cluster when you are done: `kind delete cluster --name ess-one-shot`

All generated configuration is kept in `.ess-values/` so you can inspect or reuse it between runs.

## GCP (GKE) deployment

`launch-gcp.sh` provisions a Google Kubernetes Engine cluster and deploys ESS.

### Prerequisites (GCP)

- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`gcloud`) authenticated against your project
- IAM permissions to enable `container.googleapis.com` and `compute.googleapis.com`, create clusters, and manage load balancers
- Helm 3.8+ and kubectl (the script reuses the same binaries as the local workflow)
- Optional: a reserved static IP address, DNS zone, and TLS materials (the script accepts them when ready)

### Launching on GKE

```bash
./launch-gcp.sh --project <gcp-project-id> --region us-central1 --domain matrix.example.com
```

The script will:
- Enable the Container and Compute APIs (no-op if already enabled).
- Create or reuse a GKE standard cluster (`--zone` for zonal, `--autopilot` to switch modes) and fetch kubeconfig credentials.
- Install the `ingress-nginx` controller as a LoadBalancer service (add `--lb-ip-address` to pin a static IP).
- Generate `.ess-values/gcp-hostnames.yaml` with your ESS hostnames, ingress defaults, and optional TLS secret.
- Run `helm upgrade --install` with those values in the `ess` namespace and wait for resources to become ready.

Follow the load balancer assignment with:

```bash
kubectl get svc -n ingress-nginx ess-ingress-ingress-nginx-controller -w
```

Once the external IP is known, point your DNS records (`chat.`, `admin.`, `matrix.`, `account.`, `rtc.`) to that address. Re-run the script with `--force-values` when you are ready to:

- Switch domains: `--domain your.new.domain`
- Provide TLS: `--tls-secret existing-k8s-secret` or `--disable-tls` to serve HTTP temporarily
- Override Helm configuration: append `-- --set key=value` or `-- -f extra-values.yaml`

### Cleanup (GCP)

- Remove the Helm release: `helm uninstall ess -n ess`
- Delete the ingress controller: `helm uninstall ess-ingress -n ingress-nginx`
- Delete the cluster when finished: `gcloud container clusters delete ess-one-shot-gke --region us-central1`
- Release any reserved addresses or DNS records you created
