#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="ess-one-shot"
NAMESPACE="ess"
VALUES_DIR="${PWD}/ess-values"
CHART_REF="oci://ghcr.io/element-hq/ess-helm/matrix-stack"
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
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
EOF
  fi

  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
}

ensure_ingress_nginx() {
  if kubectl get deployment -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
    echo "ingress-nginx already present. Waiting for controller to become available..."
  else
    echo "Installing ingress-nginx controller for kind..."
    kubectl apply -f "$INGRESS_MANIFEST"
  fi

  kubectl wait \
    --namespace ingress-nginx \
    --for=condition=Available \
    deployment/ingress-nginx-controller \
    --timeout=180s
}

ensure_cert_manager() {
  echo "Ensuring cert-manager Helm repository..."
  helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null

  echo "Ensuring cert-manager release in namespace 'cert-manager'..."
  helm upgrade \
    --install \
    cert-manager \
    jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.17.0 \
    --wait \
    --set crds.enabled=true

  cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-private-key
    solvers:
      - http01:
          ingress:
            class: traefik
EOF
}

ensure_namespace() {
  if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    return
  fi

  kubectl create namespace "$NAMESPACE"
}


install_ess_chart() {
  echo "Deploying ESS chart into namespace '$NAMESPACE'..."
  local helm_cmd=(
    helm
    upgrade
    --install
    ess
    "$CHART_REF"
    --namespace "$NAMESPACE"
    --create-namespace
    --wait
    -f "$VALUES_FILE"
  )
  if ((${#EXTRA_HELM_ARGS[@]} > 0)); then
    helm_cmd+=("${EXTRA_HELM_ARGS[@]}")
  fi

  "${helm_cmd[@]}"

  echo "ESS chart installation command completed."
}

main() {
  parse_args "$@"
  ensure_dependencies
  ensure_kind_cluster
  ensure_ingress_nginx
  ensure_cert_manager
  ensure_namespace
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
