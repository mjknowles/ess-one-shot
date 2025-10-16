#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TF_DIR="${SCRIPT_DIR}/base"
PROJECT_OVERRIDE=""
ANALYTICS_LOCATION_OVERRIDE=""
NAMESPACE_OVERRIDE=""
SYNAPSE_DB_OVERRIDE=""
MAS_DB_OVERRIDE=""
REPLICATION_USER_OVERRIDE=""
PUBLICATION_PREFIX_OVERRIDE=""
SLOT_PREFIX_OVERRIDE=""
CLOUDSQL_INSTANCE_OVERRIDE=""
CLOUDSQL_PRIVATE_IP_OVERRIDE=""

DEFAULT_NAMESPACE="ess"
DEFAULT_SYN_DB="synapse"
DEFAULT_MAS_DB="mas"
DEFAULT_REPLICATION_USER="datastream_replica"
DEFAULT_PUBLICATION_PREFIX="ess_publication"
DEFAULT_SLOT_PREFIX="ess_replication_slot"

usage() {
  cat <<'EOF'
Undo Datastream grants and clean up Cloud SQL replication helpers before tofu destroy.

Usage:
  pre-destroy.sh [--tf-dir PATH] [--project PROJECT_ID] [--analytics-location REGION]
                 [--namespace NAME] [--synapse-db NAME] [--mas-db NAME]
                 [--replication-user NAME] [--publication-prefix PREFIX]
                 [--slot-prefix PREFIX] [--cloudsql-instance NAME]
                 [--cloudsql-private-ip ADDRESS]

Options:
  --tf-dir PATH       Path to the OpenTofu configuration directory (default: infra/cloud/base)
  --project ID        Override the project ID parsed from terraform outputs
  --analytics-location REGION
                      Override the region used for Datastream APIs
  --cloudsql-instance NAME
                      Name of the Cloud SQL instance providing Synapse/MAS
  --cloudsql-private-ip ADDRESS
                      Private IP address of the Cloud SQL instance (optional override)
  --namespace NAME    Kubernetes namespace running ESS workloads (default: ess)
  --synapse-db NAME   Synapse database name (default: synapse)
  --mas-db NAME       MAS database name (default: mas)
  --replication-user NAME
                      Datastream replication user (default: datastream_replica)
  --publication-prefix PREFIX
                      Prefix for Datastream publications (default: ess_publication)
  --slot-prefix PREFIX
                      Prefix for Datastream replication slots (default: ess_replication_slot)
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
      [[ $# -lt 2 ]] && { echo "error: --tf-dir requires a path argument" >&2; exit 1; }
      [[ ! -d "$2" ]] && { echo "error: --tf-dir path does not exist: $2" >&2; exit 1; }
      TF_DIR=$(cd "$2" && pwd)
      shift 2
      ;;
    --project)
      [[ $# -lt 2 ]] && { echo "error: --project requires a value" >&2; exit 1; }
      PROJECT_OVERRIDE="$2"
      shift 2
      ;;
    --analytics-location)
      [[ $# -lt 2 ]] && { echo "error: --analytics-location requires a region" >&2; exit 1; }
      ANALYTICS_LOCATION_OVERRIDE="$2"
      shift 2
      ;;
    --namespace)
      [[ $# -lt 2 ]] && { echo "error: --namespace requires a value" >&2; exit 1; }
      NAMESPACE_OVERRIDE="$2"
      shift 2
      ;;
    --synapse-db)
      [[ $# -lt 2 ]] && { echo "error: --synapse-db requires a value" >&2; exit 1; }
      SYNAPSE_DB_OVERRIDE="$2"
      shift 2
      ;;
    --mas-db)
      [[ $# -lt 2 ]] && { echo "error: --mas-db requires a value" >&2; exit 1; }
      MAS_DB_OVERRIDE="$2"
      shift 2
      ;;
    --replication-user)
      [[ $# -lt 2 ]] && { echo "error: --replication-user requires a value" >&2; exit 1; }
      REPLICATION_USER_OVERRIDE="$2"
      shift 2
      ;;
    --publication-prefix)
      [[ $# -lt 2 ]] && { echo "error: --publication-prefix requires a value" >&2; exit 1; }
      PUBLICATION_PREFIX_OVERRIDE="$2"
      shift 2
      ;;
    --slot-prefix)
      [[ $# -lt 2 ]] && { echo "error: --slot-prefix requires a value" >&2; exit 1; }
      SLOT_PREFIX_OVERRIDE="$2"
      shift 2
      ;;
    --cloudsql-instance)
      [[ $# -lt 2 ]] && { echo "error: --cloudsql-instance requires a value" >&2; exit 1; }
      CLOUDSQL_INSTANCE_OVERRIDE="$2"
      shift 2
      ;;
    --cloudsql-private-ip)
      [[ $# -lt 2 ]] && { echo "error: --cloudsql-private-ip requires a value" >&2; exit 1; }
      CLOUDSQL_PRIVATE_IP_OVERRIDE="$2"
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

normalize_output() {
  local value="$1"
  if [[ "${value}" == "null" ]]; then
    value=""
  fi
  printf '%s\n' "${value}"
}

tf_output_value() {
  local expr="$1"
  local mode="${2:-required}"
  local filter=".$expr | (if type == \"string\" then . else (.|tostring) end)"
  local raw

  if [[ "${mode}" == "optional" ]]; then
    raw=$(jq -r "try (${filter}) catch \"\"" <<<"${TF_OUTPUT_JSON}")
  else
    raw=$(jq -er "${filter}" <<<"${TF_OUTPUT_JSON}") || {
      echo "error: required OpenTofu output missing: ${expr}" >&2
      exit 1
    }
  fi

  local value
  value=$(normalize_output "${raw}")

  if [[ "${mode}" != "optional" && -z "${value}" ]]; then
    echo "error: required OpenTofu output is empty: ${expr}" >&2
    exit 1
  fi

  printf '%s\n' "${value}"
}

CLOUDSQL_PRIVATE_IP="${CLOUDSQL_PRIVATE_IP_OVERRIDE}"
if [[ -z "${CLOUDSQL_PRIVATE_IP}" ]]; then
  CLOUDSQL_PRIVATE_IP=$(tf_output_value "cloudsql_private_ip.value" "optional")
fi
CLOUDSQL_CONN=$(tf_output_value "cloudsql_instance_connection_name.value" "optional")
ANALYTICS_LOCATION_OUTPUT=$(tf_output_value "analytics_location.value" "optional")
SYNAPSE_STREAM_ID=$(tf_output_value "datastream_stream_ids.value.synapse" "optional")
MAS_STREAM_ID=$(tf_output_value "datastream_stream_ids.value.mas" "optional")
ESS_NAMESPACE_OUTPUT=$(tf_output_value "ess_namespace.value" "optional")
SYNAPSE_DB_OUTPUT=$(tf_output_value "synapse_database_name.value" "optional")
MAS_DB_OUTPUT=$(tf_output_value "matrix_auth_database_name.value" "optional")
REPLICATION_USER_OUTPUT=$(tf_output_value "datastream_replication_user.value" "optional")
PUBLICATION_PREFIX_OUTPUT=$(tf_output_value "datastream_publication_prefix.value" "optional")
SLOT_PREFIX_OUTPUT=$(tf_output_value "datastream_replication_slot_prefix.value" "optional")
PROJECT_OUTPUT=$(tf_output_value "project_id.value" "optional")
CLOUDSQL_INSTANCE_OUTPUT=$(tf_output_value "cloudsql_instance_name.value" "optional")

TF_PROJECT_ID=""
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE_OVERRIDE}"
if [[ -n "${CLOUDSQL_CONN}" ]]; then
  IFS=":" read -r TF_PROJECT_ID _ PARSED_INSTANCE <<<"${CLOUDSQL_CONN}"
  if [[ -z "${CLOUDSQL_INSTANCE}" ]]; then
    CLOUDSQL_INSTANCE="${PARSED_INSTANCE}"
  fi
fi

if [[ -z "${CLOUDSQL_INSTANCE:-}" ]]; then
  CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE_OUTPUT}"
fi

if [[ -z "${CLOUDSQL_INSTANCE:-}" ]]; then
  echo "error: unable to determine Cloud SQL instance name; ensure the base stack is applied or pass --tf-dir for the active state." >&2
  exit 1
fi

PROJECT_ID="${PROJECT_OVERRIDE}"
if [[ -z "${PROJECT_ID}" && -n "${TF_PROJECT_ID}" ]]; then
  PROJECT_ID="${TF_PROJECT_ID}"
fi
if [[ -z "${PROJECT_ID}" && -n "${PROJECT_OUTPUT}" ]]; then
  PROJECT_ID="${PROJECT_OUTPUT}"
fi

if [[ -z "${PROJECT_ID}" ]]; then
  echo "error: unable to determine GCP project ID. Re-run with --project PROJECT_ID." >&2
  exit 1
fi

ANALYTICS_LOCATION="${ANALYTICS_LOCATION_OVERRIDE}"
if [[ -z "${ANALYTICS_LOCATION}" ]]; then
  ANALYTICS_LOCATION="${ANALYTICS_LOCATION_OUTPUT}"
fi
if [[ -z "${ANALYTICS_LOCATION}" ]]; then
  echo "error: unable to determine Datastream analytics location. Re-run with --analytics-location REGION." >&2
  exit 1
fi

ESS_NAMESPACE="${NAMESPACE_OVERRIDE:-${ESS_NAMESPACE_OUTPUT:-$DEFAULT_NAMESPACE}}"
SYNAPSE_DB_NAME="${SYNAPSE_DB_OVERRIDE:-${SYNAPSE_DB_OUTPUT:-$DEFAULT_SYN_DB}}"
MAS_DB_NAME="${MAS_DB_OVERRIDE:-${MAS_DB_OUTPUT:-$DEFAULT_MAS_DB}}"
REPLICATION_USER="${REPLICATION_USER_OVERRIDE:-${REPLICATION_USER_OUTPUT:-$DEFAULT_REPLICATION_USER}}"
PUBLICATION_PREFIX="${PUBLICATION_PREFIX_OVERRIDE:-${PUBLICATION_PREFIX_OUTPUT:-$DEFAULT_PUBLICATION_PREFIX}}"
SLOT_PREFIX="${SLOT_PREFIX_OVERRIDE:-${SLOT_PREFIX_OUTPUT:-$DEFAULT_SLOT_PREFIX}}"

if [[ -z "${ESS_NAMESPACE}" || -z "${SYNAPSE_DB_NAME}" || -z "${MAS_DB_NAME}" ]]; then
  echo "error: required identifiers (namespace or database names) are missing; supply overrides." >&2
  exit 1
fi

if [[ -z "${CLOUDSQL_PRIVATE_IP}" ]]; then
  echo "Fetching Cloud SQL private IP address from gcloud..."
  CLOUDSQL_PRIVATE_IP=$(gcloud sql instances describe "${CLOUDSQL_INSTANCE}" \
    --project "${PROJECT_ID}" \
    --format="value(ipAddresses[?type=PRIVATE].ipAddress)" | head -n1)
  if [[ -z "${CLOUDSQL_PRIVATE_IP}" ]]; then
    echo "error: unable to determine Cloud SQL private IP; pass --cloudsql-private-ip or ensure private service connection is configured." >&2
    exit 1
  fi
fi

stop_stream() {
  local stream_id="$1"
  if [[ -z "${stream_id}" ]]; then
    return
  fi
  if gcloud datastream streams describe "${stream_id}" \
      --location "${ANALYTICS_LOCATION}" \
      --project "${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Stopping Datastream stream ${stream_id}..."
    gcloud datastream streams update "${stream_id}" \
      --location "${ANALYTICS_LOCATION}" \
      --state=STOPPED \
      --update-mask=state \
      --project "${PROJECT_ID}" \
      --quiet >/dev/null
  else
    echo "Datastream stream ${stream_id} not found, skipping stop."
  fi
}

delete_stream() {
  local stream_id="$1"
  if [[ -z "${stream_id}" ]]; then
    return
  fi
  if gcloud datastream streams describe "${stream_id}" \
      --location "${ANALYTICS_LOCATION}" \
      --project "${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Deleting Datastream stream ${stream_id}..."
    gcloud datastream streams delete "${stream_id}" \
      --location "${ANALYTICS_LOCATION}" \
      --project "${PROJECT_ID}" \
      --quiet >/dev/null
  else
    echo "Datastream stream ${stream_id} already deleted."
  fi
}

stop_stream "${SYNAPSE_STREAM_ID}"
stop_stream "${MAS_STREAM_ID}"
delete_stream "${SYNAPSE_STREAM_ID}"
delete_stream "${MAS_STREAM_ID}"

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

JOB_NAME="datastream-cleanup-$(date +%s)"
cleanup_job() {
  kubectl -n "${ESS_NAMESPACE}" delete job "${JOB_NAME}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup_job EXIT

echo "Launching transient Kubernetes job ${JOB_NAME} to remove Datastream grants and publications..."
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
              psql -h "${CLOUDSQL_PRIVATE_IP}" -U postgres -d postgres <<SQL
              \set ON_ERROR_STOP on
              ALTER ROLE "${REPLICATION_USER}" WITH NOREPLICATION;
              DO $do$
              BEGIN
                IF EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '${SLOT_PREFIX}_${SYNAPSE_DB_NAME}') THEN
                  PERFORM pg_drop_replication_slot('${SLOT_PREFIX}_${SYNAPSE_DB_NAME}');
                END IF;
                IF EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '${SLOT_PREFIX}_${MAS_DB_NAME}') THEN
                  PERFORM pg_drop_replication_slot('${SLOT_PREFIX}_${MAS_DB_NAME}');
                END IF;
              END
              $do$;
              REVOKE ALL PRIVILEGES ON DATABASE "${SYNAPSE_DB_NAME}" FROM "${REPLICATION_USER}";
              REVOKE ALL PRIVILEGES ON DATABASE "${MAS_DB_NAME}" FROM "${REPLICATION_USER}";
              REVOKE USAGE ON SCHEMA public FROM "${REPLICATION_USER}";
              REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM "${REPLICATION_USER}";
              ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM "${REPLICATION_USER}";
              REASSIGN OWNED BY "${REPLICATION_USER}" TO postgres;
              DROP OWNED BY "${REPLICATION_USER}";
SQL
              psql -h "${CLOUDSQL_PRIVATE_IP}" -U postgres -d "${SYNAPSE_DB_NAME}" <<SQL
              \set ON_ERROR_STOP on
              DROP PUBLICATION IF EXISTS "${PUBLICATION_PREFIX}_${SYNAPSE_DB_NAME}";
              REVOKE USAGE ON SCHEMA public FROM "${REPLICATION_USER}";
              REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM "${REPLICATION_USER}";
              ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM "${REPLICATION_USER}";
              REASSIGN OWNED BY "${REPLICATION_USER}" TO postgres;
              DROP OWNED BY "${REPLICATION_USER}";
SQL
              psql -h "${CLOUDSQL_PRIVATE_IP}" -U postgres -d "${MAS_DB_NAME}" <<SQL
              \set ON_ERROR_STOP on
              DROP PUBLICATION IF EXISTS "${PUBLICATION_PREFIX}_${MAS_DB_NAME}";
              REVOKE USAGE ON SCHEMA public FROM "${REPLICATION_USER}";
              REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM "${REPLICATION_USER}";
              ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM "${REPLICATION_USER}";
              REASSIGN OWNED BY "${REPLICATION_USER}" TO postgres;
              DROP OWNED BY "${REPLICATION_USER}";
SQL
EOF

if ! kubectl -n "${ESS_NAMESPACE}" wait --for=condition=complete --timeout=300s "job/${JOB_NAME}"; then
  echo "error: Datastream cleanup job failed" >&2
  kubectl -n "${ESS_NAMESPACE}" logs "job/${JOB_NAME}" || true
  exit 1
fi

kubectl -n "${ESS_NAMESPACE}" logs "job/${JOB_NAME}" || true

echo "Datastream streams removed and Cloud SQL privileges cleaned up."
