#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-apply}"
NAMESPACE="${OIDC_EXAMPLE_NAMESPACE:-ess}"
CM_NAME="ess-matrix-authentication-service"
BACKUP_NAME="oidc-example-mas-backup"
MARKER_NAME="oidc-example-mas-overlay"

GOOGLE_CLIENT_ID="${GOOGLE_OIDC_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${GOOGLE_OIDC_CLIENT_SECRET:-}"
PROVIDER_ID="${MAS_GOOGLE_PROVIDER_ID:-01HFS6S2SVAR7Y7QYMZJ53ZAGZ}"
PROVIDER_NAME="${MAS_GOOGLE_PROVIDER_NAME:-Google}"
MAS_PUBLIC_BASE_URL="${MAS_PUBLIC_BASE_URL:-https://localhost:8443}"
APP_CLIENT_ID="${MAS_OAUTH_CLIENT_ID:-01J44RKQYM4G3TNVANTMTDYTX6}"
APP_CLIENT_SECRET="${MAS_OAUTH_CLIENT_SECRET:-dev-mas-oauth-client-secret-change-me}"
APP_PUBLIC_BASE_URL="${OIDC_EXAMPLE_PUBLIC_BASE_URL:-https://oidc.ess.localhost}"

require_env() {
  local name="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    echo "Set ${name} before running Tilt." >&2
    exit 1
  fi
}

restart_mas() {
  sleep 2
  kubectl -n "${NAMESPACE}" rollout restart deploy/ess-matrix-authentication-service >&2
}

patch_mas_config() {
  local content="$1"
  local patch_file
  patch_file="$(mktemp "${TMPDIR:-/tmp}/mas-config-patch.XXXXXX")"
  python3 - "${content}" >"${patch_file}" <<'PY'
import json
import sys

print(json.dumps({
    "data": {
        "mas-config-overrides.yaml": sys.argv[1],
    },
}))
PY
  kubectl -n "${NAMESPACE}" patch cm "${CM_NAME}" \
    --field-manager=helm \
    --type merge \
    --patch-file "${patch_file}" >&2
  rm -f "${patch_file}"
}

backup_current_config() {
  if kubectl -n "${NAMESPACE}" get secret "${BACKUP_NAME}" >/dev/null 2>&1; then
    return
  fi

  local current
  current="$(kubectl -n "${NAMESPACE}" get cm "${CM_NAME}" -o 'jsonpath={.data.mas-config-overrides\.yaml}')"
  kubectl -n "${NAMESPACE}" create secret generic "${BACKUP_NAME}" \
    --from-literal=mas-config-overrides.yaml="${current}" \
    --dry-run=client \
    -o yaml | kubectl apply -f - >&2
}

base_config() {
  if kubectl -n "${NAMESPACE}" get secret "${BACKUP_NAME}" >/dev/null 2>&1; then
    kubectl -n "${NAMESPACE}" get secret "${BACKUP_NAME}" -o 'jsonpath={.data.mas-config-overrides\.yaml}' | base64 -d
  else
    kubectl -n "${NAMESPACE}" get cm "${CM_NAME}" -o 'jsonpath={.data.mas-config-overrides\.yaml}'
  fi
}

build_overlay_config() {
  local current="$1"
  MAS_CONFIG="${current}" \
  MAS_PUBLIC_BASE_URL="${MAS_PUBLIC_BASE_URL}" \
  PROVIDER_ID="${PROVIDER_ID}" \
  PROVIDER_NAME="${PROVIDER_NAME}" \
  GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}" \
  GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET}" \
  APP_CLIENT_ID="${APP_CLIENT_ID}" \
  APP_CLIENT_SECRET="${APP_CLIENT_SECRET}" \
  APP_CALLBACK_URL="${APP_PUBLIC_BASE_URL%/}/callback" \
  python3 - <<'PY'
import json
import os
import re

data = os.environ["MAS_CONFIG"]
public_base = json.dumps(os.environ["MAS_PUBLIC_BASE_URL"])

if re.search(r'(?m)^  public_base: .+$', data):
    data = re.sub(r'(?m)^  public_base: .+$', f"  public_base: {public_base}", data, count=1)
elif re.search(r'(?m)^http:\s*$', data):
    data = re.sub(r'(?m)^http:\s*$', f"http:\n  public_base: {public_base}", data, count=1)
else:
    data = f"http:\n  public_base: {public_base}\n" + data

def q(name):
    return json.dumps(os.environ[name])

overlay = f"""

passwords:
  enabled: false
account:
  password_registration_enabled: false
upstream_oauth2:
  providers:
    - id: {q("PROVIDER_ID")}
      human_name: {q("PROVIDER_NAME")}
      brand_name: "google"
      issuer: "https://accounts.google.com"
      token_endpoint_auth_method: "client_secret_post"
      client_id: {q("GOOGLE_CLIENT_ID")}
      client_secret: {q("GOOGLE_CLIENT_SECRET")}
      scope: "openid profile email"
      claims_imports:
        skip_confirmation: true
        localpart:
          action: require
          template: "{{{{ (user.email | split('@'))[0] }}}}"
          on_conflict: set
        displayname:
          action: force
          template: "{{{{ user.name }}}}"
        email:
          action: force
          template: "{{{{ user.email }}}}"
          set_email_verification: always
        account_name:
          template: "{{{{ user.email }}}}"
clients:
  - client_id: {q("APP_CLIENT_ID")}
    client_auth_method: client_secret_basic
    client_secret: {q("APP_CLIENT_SECRET")}
    redirect_uris:
      - {q("APP_CALLBACK_URL")}
"""

print(data.rstrip() + overlay)
PY
}

emit_marker() {
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${MARKER_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${MARKER_NAME}
data:
  status: applied
EOF
}

apply_marker() {
  emit_marker | kubectl apply -f - -o yaml
}

apply_overlay() {
  require_env GOOGLE_OIDC_CLIENT_ID "${GOOGLE_CLIENT_ID}"
  require_env GOOGLE_OIDC_CLIENT_SECRET "${GOOGLE_CLIENT_SECRET}"

  backup_current_config
  local current patched
  current="$(base_config)"
  patched="$(build_overlay_config "${current}")"
  patch_mas_config "${patched}"
  restart_mas
  apply_marker
}

delete_overlay() {
  if kubectl -n "${NAMESPACE}" get secret "${BACKUP_NAME}" >/dev/null 2>&1; then
    local original
    original="$(kubectl -n "${NAMESPACE}" get secret "${BACKUP_NAME}" -o 'jsonpath={.data.mas-config-overrides\.yaml}' | base64 -d)"
    patch_mas_config "${original}"
    kubectl -n "${NAMESPACE}" delete secret "${BACKUP_NAME}" >&2
    restart_mas
  fi
  kubectl -n "${NAMESPACE}" delete cm "${MARKER_NAME}" --ignore-not-found >&2
}

case "${ACTION}" in
  apply)
    apply_overlay
    ;;
  delete)
    delete_overlay
    ;;
  *)
    echo "Usage: $0 apply|delete" >&2
    exit 2
    ;;
esac
