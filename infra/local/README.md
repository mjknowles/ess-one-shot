## Local Deployment

Spin up a local Kubernetes cluster and deploy the Element Server Suite (ESS) community Helm chart in one shot.

### Prerequisites

- Docker (or another container runtime that kind can talk to)
- [kind](https://kind.sigs.k8s.io/) (pre-installed as requested)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (pre-installed as requested)
- [Helm 3.8+](https://helm.sh/) (required for OCI registry support)
- Update your hosts file with:

```
127.0.0.1 chat.ess.localhost
127.0.0.1 admin.ess.localhost
127.0.0.1 matrix.ess.localhost
127.0.0.1 account.ess.localhost
127.0.0.1 rtc.ess.localhost
```

Optional but nice:

- infracost (https://www.infracost.io/docs/#quick-start)

### Quick start

```bash
./infra/local/launch-local.sh
kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user
```

### Tear down

```bash
kind delete cluster --name ess-one-shot
./remove-ca-trust.sh
```
