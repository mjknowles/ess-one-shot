#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="ess-one-shot"
NAMESPACE="ess"
DOMAIN="127-0-0-1.nip.io"
VALUES_DIR="${PWD}/.ess-values"
VALUES_FILE="${VALUES_DIR}/hostnames.yaml"
CHART_REF="oci://ghcr.io/element-hq/ess-helm/matrix-stack"
INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/kind/deploy.yaml"
SKIP_CLUSTER_CREATION="false"
FORCE_VALUES="false"
EXTRA_HELM_ARGS=()

usage() {
  cat <<'EOF'
Usage: launch-local.sh [options] [-- extra helm args...]

Spin up a kind cluster suitable for running the Element Server Suite Helm chart.

Options:
  --cluster-name NAME      Name for the kind cluster (default: ess-one-shot)
  --domain DOMAIN          Base domain for ingress hosts (default: 127-0-0-1.nip.io)
  --namespace NAME         Namespace to install ESS into (default: ess)
  --values-file PATH       Path for generated hostnames values file (default: ./.ess-values/hostnames.yaml)
  --skip-cluster           Reuse the current kube context instead of creating kind
  --force-values           Overwrite the values file even if it already exists
  -h, --help               Show this help and exit

Anything after `--` is passed straight to the final `helm upgrade --install` command.
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
      --cluster-name)
        [[ $# -lt 2 ]] && fatal "--cluster-name requires an argument"
        CLUSTER_NAME="$2"
        shift 2
        ;;
      --domain)
        [[ $# -lt 2 ]] && fatal "--domain requires an argument"
        DOMAIN="$2"
        shift 2
        ;;
      --namespace)
        [[ $# -lt 2 ]] && fatal "--namespace requires an argument"
        NAMESPACE="$2"
        shift 2
        ;;
      --values-file)
        [[ $# -lt 2 ]] && fatal "--values-file requires an argument"
        VALUES_FILE="$(realpath "$2")"
        VALUES_DIR="$(dirname "$VALUES_FILE")"
        shift 2
        ;;
      --skip-cluster)
        SKIP_CLUSTER_CREATION="true"
        shift
        ;;
      --force-values)
        FORCE_VALUES="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        EXTRA_HELM_ARGS=("$@")
        return
        ;;
      *)
        fatal "Unknown option: $1"
        ;;
    esac
  done
}

ensure_dependencies() {
  for bin in kind kubectl helm; do
    command_exists "$bin" || fatal "Missing dependency: $bin"
  done
}

ensure_kind_cluster() {
  if [[ "$SKIP_CLUSTER_CREATION" == "true" ]]; then
    echo "Skipping kind cluster creation (per --skip-cluster)."
    return
  fi

  if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
    echo "Reusing existing kind cluster '$CLUSTER_NAME'."
  else
    echo "Creating kind cluster '$CLUSTER_NAME'..."
    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
  fi

  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
}

# ensure_ingress_nginx() {
#   if kubectl get ns ingress-nginx >/dev/null 2>&1; then
#     echo "ingress-nginx already present."
#     return
#   fi

#   echo "Installing ingress-nginx controller for kind..."
#   kubectl apply -f "$INGRESS_MANIFEST"
#   kubectl wait --namespace ingress-nginx \
#     --for=condition=Ready pods \
#     --selector=app.kubernetes.io/component=controller \
#     --timeout=180s
# }

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

  cat >"$VALUES_FILE" <<EOF
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
serverName: ${DOMAIN}
synapse:
  ingress:
    host: matrix.${DOMAIN}
EOF

  echo "Wrote ESS hostnames values file to $VALUES_FILE."
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

  echo "ESS chart installation command completed."
}

main() {
  parse_args "$@"
  ensure_dependencies
  ensure_kind_cluster
  # ensure_ingress_nginx
  ensure_namespace
  ensure_values_file
  install_ess_chart

  cat <<EOF

ESS should now be installing in namespace '$NAMESPACE'.

Ingress endpoints (once ready):
  Element Web:      https://chat.${DOMAIN}
  Admin console:    https://admin.${DOMAIN}
  Synapse (Matrix): https://matrix.${DOMAIN}
  MAS:              https://account.${DOMAIN}
  RTC:              https://rtc.${DOMAIN}

If you're using the default 127-0-0-1.nip.io domain, no /etc/hosts changes are required.
Otherwise point the hostnames above to 127.0.0.1 and access ingress via ports 8080 (HTTP) and 8443 (HTTPS).

EOF
}

main "$@"
