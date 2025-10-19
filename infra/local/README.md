## Local Deployment

Spin up a local Kubernetes cluster and deploy the Element Server Suite (ESS) community Helm chart in one shot.

### Prerequisites

- Docker (or another container runtime that kind can talk to)
- [kind](https://kind.sigs.k8s.io/) (pre-installed as requested)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (pre-installed as requested)
- [Helm 3.8+](https://helm.sh/) (required for OCI registry support)

Optional but nice:

- infracost (https://www.infracost.io/docs/#quick-start)

### Quick start

```bash
./infra/local/launch-local.sh
```

The script will:

- Verify that `kind`, `kubectl`, and `helm` are available.
- Create or reuse a `kind` cluster named `ess-one-shot` (one control-plane + one worker node) and expose ingress ports `80`/`443` to your host.
- Generate `.ess-values/hostnames.yaml` with a set of hostnames that point at `127-0-0-1.nip.io` (no `/etc/hosts` edits required).
- Run `helm upgrade --install` against `oci://ghcr.io/element-hq/ess-helm/matrix-stack` in the `ess` namespace and wait for resources to become ready.

Once pods settle, the endpoints will be available through ingress on the following HTTPS hostnames (self-signed certificates unless you customise TLS):

- Element Web: `https://chat.127-0-0-1.nip.io:8443`
- Admin console: `https://admin.127-0-0-1.nip.io:8443`
- Synapse (Matrix): `https://matrix.127-0-0-1.nip.io:8443`
- Matrix Authentication Service: `https://account.127-0-0-1.nip.io:8443`
- Matrix RTC: `https://rtc.127-0-0-1.nip.io:8443`

### Customising the launch

```bash
./infra/local/launch-local.sh --help
```

- `--domain your.domain.test` – use custom hostnames (`chat.your.domain.test`, etc.). Be sure to route them to `127.0.0.1` (edit `/etc/hosts` or configure DNS) and browse via `https://…:8443`.
- `--values-file /path/to/values.yaml` – point at your own chart values. Use `--force-values` to overwrite the generated file.
- `--skip-cluster` – deploy into an already-selected Kubernetes context (no kind cluster creation or ingress install).
- `-- <helm args>` – pass additional flags straight to the final `helm upgrade --install`. Example: `./infra/local/launch-local.sh -- --set synapse.resources.requests.cpu=1`.

The script reuses the generated values file on subsequent runs unless `--force-values` is supplied, making it easy to tweak hostnames or append additional overrides alongside `helm`’s `-f` or `--set` options.

### What happens next?

- ESS disables open registration. Create an initial user once the pods are up:
  ```bash
  kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user
  ```
- TLS is self-signed by default. For proper certificates, follow the [cert-manager instructions in the upstream README](https://github.com/element-hq/ess-helm#preparing-the-environment).
- Review the [official ESS Helm documentation](https://github.com/element-hq/ess-helm#installation) for advanced configuration (external PostgreSQL, TLS, storage, etc.).

### Tearing it down

- Remove the release: `helm uninstall ess -n ess`
- Delete the kind cluster when you are done: `kind delete cluster --name ess-one-shot`

All generated configuration is kept in `.ess-values/` so you can inspect or reuse it between runs.
