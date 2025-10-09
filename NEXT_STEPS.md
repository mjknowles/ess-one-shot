## Local

1. Run ./launch-local.sh and monitor kubectl get pods -n ess until everything is ready.
2. Create your first user with kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user.
3. Decide if you need cert-manager/TLS customization before exposing the endpoints more broadly.

## GCP

1. Install and authenticate the Google Cloud CLI, then run ./launch-gcp.sh --project <id> --region <region>
   --domain <your-domain> once DNS/TLS details are ready.
2. Watch kubectl get svc -n ingress-nginx ess-ingress-ingress-nginx-controller -w and update DNS/TLS values
   before rerunning with --force-values if needed.
