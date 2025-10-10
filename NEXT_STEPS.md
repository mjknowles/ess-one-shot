## Local

1. Run ./infra/local/launch-local.sh and monitor kubectl get pods -n ess until everything is ready.
2. Create your first user with kubectl exec -n ess -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user.
3. Decide if you need cert-manager/TLS customization before exposing the endpoints more broadly.
