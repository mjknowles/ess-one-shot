#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${OIDC_EXAMPLE_NAMESPACE:-ess}"
GOOGLE_CLIENT_ID="${GOOGLE_OIDC_CLIENT_ID:-${OIDC_EXAMPLE_CLIENT_ID:-}}"
GOOGLE_CLIENT_SECRET="${GOOGLE_OIDC_CLIENT_SECRET:-${OIDC_EXAMPLE_CLIENT_SECRET:-}}"
if [[ -z "${GOOGLE_CLIENT_ID}" || -z "${GOOGLE_CLIENT_SECRET}" ]]; then
  echo "Set GOOGLE_OIDC_CLIENT_ID and GOOGLE_OIDC_CLIENT_SECRET before running Tilt." >&2
  exit 1
fi
PROVIDER_ID="${MAS_GOOGLE_PROVIDER_ID:-01HFS6S2SVAR7Y7QYMZJ53ZAGZ}"
PROVIDER_NAME="${MAS_GOOGLE_PROVIDER_NAME:-Google}"
APP_CLIENT_ID="${MAS_OAUTH_CLIENT_ID:-01J44RKQYM4G3TNVANTMTDYTX6}"
APP_CLIENT_SECRET="${MAS_OAUTH_CLIENT_SECRET:-dev-mas-oauth-client-secret-change-me}"
APP_PUBLIC_BASE_URL="${OIDC_EXAMPLE_PUBLIC_BASE_URL:-https://oidc.ess.localhost}"

tmpfile="$(mktemp /tmp/mas-google-oidc-values.XXXXXX.yaml)"
trap 'rm -f "${tmpfile}"' EXIT

cat >"${tmpfile}" <<EOF
matrixAuthenticationService:
  additional:
    1-googleOidc:
      config: |
        passwords:
          enabled: false
        account:
          password_registration_enabled: false
        upstream_oauth2:
          providers:
            - id: "${PROVIDER_ID}"
              human_name: "${PROVIDER_NAME}"
              brand_name: "google"
              issuer: "https://accounts.google.com"
              token_endpoint_auth_method: "client_secret_post"
              client_id: "${GOOGLE_CLIENT_ID}"
              client_secret: "${GOOGLE_CLIENT_SECRET}"
              scope: "openid profile email"
              claims_imports:
                skip_confirmation: true
                localpart:
                  action: require
                  template: "{{ (user.email | split('@'))[0] }}"
                  on_conflict: set
                displayname:
                  action: force
                  template: "{{ user.name }}"
                email:
                  action: force
                  template: "{{ user.email }}"
                  set_email_verification: always
                account_name:
                  template: "{{ user.email }}"
        clients:
          - client_id: "${APP_CLIENT_ID}"
            client_auth_method: client_secret_basic
            client_secret: "${APP_CLIENT_SECRET}"
            redirect_uris:
              - "${APP_PUBLIC_BASE_URL%/}/callback"
EOF

if helm status ess --namespace "${NAMESPACE}" >/dev/null 2>&1; then
  helm upgrade ess oci://ghcr.io/element-hq/ess-helm/matrix-stack \
    --namespace "${NAMESPACE}" \
    --reuse-values \
    --wait \
    -f "${tmpfile}"
else
  helm upgrade --install ess oci://ghcr.io/element-hq/ess-helm/matrix-stack \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --wait \
    -f ../local/ess-values/ingress.yaml \
    -f ../local/ess-values/letsencrypt.yaml \
    -f ../local/ess-values/mas.yaml \
    -f ../local/ess-values/rtc.yaml \
    -f ../local/ess-values/synapse.yaml \
    -f "${tmpfile}"
fi
