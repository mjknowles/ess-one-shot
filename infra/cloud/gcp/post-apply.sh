#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TF_DIR="${SCRIPT_DIR}/base"
PROJECT_OVERRIDE=""

usage() {
  cat <<'EOF'
Run the Cloud SQL grants and start Datastream streams after tofu apply.

Usage:
  post-apply.sh [--tf-dir PATH] [--project PROJECT_ID]

Options:
  --tf-dir PATH       Path to the OpenTofu configuration directory (default: infra/cloud/base)
  --project ID        Override the project ID parsed from terraform outputs
  -h, --help          Show this help message
EOF
}

require_binary() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: $bin is required but not installed or not on PATH" >&2
    exit 1
  fi
}

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
    --project)
      if [[ $# -lt 2 ]]; then
        echo "error: --project requires a value" >&2
        exit 1
      fi
      PROJECT_OVERRIDE="$2"
      shift 2
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
require_binary gcloud
require_binary kubectl

TF_OUTPUT_JSON=$(tofu -chdir="${TF_DIR}" output -json)

tf_output_string() {
  local expr="$1"
  jq -er ".$expr | (if type == \"string\" then . else (.|tostring) end)" <<<"${TF_OUTPUT_JSON}"
}

CLOUDSQL_PRIVATE_IP=$(tf_output_string "cloudsql_private_ip.value")
CLOUDSQL_CONN=$(tf_output_string "cloudsql_instance_connection_name.value")
ANALYTICS_LOCATION=$(tf_output_string "analytics_location.value")
SYNAPSE_STREAM_ID=$(tf_output_string "datastream_stream_ids.value.synapse")
MAS_STREAM_ID=$(tf_output_string "datastream_stream_ids.value.mas")
ESS_NAMESPACE=$(tf_output_string "ess_namespace.value")

IFS=":" read -r TF_PROJECT_ID _ CLOUDSQL_INSTANCE <<<"${CLOUDSQL_CONN}"
if [[ -z "${CLOUDSQL_INSTANCE:-}" ]]; then
  echo "error: failed to parse Cloud SQL instance name from connection string: ${CLOUDSQL_CONN}" >&2
  exit 1
fi

PROJECT_ID="${PROJECT_OVERRIDE:-$TF_PROJECT_ID}"

POSTGRES_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)
if [[ -z "${POSTGRES_PASSWORD}" ]]; then
  echo "error: failed to generate temporary postgres password" >&2
  exit 1
fi

echo "Setting a temporary password for postgres on instance ${CLOUDSQL_INSTANCE}..."
gcloud sql users set-password postgres \
  --instance "${CLOUDSQL_INSTANCE}" \
  --project "${PROJECT_ID}" \
  --password "${POSTGRES_PASSWORD}" \
  --quiet >/dev/null

JOB_NAME="datastream-grants-$(date +%s)"
cleanup_job() {
  kubectl -n "${ESS_NAMESPACE}" delete job "${JOB_NAME}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup_job EXIT

echo "Launching transient Kubernetes job ${JOB_NAME} to apply grants and logical replication setup..."
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${ESS_NAMESPACE}
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:15
          imagePullPolicy: IfNotPresent
          env:
            - name: PGPASSWORD
              value: "${POSTGRES_PASSWORD}"
          command:
            - /bin/bash
            - -c
            - |
              set -euo pipefail
              psql -h "${CLOUDSQL_PRIVATE_IP}" -U postgres -d postgres <<'SQL'
              \set ON_ERROR_STOP on
              ALTER ROLE datastream_replica WITH REPLICATION;
              GRANT CONNECT ON DATABASE synapse TO datastream_replica;
              GRANT CONNECT ON DATABASE mas TO datastream_replica;
              GRANT USAGE ON SCHEMA public TO datastream_replica;
              GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream_replica;
              ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO datastream_replica;
              SQL
              psql -h "${CLOUDSQL_PRIVATE_IP}" -U postgres -d synapse <<'SQL'
              \set ON_ERROR_STOP on
              DO \$do\$
              BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'ess_publication_synapse') THEN
                  EXECUTE 'CREATE PUBLICATION ess_publication_synapse FOR ALL TABLES';
                END IF;
              END
              \$do\$;
              SQL
              psql -h "${CLOUDSQL_PRIVATE_IP}" -U postgres -d mas <<'SQL'
              \set ON_ERROR_STOP on
              DO \$do\$
              BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'ess_publication_mas') THEN
                  EXECUTE 'CREATE PUBLICATION ess_publication_mas FOR ALL TABLES';
                END IF;
              END
              \$do\$;
              SQL
EOF

if ! kubectl -n "${ESS_NAMESPACE}" wait --for=condition=complete --timeout=300s "job/${JOB_NAME}"; then
  echo "error: Datastream grant job failed" >&2
  kubectl -n "${ESS_NAMESPACE}" logs "job/${JOB_NAME}" || true
  exit 1
fi

kubectl -n "${ESS_NAMESPACE}" logs "job/${JOB_NAME}" || true

start_stream() {
  local stream_name="$1"
  echo "Starting Datastream stream ${stream_name}..."
  gcloud datastream streams update "${stream_name}" \
    --location "${ANALYTICS_LOCATION}" \
    --state=RUNNING \
    --update-mask=state \
    --project "${PROJECT_ID}" >/dev/null
}

start_stream "${SYNAPSE_STREAM_ID}"
start_stream "${MAS_STREAM_ID}"

echo "Datastream streams set to RUNNING. Verify BigQuery tables for incoming changes."
