#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID=""
BUCKET_NAME=""
LOCATION=""
STATE_PREFIX="opentofu/base"
BACKEND_FILE="$(dirname "${BASH_SOURCE[0]}")/backend.hcl"
STATE_ADMIN=""
FORCE_BACKEND="false"

usage() {
  cat <<'EOF'
Usage: init-remote-state.sh --project PROJECT --bucket BUCKET --location LOCATION [options]

Create (or validate) a Google Cloud Storage bucket for OpenTofu remote state and
write backend.hcl with the provided settings.

Options:
  --project PROJECT       GCP project that owns the state bucket (required)
  --bucket BUCKET         Name of the GCS bucket to use for state (required)
  --location LOCATION     Bucket location, e.g. us, us-central1 (required for creation)
  --prefix PREFIX         Object prefix inside the bucket (default: opentofu/base)
  --backend-file PATH     Where to write backend.hcl (default: infra/cloud/backend.hcl)
  --state-admin PRINCIPAL Grant roles/storage.objectAdmin on the bucket to this principal
                          (service account email or user, e.g. user:you@example.com)
  --force                 Overwrite backend file if it already exists
  -h, --help              Show this help and exit
EOF
}

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ $# -lt 2 ]] && fatal "--project requires a value"
        PROJECT_ID="$2"
        shift 2
        ;;
      --bucket)
        [[ $# -lt 2 ]] && fatal "--bucket requires a value"
        BUCKET_NAME="$2"
        shift 2
        ;;
      --location)
        [[ $# -lt 2 ]] && fatal "--location requires a value"
        LOCATION="$2"
        shift 2
        ;;
      --prefix)
        [[ $# -lt 2 ]] && fatal "--prefix requires a value"
        STATE_PREFIX="$2"
        shift 2
        ;;
      --backend-file)
        [[ $# -lt 2 ]] && fatal "--backend-file requires a value"
        BACKEND_FILE="$2"
        shift 2
        ;;
      --state-admin)
        [[ $# -lt 2 ]] && fatal "--state-admin requires a value"
        STATE_ADMIN="$2"
        shift 2
        ;;
      --force)
        FORCE_BACKEND="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fatal "Unknown option: $1"
        ;;
    esac
  done

  [[ -z "$PROJECT_ID" ]] && fatal "--project is required"
  [[ -z "$BUCKET_NAME" ]] && fatal "--bucket is required"
  [[ -z "$LOCATION" ]] && fatal "--location is required"
}

ensure_dependencies() {
  command_exists gcloud || fatal "gcloud CLI is required"
}

bucket_exists() {
  gcloud storage buckets describe "gs://${BUCKET_NAME}" \
    --project "${PROJECT_ID}" \
    --format="value(name)" >/dev/null 2>&1
}

create_bucket() {
  echo "Creating bucket gs://${BUCKET_NAME} in ${LOCATION}..."
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project "${PROJECT_ID}" \
    --location "${LOCATION}" \
    --uniform-bucket-level-access \
    --public-access-prevention enforced
}

enable_versioning() {
  echo "Ensuring object versioning is enabled..."
  gcloud storage buckets update "gs://${BUCKET_NAME}" \
    --project "${PROJECT_ID}" \
    --versioning
}

grant_state_admin() {
  local member="$1"
  if [[ -z "$member" ]]; then
    return
  fi

  # Allow shorthand like user@example.com by defaulting to user:
  if [[ "$member" != *:* ]]; then
    if [[ "$member" == *@* ]]; then
      member="user:${member}"
    else
      member="serviceAccount:${member}"
    fi
  fi

  echo "Granting roles/storage.objectAdmin to ${member}..."
  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --project "${PROJECT_ID}" \
    --member "${member}" \
    --role roles/storage.objectAdmin >/dev/null
}

write_backend_file() {
  if [[ -f "$BACKEND_FILE" && "$FORCE_BACKEND" != "true" ]]; then
    echo "Backend file already exists at ${BACKEND_FILE} (use --force to overwrite)."
    return
  fi

  mkdir -p "$(dirname "$BACKEND_FILE")"
  cat >"$BACKEND_FILE" <<EOF
bucket = "${BUCKET_NAME}"
prefix = "${STATE_PREFIX}"
EOF

  echo "Wrote backend configuration to ${BACKEND_FILE}."
}

main() {
  parse_args "$@"
  ensure_dependencies

  if bucket_exists; then
    echo "Bucket gs://${BUCKET_NAME} already exists; reusing."
  else
    create_bucket
  fi

  enable_versioning
  grant_state_admin "$STATE_ADMIN"
  write_backend_file

  cat <<EOF

Remote state ready.

Next steps:
  tofu init -backend-config=${BACKEND_FILE}
EOF
}

main "$@"
