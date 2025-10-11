## Local

1. Run ./infra/local/launch-local.sh and monitor kubectl get pods -n ess until everything is ready.
2. Create your first user with kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user.
3. Decide if you need cert-manager/TLS customization before exposing the endpoints more broadly.

## Cloud

1. Update Terraform to provision its own VPC and subnets for the ESS stack instead of using `default`; reference that network from every dependent resource so `tofu destroy` can tear the peering and reserved ranges down automatically.
2. Keep all Service Networking consumers (Cloud SQL, future private services) inside the same OpenTofu stack and favor `tofu destroy -target=helm_release.ess` (plus other Kubernetes resources) before deleting the cluster to avoid provider auth failures during teardown.
3. Document and follow a destroy order in the repo so manual console deletes aren’t needed; if you must delete out-of-band, immediately run `tofu state rm …` for the affected resources to keep state tidy.
