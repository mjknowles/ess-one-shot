# ess-one-shot

Spin up a local Kubernetes cluster and deploy the Element Server Suite (ESS) community Helm chart in one shot.

## Local Deployment

### Prerequisites

- Docker (or another container runtime that kind can talk to)
- [kind](https://kind.sigs.k8s.io/) (pre-installed as requested)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (pre-installed as requested)
- [Helm 3.8+](https://helm.sh/) (required for OCI registry support)

### Quick start

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

### Customising the launch

```
./launch-local.sh --help
```

- `--domain your.domain.test` – use custom hostnames (`chat.your.domain.test`, etc.). Be sure to route them to `127.0.0.1` (edit `/etc/hosts` or configure DNS) and browse via `https://…:8443`.
- `--values-file /path/to/values.yaml` – point at your own chart values. Use `--force-values` to overwrite the generated file.
- `--skip-cluster` – deploy into an already-selected Kubernetes context (no kind cluster creation or ingress install).
- `-- <helm args>` – pass additional flags straight to `helm upgrade --install`. Example: `./launch-local.sh -- --set synapse.resources.requests.cpu=1`.

The script reuses the generated values file on subsequent runs unless `--force-values` is supplied, making it easy to tweak hostnames or append additional overrides alongside `helm`’s `-f` or `--set` options.

### What happens next?

- ESS disables open registration. Create an initial user once the pods are up:
  ```
  kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user
  ```
- TLS is self-signed by default. For proper certificates, follow the [cert-manager instructions in the upstream README](https://github.com/element-hq/ess-helm#preparing-the-environment).
- Review the [official ESS Helm documentation](https://github.com/element-hq/ess-helm#installation) for advanced configuration (external PostgreSQL, TLS, storage, etc.).

### Tearing it down

- Remove the release: `helm uninstall ess -n ess`
- Delete the kind cluster when you are done: `kind delete cluster --name ess-one-shot`

All generated configuration is kept in `.ess-values/` so you can inspect or reuse it between runs.

## GCP (GKE) Deployment with OpenTofu

Use the OpenTofu configuration in `./opentofu` to spin up an Autopilot GKE cluster, configure Google-managed HTTPS ingress, and deploy the Element Server Suite with a single apply.

### Prerequisites (GCP)

- [OpenTofu 1.6+](https://opentofu.org/)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) authenticated for your project (`gcloud auth application-default login` or a service-account key in `GOOGLE_APPLICATION_CREDENTIALS`)
- IAM permissions to enable `compute.googleapis.com` / `container.googleapis.com`, create Autopilot clusters, and manage load balancers
- [Helm 3.8+](https://helm.sh/) (required by the Helm provider)
- Public DNS control for the domain you plan to serve (you will point five records at the load balancer IP after apply)

### Configure once

Create `opentofu/tofu.tfvars` with the only required inputs:

```hcl
project_id = "my-gcp-project"
domain     = "example.com"
# region = "us-central1"   # optional override
```

### Deploy

```bash
cd opentofu
tofu init
tofu plan  -var-file=tofu.tfvars          # optional review
tofu apply -var-file=tofu.tfvars          # creates the cluster + deploys ESS
```

During `apply` OpenTofu will enable the necessary APIs, create an Autopilot cluster, provision a `ManagedCertificate`, and install the ESS Helm chart with Ingress resources for:

- `chat.${domain}`
- `admin.${domain}`
- `matrix.${domain}`
- `account.${domain}`
- `rtc.${domain}`

Watch the ingress until it has an external IP:

```bash
kubectl get ingress -n ess -w
```

Update your DNS A records for the five hostnames to the reported IP. Google-managed certificates usually become `Active` once DNS propagates (up to ~15 minutes).

### Cleanup (GCP)

From the `opentofu/` directory:

```bash
tofu destroy -var-file=tofu.tfvars
```

This tears down the Helm release and Autopilot cluster. Remember to remove any DNS records you added manually.
