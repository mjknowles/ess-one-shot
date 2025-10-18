#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TF_DIR="${SCRIPT_DIR}/base"
HELM_TIMEOUT="15m"

usage() {
  cat <<'EOF'
Deploy the ESS Helm charts using values sourced from OpenTofu outputs.

Usage:
  deploy-charts.sh [--tf-dir PATH] [--skip-repo-update]

Options:
  --tf-dir PATH         Directory that contains the OpenTofu configuration (default: infra/cloud)
  --skip-repo-update    Skip running `helm repo update`
  -h, --help            Show this help message
EOF
}

require_binary() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: $bin is required but not installed or not on PATH" >&2
    exit 1
  fi
}

SKIP_REPO_UPDATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tf-dir)
      if [[ $# -lt 2 ]]; then
        echo "error: --tf-dir requires a path argument" >&2
        exit 1
      fi
      if [[ ! -d "$2" ]]; then
        echo "error: --tf-dir path does not exist: $2" >&2
        exit 1
      fi
      TF_DIR=$(cd "$2" && pwd)
      shift 2
      ;;
    --skip-repo-update)
      SKIP_REPO_UPDATE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_binary tofu
require_binary jq
require_binary helm
require_binary kubectl

TF_OUTPUT_JSON=$(tofu -chdir="${TF_DIR}" output -json)

tf_output_string() {
  local expr="$1"
  jq -er ".$expr | (if type == \"string\" then . else (.|tostring) end)" <<<"${TF_OUTPUT_JSON}"
}

# Extract required values
ESS_NAMESPACE=$(tf_output_string "ess_namespace.value")
HOST_ADMIN=$(tf_output_string "hosts.value.admin")
HOST_CHAT=$(tf_output_string "hosts.value.chat")
HOST_MATRIX=$(tf_output_string "hosts.value.matrix")
HOST_ACCOUNT=$(tf_output_string "hosts.value.account")
HOST_RTC=$(tf_output_string "hosts.value.rtc")
BASE_DOMAIN=$(tf_output_string "base_domain.value")
GATEWAY_IP=$(tf_output_string "gateway_ip_address.value")
CLOUDSQL_HOST=$(tf_output_string "cloudsql_private_ip.value")
SYNAPSE_SECRET_NAME=$(tf_output_string "synapse_database_secret_name.value")
MAS_SECRET_NAME=$(tf_output_string "matrix_auth_database_secret_name.value")
SYNAPSE_SA_NAME=$(tf_output_string "synapse_service_account_name.value")
SYNAPSE_SA_EMAIL=$(tf_output_string "synapse_service_account_email.value")
MAS_SA_NAME=$(tf_output_string "matrix_auth_service_account_name.value")
MAS_SA_EMAIL=$(tf_output_string "matrix_auth_service_account_email.value")
SYNAPSE_DB_USER=$(tf_output_string "synapse_database_user.value")
SYNAPSE_DB_NAME=$(tf_output_string "synapse_database_name.value")
MAS_DB_USER=$(tf_output_string "matrix_auth_database_user.value")
MAS_DB_NAME=$(tf_output_string "matrix_auth_database_name.value")

MAUTRIX_SIGNAL_NAMESPACE=${MAUTRIX_SIGNAL_NAMESPACE:-nss}
MAUTRIX_SIGNAL_RELEASE_NAME=${MAUTRIX_SIGNAL_RELEASE_NAME:-mautrix-signal}
MAUTRIX_SIGNAL_REPLICA_COUNT=${MAUTRIX_SIGNAL_REPLICA_COUNT:-1}
MAUTRIX_SIGNAL_CONFIG_PATH=${MAUTRIX_SIGNAL_CONFIG_PATH:-${SCRIPT_DIR}/mautrix-signal/config/config.yaml}
MAUTRIX_SIGNAL_REGISTRATION_PATH=${MAUTRIX_SIGNAL_REGISTRATION_PATH:-${SCRIPT_DIR}/mautrix-signal/config/registration.yaml}
MAUTRIX_SIGNAL_IMAGE_REPOSITORY=${MAUTRIX_SIGNAL_IMAGE_REPOSITORY:-dock.mau.dev/mautrix/signal}
MAUTRIX_SIGNAL_IMAGE_TAG=${MAUTRIX_SIGNAL_IMAGE_TAG:-v0.8.6}
MAUTRIX_SIGNAL_IMAGE_PULL_POLICY=${MAUTRIX_SIGNAL_IMAGE_PULL_POLICY:-IfNotPresent}
MAUTRIX_SIGNAL_SERVICE_PORT=${MAUTRIX_SIGNAL_SERVICE_PORT:-29328}

if [[ ! -f "${MAUTRIX_SIGNAL_CONFIG_PATH}" ]]; then
  echo "error: mautrix-signal config file not found at ${MAUTRIX_SIGNAL_CONFIG_PATH}" >&2
  exit 1
fi

if [[ ! -f "${MAUTRIX_SIGNAL_REGISTRATION_PATH}" ]]; then
  echo "error: mautrix-signal registration file not found at ${MAUTRIX_SIGNAL_REGISTRATION_PATH}" >&2
  exit 1
fi

MAUTRIX_SIGNAL_CONFIG_CONTENT=$(awk '{print "    "$0} END {print ""}' "${MAUTRIX_SIGNAL_CONFIG_PATH}")
MAUTRIX_SIGNAL_REGISTRATION_CONTENT=$(awk '{print "    "$0} END {print ""}' "${MAUTRIX_SIGNAL_REGISTRATION_PATH}")

MAUTRIX_SIGNAL_CHART_NAME="mautrix-signal"
if [[ "${MAUTRIX_SIGNAL_RELEASE_NAME}" == *"${MAUTRIX_SIGNAL_CHART_NAME}"* ]]; then
  MAUTRIX_SIGNAL_CONFIGMAP_NAME="${MAUTRIX_SIGNAL_RELEASE_NAME}"
else
  MAUTRIX_SIGNAL_CONFIGMAP_NAME="${MAUTRIX_SIGNAL_RELEASE_NAME}-${MAUTRIX_SIGNAL_CHART_NAME}"
fi
MAUTRIX_SIGNAL_CONFIGMAP_NAME="${MAUTRIX_SIGNAL_CONFIGMAP_NAME:0:63}"
MAUTRIX_SIGNAL_CONFIGMAP_NAME="${MAUTRIX_SIGNAL_CONFIGMAP_NAME%-}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ESS_VALUES="${TMP_DIR}/ess-values.yaml"
cat > "${ESS_VALUES}" <<EOF
postgres:
  enabled: false
ingress:
  tlsEnabled: false
serverName: "${BASE_DOMAIN}"
elementAdmin:
  ingress:
    host: "${HOST_ADMIN}"
    className: "disabled"
  resources:
    requests:
      cpu: 25m
      memory: 64Mi
elementWeb:
  ingress:
    host: "${HOST_CHAT}"
    className: "disabled"
  resources:
    requests:
      cpu: 25m
      memory: 64Mi
matrixAuthenticationService:
  ingress:
    host: "${HOST_ACCOUNT}"
    className: "disabled"
  postgres:
    host: "${CLOUDSQL_HOST}"
    port: 5432
    user: "${MAS_DB_USER}"
    database: "${MAS_DB_NAME}"
    sslMode: require
    password:
      secret: "${MAS_SECRET_NAME}"
      secretKey: password
  serviceAccount:
    create: true
    name: "${MAS_SA_NAME}"
    annotations:
      iam.gke.io/gcp-service-account: "${MAS_SA_EMAIL}"
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
matrixRTC:
  ingress:
    host: "${HOST_RTC}"
    className: "disabled"
  resources:
    requests:
      cpu: 25m
      memory: 32Mi
synapse:
  ingress:
    host: "${HOST_MATRIX}"
    className: "disabled"
  postgres:
    host: "${CLOUDSQL_HOST}"
    port: 5432
    user: "${SYNAPSE_DB_USER}"
    database: "${SYNAPSE_DB_NAME}"
    sslMode: require
    password:
      secret: "${SYNAPSE_SECRET_NAME}"
      secretKey: password
  serviceAccount:
    create: true
    name: "${SYNAPSE_SA_NAME}"
    annotations:
      iam.gke.io/gcp-service-account: "${SYNAPSE_SA_EMAIL}"
  additional:
    00-allow-unsafe-locale:
      config: |-
        database:
          allow_unsafe_locale: true
  appservices:
    - configMap: "${MAUTRIX_SIGNAL_CONFIGMAP_NAME}-config"
      configMapKey: registration.yaml
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
wellKnownDelegation:
  enabled: true
  ingress:
    className: "disabled"
EOF

MAUTRIX_SIGNAL_VALUES="${TMP_DIR}/mautrix-signal-values.yaml"
cat > "${MAUTRIX_SIGNAL_VALUES}" <<EOF
replicaCount: ${MAUTRIX_SIGNAL_REPLICA_COUNT}
image:
  repository: ${MAUTRIX_SIGNAL_IMAGE_REPOSITORY}
  tag: ${MAUTRIX_SIGNAL_IMAGE_TAG}
  pullPolicy: ${MAUTRIX_SIGNAL_IMAGE_PULL_POLICY}
service:
  type: ClusterIP
  port: ${MAUTRIX_SIGNAL_SERVICE_PORT}
configMap:
  configYaml: |
${MAUTRIX_SIGNAL_CONFIG_CONTENT}
  registrationYaml: |
${MAUTRIX_SIGNAL_REGISTRATION_CONTENT}
EOF

if [[ "${SKIP_REPO_UPDATE}" -eq 0 ]]; then
  helm repo update >/dev/null
fi

helm upgrade --install "${MAUTRIX_SIGNAL_RELEASE_NAME}" "${SCRIPT_DIR}/mautrix-signal" \
  --namespace "${MAUTRIX_SIGNAL_NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout "${HELM_TIMEOUT}" \
  -f "${MAUTRIX_SIGNAL_VALUES}"

helm upgrade --install ess oci://ghcr.io/element-hq/ess-helm/matrix-stack \
  --namespace "${ESS_NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout "${HELM_TIMEOUT}" \
  -f "${ESS_VALUES}"

echo "Helm releases applied successfully."
