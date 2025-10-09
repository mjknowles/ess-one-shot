#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
CLUSTER_NAME="ess-one-shot-gke"
PROJECT=""
REGION="us-central1"
ZONE=""
NAMESPACE="ess"
USE_AUTOPILOT="false"
MACHINE_TYPE="e2-standard-4"
NODE_COUNT="3"
RELEASE_CHANNEL="regular"
NETWORK=""
SUBNETWORK=""
LB_IP_ADDRESS=""
DOMAIN="PLACEHOLDER_DOMAIN"
TLS_ENABLED="true"
TLS_SECRET_NAME=""
INGRESS_CLASS_NAME="nginx"
INGRESS_CONTROLLER_TYPE="ingress-nginx"
VALUES_DIR="${PWD}/.ess-values"
VALUES_FILE="${VALUES_DIR}/gcp-hostnames.yaml"
CHART_REF="oci://ghcr.io/element-hq/ess-helm/matrix-stack"
INGRESS_RELEASE_NAME="ess-ingress"
INGRESS_NAMESPACE="ingress-nginx"
INGRESS_CHART="ingress-nginx/ingress-nginx"
SKIP_CLUSTER_CREATION="false"
FORCE_VALUES="false"
EXTRA_HELM_ARGS=()

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options] [-- <extra helm args>]

Provision (or reuse) a Google Kubernetes Engine cluster and deploy the Element Server Suite Helm chart.

Cluster options:
  --project PROJECT         GCP project ID (defaults to gcloud config project)
  --region REGION           GCP region (default: ${REGION})
  --zone ZONE               GCP zone (standard clusters only; overrides --region for zonal clusters)
  --cluster-name NAME       GKE cluster name (default: ${CLUSTER_NAME})
  --namespace NAME          Kubernetes namespace for ESS (default: ${NAMESPACE})
  --autopilot               Use Autopilot mode (requires --region; ignores node size/count options)
  --machine-type TYPE       Node machine type for standard clusters (default: ${MACHINE_TYPE})
  --node-count N            Node count for standard clusters (default: ${NODE_COUNT})
  --release-channel NAME    Release channel (rapid|regular|stable) for standard clusters (default: ${RELEASE_CHANNEL})
  --network NAME            Optional VPC network to attach the cluster to
  --subnetwork NAME         Optional subnetwork inside the chosen VPC
  --lb-ip-address IP        Optional reserved static IP for ingress-nginx LoadBalancer
  --skip-cluster            Assume the target cluster already exists and skip creation

Ingress & chart options:
  --domain DOMAIN           Base domain for ESS ingress hostnames (default: ${DOMAIN})
  --disable-tls             Turn off TLS configuration in the generated values file
  --tls-secret NAME         Existing TLS secret to reference for all ingresses
  --ingress-class NAME      IngressClass name to reference (default: ${INGRESS_CLASS_NAME})
  --ingress-controller-type TYPE  Chart controller hint (default: ${INGRESS_CONTROLLER_TYPE})
  --values-file PATH        Where to write the generated values file (default: ${VALUES_FILE})
  --force-values            Regenerate the values file even if it already exists

General:
  -h, --help                Show this help text

Any arguments after '--' are passed straight to the final 'helm upgrade --install' call.
EOF
}

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

resolve_path() {
  local input_path="$1"
  if command_exists realpath; then
    realpath "$input_path"
  else
    python3 - "$input_path" <<'PY'
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ $# -lt 2 ]] && fatal "--project requires an argument"
        PROJECT="$2"
        shift 2
        ;;
      --region)
        [[ $# -lt 2 ]] && fatal "--region requires an argument"
        REGION="$2"
        shift 2
        ;;
      --zone)
        [[ $# -lt 2 ]] && fatal "--zone requires an argument"
        ZONE="$2"
        shift 2
        ;;
      --cluster-name)
        [[ $# -lt 2 ]] && fatal "--cluster-name requires an argument"
        CLUSTER_NAME="$2"
        shift 2
        ;;
      --namespace)
        [[ $# -lt 2 ]] && fatal "--namespace requires an argument"
        NAMESPACE="$2"
        shift 2
        ;;
      --autopilot)
        USE_AUTOPILOT="true"
        shift
        ;;
      --machine-type)
        [[ $# -lt 2 ]] && fatal "--machine-type requires an argument"
        MACHINE_TYPE="$2"
        shift 2
        ;;
      --node-count)
        [[ $# -lt 2 ]] && fatal "--node-count requires an argument"
        NODE_COUNT="$2"
        shift 2
        ;;
      --release-channel)
        [[ $# -lt 2 ]] && fatal "--release-channel requires an argument"
        RELEASE_CHANNEL="$2"
        shift 2
        ;;
      --network)
        [[ $# -lt 2 ]] && fatal "--network requires an argument"
        NETWORK="$2"
        shift 2
        ;;
      --subnetwork)
        [[ $# -lt 2 ]] && fatal "--subnetwork requires an argument"
        SUBNETWORK="$2"
        shift 2
        ;;
      --lb-ip-address)
        [[ $# -lt 2 ]] && fatal "--lb-ip-address requires an argument"
        LB_IP_ADDRESS="$2"
        shift 2
        ;;
      --domain)
        [[ $# -lt 2 ]] && fatal "--domain requires an argument"
        DOMAIN="$2"
        shift 2
        ;;
      --disable-tls)
        TLS_ENABLED="false"
        shift
        ;;
      --tls-secret)
        [[ $# -lt 2 ]] && fatal "--tls-secret requires an argument"
        TLS_SECRET_NAME="$2"
        shift 2
        ;;
      --ingress-class)
        [[ $# -lt 2 ]] && fatal "--ingress-class requires an argument"
        INGRESS_CLASS_NAME="$2"
        shift 2
        ;;
      --ingress-controller-type)
        [[ $# -lt 2 ]] && fatal "--ingress-controller-type requires an argument"
        INGRESS_CONTROLLER_TYPE="$2"
        shift 2
        ;;
      --values-file)
        [[ $# -lt 2 ]] && fatal "--values-file requires an argument"
        VALUES_FILE="$(resolve_path "$2")"
        VALUES_DIR="$(dirname "$VALUES_FILE")"
        shift 2
        ;;
      --force-values)
        FORCE_VALUES="true"
        shift
        ;;
      --skip-cluster)
        SKIP_CLUSTER_CREATION="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        EXTRA_HELM_ARGS=("$@")
        break
        ;;
      *)
        fatal "Unknown option: $1"
        ;;
    esac
  done
}

region_from_zone() {
  [[ -z "$1" ]] && return
  echo "${1%-*}"
}

ensure_dependencies() {
  for bin in gcloud kubectl helm python3; do
    command_exists "$bin" || fatal "Missing dependency: $bin"
  done
}

ensure_gcloud_auth() {
  local account
  account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" || true
  [[ -n "$account" ]] || fatal "No active gcloud account. Run 'gcloud auth login' first."
}

ensure_project() {
  if [[ -z "$PROJECT" ]]; then
    PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
  fi
  [[ -n "$PROJECT" ]] || fatal "No GCP project specified. Use --project or 'gcloud config set project <id>'."
}

ensure_location_settings() {
  if [[ "$USE_AUTOPILOT" == "true" ]]; then
    [[ -n "$ZONE" ]] && fatal "--autopilot cannot be combined with --zone; use --region."
    [[ -z "$REGION" ]] && fatal "--autopilot requires --region."
    if [[ "$MACHINE_TYPE" != "e2-standard-4" || "$NODE_COUNT" != "3" ]]; then
      echo "INFO: --machine-type and --node-count are ignored in Autopilot mode." >&2
    fi
    return
  fi

  if [[ -z "$ZONE" && -z "$REGION" ]]; then
    ZONE="us-central1-a"
  fi
  if [[ -z "$REGION" && -n "$ZONE" ]]; then
    REGION="$(region_from_zone "$ZONE")"
  fi
}

ensure_apis() {
  echo "Enabling required Google APIs (idempotent)..."
  gcloud services enable container.googleapis.com compute.googleapis.com --project "$PROJECT"
}

cluster_exists() {
  local location_flag
  if [[ "$USE_AUTOPILOT" == "true" || ( -z "$ZONE" && -n "$REGION" ) ]]; then
    location_flag=(--region "$REGION")
  else
    location_flag=(--zone "$ZONE")
  fi
  gcloud container clusters describe "$CLUSTER_NAME" --project "$PROJECT" "${location_flag[@]}" >/dev/null 2>&1
}

ensure_cluster() {
  if [[ "$SKIP_CLUSTER_CREATION" == "true" ]]; then
    echo "Skipping cluster creation (per --skip-cluster)."
    return
  fi

  if cluster_exists; then
    echo "Reusing existing GKE cluster '$CLUSTER_NAME'."
    return
  fi

  echo "Creating GKE cluster '$CLUSTER_NAME'..."
  local base_cmd=(gcloud container clusters)
  local args=()

  if [[ "$USE_AUTOPILOT" == "true" ]]; then
    base_cmd+=("create-auto")
    args+=("$CLUSTER_NAME" "--project" "$PROJECT" "--region" "$REGION")
  else
    base_cmd+=("create")
    args+=("$CLUSTER_NAME" "--project" "$PROJECT" "--enable-ip-alias" "--release-channel" "$RELEASE_CHANNEL")
    if [[ -n "$ZONE" ]]; then
      args+=("--zone" "$ZONE")
    else
      args+=("--region" "$REGION")
    fi
    args+=("--machine-type" "$MACHINE_TYPE" "--num-nodes" "$NODE_COUNT")
  fi

  if [[ -n "$NETWORK" ]]; then
    args+=("--network" "$NETWORK")
  fi
  if [[ -n "$SUBNETWORK" ]]; then
    args+=("--subnetwork" "$SUBNETWORK")
  fi

  "${base_cmd[@]}" "${args[@]}"
}

configure_kubectl_context() {
  local location_flag
  if [[ "$USE_AUTOPILOT" == "true" || ( -z "$ZONE" && -n "$REGION" ) ]]; then
    location_flag=(--region "$REGION")
  else
    location_flag=(--zone "$ZONE")
  fi

  gcloud container clusters get-credentials "$CLUSTER_NAME" --project "$PROJECT" "${location_flag[@]}"
}

ensure_ingress_controller() {
  echo "Installing ingress-nginx via Helm..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
  helm repo update ingress-nginx >/dev/null

  local helm_args=(
    "upgrade" "--install" "$INGRESS_RELEASE_NAME" "$INGRESS_CHART"
    "--namespace" "$INGRESS_NAMESPACE"
    "--create-namespace"
    "--set" "controller.publishService.enabled=true"
    "--set" "controller.metrics.enabled=true"
  )

  if [[ -n "$LB_IP_ADDRESS" ]]; then
    helm_args+=("--set" "controller.service.loadBalancerIP=$LB_IP_ADDRESS")
  fi

  helm "${helm_args[@]}"

  kubectl wait --namespace "$INGRESS_NAMESPACE" \
    --for=condition=Ready pods \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s
}

ensure_namespace() {
  if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    return
  fi
  kubectl create namespace "$NAMESPACE"
}

ensure_values_file() {
  mkdir -p "$VALUES_DIR"
  if [[ -f "$VALUES_FILE" && "$FORCE_VALUES" != "true" ]]; then
    echo "Values file already exists at $VALUES_FILE (use --force-values to regenerate)."
    return
  fi

  {
    cat <<EOF
ingress:
  className: ${INGRESS_CLASS_NAME}
  controllerType: ${INGRESS_CONTROLLER_TYPE}
  tlsEnabled: ${TLS_ENABLED}
EOF
    if [[ "$TLS_ENABLED" == "true" && -n "$TLS_SECRET_NAME" ]]; then
      echo "  tlsSecret: ${TLS_SECRET_NAME}"
    else
      cat <<'EOF'
  # tlsSecret: your-precreated-tls-secret
EOF
    fi

    cat <<EOF
serverName: ${DOMAIN}

elementAdmin:
  ingress:
    host: admin.${DOMAIN}
elementWeb:
  ingress:
    host: chat.${DOMAIN}
matrixAuthenticationService:
  ingress:
    host: account.${DOMAIN}
matrixRTC:
  ingress:
    host: rtc.${DOMAIN}
synapse:
  ingress:
    host: matrix.${DOMAIN}
EOF
  } >"$VALUES_FILE"

  echo "Wrote ESS values file to $VALUES_FILE."
}

install_ess_chart() {
  echo "Deploying ESS chart into namespace '$NAMESPACE'..."
  helm upgrade \
    --install \
    ess \
    "$CHART_REF" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait \
    -f "$VALUES_FILE" \
    "${EXTRA_HELM_ARGS[@]}"
}

main() {
  parse_args "$@"
  ensure_dependencies
  ensure_gcloud_auth
  ensure_project
  ensure_location_settings
  ensure_apis
  ensure_cluster
  configure_kubectl_context
  ensure_ingress_controller
  ensure_namespace
  ensure_values_file
  install_ess_chart

  cat <<EOF

ESS deployment triggered in '${NAMESPACE}' on cluster '${CLUSTER_NAME}' (project: ${PROJECT}).

Next steps:
  * Point the following hostnames at the ingress LoadBalancer IP once assigned:
      chat.${DOMAIN}
      admin.${DOMAIN}
      matrix.${DOMAIN}
      account.${DOMAIN}
      rtc.${DOMAIN}
  * Provide a TLS secret via --tls-secret or edit ${VALUES_FILE} when ready (or use --disable-tls for HTTP).
  * Track ingress IP with: kubectl get svc -n ${INGRESS_NAMESPACE} ${INGRESS_RELEASE_NAME}-ingress-nginx-controller -w

Re-run this script with updated options (e.g. --force-values, --domain, --tls-secret) to apply changes.
EOF
}

main "$@"
