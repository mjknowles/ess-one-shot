## Local

1. Run ./launch-local.sh and monitor kubectl get pods -n ess until everything is ready.
2. Create your first user with kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user.
3. Decide if you need cert-manager/TLS customization before exposing the endpoints more broadly.

## GCP

1. Install and authenticate the Google Cloud CLI, then configure `opentofu/tofu.tfvars` with `project_id` and `domain` (override `region` if you prefer). Run `cd opentofu && tofu init && tofu apply -var-file=tofu.tfvars`.
2. Watch `kubectl get ingress -n ess -w`, add DNS records for the reported IP, and reapply if you change the base domain later.
