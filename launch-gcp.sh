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
TLS_SECRET_NAME=""
INGRESS_PROVIDER="nginx"
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
INGRESS_ANNOTATIONS=()
GCP_MANAGED_CERT="false"
GCP_MANAGED_CERT_NAME="ess-managed-cert"
GCP_MANAGED_CERT_HOSTS=""
GCP_STATIC_IP_NAME=""
USER_SET_INGRESS_CLASS="false"
USER_SET_INGRESS_CONTROLLER="false"
AUTO_TLS_SECRET_NAME="ess-autogen-tls"
GENERATE_SELF_SIGNED="false"

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
  --lb-ip-address IP        Reserved static IP for ingress-nginx LoadBalancer (nginx provider only)
  --ingress-provider NAME   Choose ingress controller: nginx (default) or gce
  --gcp-static-ip-name NAME GCE static global IP name (gce provider only)
  --skip-cluster            Assume the target cluster already exists and skip creation

Ingress & chart options:
  --domain DOMAIN           Base domain for ESS ingress hostnames (default: ${DOMAIN})
  --tls-secret NAME         Existing TLS secret to reference for all ingresses
  --gcp-managed-cert        Request a Google-managed certificate (gce provider only)
  --gcp-managed-cert-name NAME   ManagedCertificate resource name (default: ${GCP_MANAGED_CERT_NAME})
  --gcp-managed-cert-hosts HOSTS Comma-separated domains for the managed certificate
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
      --ingress-provider)
        [[ $# -lt 2 ]] && fatal "--ingress-provider requires an argument"
        INGRESS_PROVIDER="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
        shift 2
        ;;
      --gcp-static-ip-name)
        [[ $# -lt 2 ]] && fatal "--gcp-static-ip-name requires an argument"
        GCP_STATIC_IP_NAME="$2"
        shift 2
        ;;
      --domain)
        [[ $# -lt 2 ]] && fatal "--domain requires an argument"
        DOMAIN="$2"
        shift 2
        ;;
      --tls-secret)
        [[ $# -lt 2 ]] && fatal "--tls-secret requires an argument"
        TLS_SECRET_NAME="$2"
        shift 2
        ;;
      --gcp-managed-cert)
        GCP_MANAGED_CERT="true"
        shift
        ;;
      --gcp-managed-cert-name)
        [[ $# -lt 2 ]] && fatal "--gcp-managed-cert-name requires an argument"
        GCP_MANAGED_CERT_NAME="$2"
        shift 2
        ;;
      --gcp-managed-cert-hosts)
        [[ $# -lt 2 ]] && fatal "--gcp-managed-cert-hosts requires an argument"
        GCP_MANAGED_CERT_HOSTS="$2"
        shift 2
        ;;
      --ingress-class)
        [[ $# -lt 2 ]] && fatal "--ingress-class requires an argument"
        INGRESS_CLASS_NAME="$2"
        USER_SET_INGRESS_CLASS="true"
        shift 2
        ;;
      --ingress-controller-type)
        [[ $# -lt 2 ]] && fatal "--ingress-controller-type requires an argument"
        INGRESS_CONTROLLER_TYPE="$2"
        USER_SET_INGRESS_CONTROLLER="true"
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

split_csv() {
  local input="$1"
  local IFS=","
  read -ra __split_result <<<"$input"
  printf '%s\n' "${__split_result[@]}"
}

ess_hostnames() {
  cat <<EOF
admin.${DOMAIN}
chat.${DOMAIN}
matrix.${DOMAIN}
account.${DOMAIN}
rtc.${DOMAIN}
EOF
}

configure_ingress_settings() {
  [[ "$DOMAIN" != "PLACEHOLDER_DOMAIN" ]] || fatal "Please supply a real base domain via --domain."

  case "$INGRESS_PROVIDER" in
    nginx)
      [[ "$USER_SET_INGRESS_CLASS" == "false" ]] && INGRESS_CLASS_NAME="nginx"
      [[ "$USER_SET_INGRESS_CONTROLLER" == "false" ]] && INGRESS_CONTROLLER_TYPE="ingress-nginx"
      if [[ -n "$GCP_STATIC_IP_NAME" ]]; then
        fatal "--gcp-static-ip-name is only valid with --ingress-provider gce"
      fi
      if [[ "$GCP_MANAGED_CERT" == "true" ]]; then
        fatal "--gcp-managed-cert is only supported with --ingress-provider gce"
      fi
      if [[ -z "$TLS_SECRET_NAME" ]]; then
        TLS_SECRET_NAME="$AUTO_TLS_SECRET_NAME"
        GENERATE_SELF_SIGNED="true"
      fi
      ;;
    gce)
      [[ "$USER_SET_INGRESS_CLASS" == "false" ]] && INGRESS_CLASS_NAME="gce"
      [[ "$USER_SET_INGRESS_CONTROLLER" == "false" ]] && INGRESS_CONTROLLER_TYPE=""
      if [[ -n "$LB_IP_ADDRESS" ]]; then
        fatal "--lb-ip-address is only valid with --ingress-provider nginx"
      fi
      if [[ -n "$GCP_STATIC_IP_NAME" ]]; then
        INGRESS_ANNOTATIONS+=("kubernetes.io/ingress.global-static-ip-name=${GCP_STATIC_IP_NAME}")
      fi
      if [[ "$GCP_MANAGED_CERT" != "true" && -z "$TLS_SECRET_NAME" ]]; then
        TLS_SECRET_NAME="$AUTO_TLS_SECRET_NAME"
        GENERATE_SELF_SIGNED="true"
      fi
      ;;
    *)
      fatal "Unsupported ingress provider: ${INGRESS_PROVIDER} (use 'nginx' or 'gce')"
      ;;
  esac

  if [[ "$GCP_MANAGED_CERT" == "true" ]]; then
    [[ "$INGRESS_PROVIDER" == "gce" ]] || fatal "--gcp-managed-cert requires --ingress-provider gce"
    [[ "$DOMAIN" != "PLACEHOLDER_DOMAIN" ]] || fatal "--gcp-managed-cert requires --domain to be set to your base domain"
    [[ -z "$TLS_SECRET_NAME" ]] || fatal "Cannot combine --gcp-managed-cert with --tls-secret; choose one TLS handling method."
    INGRESS_ANNOTATIONS+=("networking.gke.io/managed-certificates=${GCP_MANAGED_CERT_NAME}")
  fi

  if [[ "$INGRESS_PROVIDER" == "gce" && "$GCP_MANAGED_CERT" != "true" && "$TLS_SECRET_NAME" == "$AUTO_TLS_SECRET_NAME" ]]; then
    echo "INFO: Generating a self-signed TLS secret '${AUTO_TLS_SECRET_NAME}' for the GCE ingress. Replace it with a real certificate when ready." >&2
  fi
}

managed_certificate_hosts() {
  if [[ -n "$GCP_MANAGED_CERT_HOSTS" ]]; then
    while IFS= read -r raw_host; do
      local cleaned="${raw_host//[[:space:]]/}"
      [[ -n "$cleaned" ]] && printf '%s\n' "$cleaned"
    done < <(split_csv "$GCP_MANAGED_CERT_HOSTS")
    return
  fi

  ess_hostnames
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
  if [[ "$INGRESS_PROVIDER" != "nginx" ]]; then
    echo "Skipping ingress-nginx installation (ingress-provider=${INGRESS_PROVIDER})."
    return
  fi

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

generate_self_signed_secret() {
  command_exists openssl || fatal "Missing dependency: openssl (required to generate a temporary TLS certificate)."

  local tmp
  tmp="$(mktemp -d)"
  local key_file="${tmp}/tls.key"
  local cert_file="${tmp}/tls.crt"
  local cfg_file="${tmp}/openssl.cnf"

  {
    cat <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
CN = ${DOMAIN}

[req_ext]
subjectAltName = @alt_names

[alt_names]
EOF
    local idx=1
    while IFS= read -r host; do
      printf "DNS.%d = %s\n" "$idx" "$host"
      idx=$((idx+1))
    done < <(ess_hostnames)
    printf "DNS.%d = %s\n" "$idx" "$DOMAIN"
  } >"$cfg_file"

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$key_file" \
    -out "$cert_file" \
    -days 365 \
    -config "$cfg_file" \
    >/dev/null 2>&1

  kubectl create secret tls "$TLS_SECRET_NAME" \
    -n "$NAMESPACE" \
    --cert="$cert_file" \
    --key="$key_file" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

  rm -rf "$tmp"
}

ensure_tls_secret() {
  if [[ -z "$TLS_SECRET_NAME" ]]; then
    return
  fi

  if kubectl get secret "$TLS_SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    return
  fi

  if [[ "$GCP_MANAGED_CERT" == "true" ]]; then
    # Managed certificates will provision TLS; no Kubernetes secret required.
    return
  fi

  if [[ "$GENERATE_SELF_SIGNED" == "true" ]]; then
    echo "Creating self-signed TLS secret '${TLS_SECRET_NAME}' in namespace '${NAMESPACE}'..."
    generate_self_signed_secret
    return
  fi

  fatal "TLS secret '${TLS_SECRET_NAME}' not found in namespace '${NAMESPACE}'. Please create it or rerun with a different option."
}

ensure_managed_certificate() {
  if [[ "$GCP_MANAGED_CERT" != "true" ]]; then
    return
  fi

  local hosts=()
  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    hosts+=("$host")
  done < <(managed_certificate_hosts)

  if [[ "${#hosts[@]}" -eq 0 ]]; then
    fatal "--gcp-managed-cert was requested but no domains were supplied"
  fi

  echo "Configuring Google managed certificate '${GCP_MANAGED_CERT_NAME}' for hosts: ${hosts[*]}"
  {
    cat <<EOF
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: ${GCP_MANAGED_CERT_NAME}
  namespace: ${NAMESPACE}
spec:
  domains:
EOF
    for host in "${hosts[@]}"; do
      echo "  - ${host}"
    done
  } | kubectl apply -f -
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
EOF
    if [[ -n "$INGRESS_CONTROLLER_TYPE" ]]; then
      echo "  controllerType: ${INGRESS_CONTROLLER_TYPE}"
    else
      echo "  # controllerType: \"\""
    fi
    cat <<EOF
  tlsEnabled: true
  annotations:
EOF
    if [[ "${#INGRESS_ANNOTATIONS[@]}" -eq 0 ]]; then
      echo "    {}"
    else
      for annotation in "${INGRESS_ANNOTATIONS[@]}"; do
        local key value
        key="${annotation%%=*}"
        value="${annotation#*=}"
        printf '    %s: "%s"\n' "$key" "$value"
      done
    fi
    if [[ -n "$TLS_SECRET_NAME" ]]; then
      echo "  tlsSecret: ${TLS_SECRET_NAME}"
    else
      echo "  # tlsSecret: your-precreated-tls-secret"
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
  configure_ingress_settings
  ensure_dependencies
  ensure_gcloud_auth
  ensure_project
  ensure_location_settings
  ensure_apis
  ensure_cluster
  configure_kubectl_context
  ensure_ingress_controller
  ensure_namespace
  ensure_tls_secret
  ensure_managed_certificate
  ensure_values_file
  install_ess_chart

  local track_cmd
  if [[ "$INGRESS_PROVIDER" == "nginx" ]]; then
    track_cmd="kubectl get svc -n ${INGRESS_NAMESPACE} ${INGRESS_RELEASE_NAME}-ingress-nginx-controller -w"
  else
    track_cmd="kubectl get ingress -n ${NAMESPACE} -w"
  fi

  cat <<EOF

ESS deployment triggered in '${NAMESPACE}' on cluster '${CLUSTER_NAME}' (project: ${PROJECT}).

Next steps:
  * Point the following hostnames at the ingress LoadBalancer IP once assigned:
      chat.${DOMAIN}
      admin.${DOMAIN}
      matrix.${DOMAIN}
      account.${DOMAIN}
      rtc.${DOMAIN}
EOF

  if [[ -n "$TLS_SECRET_NAME" ]]; then
    cat <<EOF
  * Replace the TLS secret '${TLS_SECRET_NAME}' with production material when available (or rerun with --tls-secret).
EOF
  elif [[ "$INGRESS_PROVIDER" == "nginx" ]]; then
    cat <<EOF
  * A temporary self-signed TLS secret was created; replace it with production material when ready.
EOF
  fi

  cat <<EOF
  * Track ingress status with: ${track_cmd}
EOF

  if [[ "$GCP_MANAGED_CERT" == "true" ]]; then
    cat <<EOF
  * Google-managed certificate '${GCP_MANAGED_CERT_NAME}' is provisioning; it can take up to 15 minutes once DNS resolves.
EOF
  fi

  cat <<'EOF'

Re-run this script with updated options (e.g. --force-values, --domain, --tls-secret) to apply changes.
EOF
}

main "$@"
