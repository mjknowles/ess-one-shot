#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="ess-one-shot"
NAMESPACE="ess"
VALUES_DIR="${PWD}/ess-values"
CHART_REF="oci://ghcr.io/element-hq/ess-helm/matrix-stack"
CA_DIR="${PWD}/.ca"
CA_CERT_FILE="${CA_DIR}/ca.crt"
CA_KEY_FILE="${CA_DIR}/ca.pem"
CA_FINGERPRINT_FILE="${CA_DIR}/ca.sha256"
TRUST_CA="${ESS_TRUST_CA:-true}"

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_wsl() {
  if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]]; then
    return 0
  fi
  if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    return 0
  fi
  return 1
}

encode_file_base64() {
  python3 - "$1" <<'PY'
import base64
import sys

with open(sys.argv[1], 'rb') as fh:
    sys.stdout.write(base64.b64encode(fh.read()).decode())
PY
}

install_ca_trust_store() {
  if [[ "$TRUST_CA" != "true" ]]; then
    echo "Skipping trust store install (ESS_TRUST_CA=$TRUST_CA)."
    return 2
  fi

  if [[ ! -f "$CA_CERT_FILE" ]]; then
    echo "WARN: CA certificate $CA_CERT_FILE missing; cannot install trust."
    return 1
  fi

  local os_name
  os_name="$(uname -s)"

  case "$os_name" in
    Darwin)
      if ! command_exists security || ! command_exists sudo; then
        echo "WARN: Unable to install CA automatically on macOS (requires security and sudo)."
        return 1
      fi

      if ! sudo security delete-certificate -c "ess-ca" /Library/Keychains/System.keychain >/dev/null 2>&1; then
        true
      fi

      if sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CA_CERT_FILE"; then
        echo "Installed CA into macOS trust store."
        return 0
      else
        echo "WARN: Failed to install CA into macOS trust store."
        return 1
      fi
      ;;
    Linux)
      if ! command_exists sudo; then
        echo "WARN: sudo not available; cannot modify Linux trust store."
        return 1
      fi

      local linux_status=1

      if command_exists update-ca-certificates; then
        local dest="/usr/local/share/ca-certificates/ess-ca.crt"
        if sudo install -m 0644 "$CA_CERT_FILE" "$dest"; then
          if sudo update-ca-certificates; then
            echo "Installed CA via update-ca-certificates."
            linux_status=0
          fi
        fi
        if (( linux_status != 0 )); then
          echo "WARN: Failed to install CA using update-ca-certificates."
        fi
      elif command_exists trust; then
        if sudo trust anchor --store "$CA_CERT_FILE"; then
          echo "Installed CA via trust anchor."
          linux_status=0
        else
          echo "WARN: Failed to install CA using trust anchor."
        fi
      else
        echo "WARN: Neither update-ca-certificates nor trust present; skipping trust store install."
        linux_status=1
      fi

      local running_in_wsl=0
      if is_wsl; then
        running_in_wsl=1
      fi

      local windows_status=0
      if (( running_in_wsl )); then
        if install_ca_windows_trust_store; then
          windows_status=0
        else
          windows_status=1
        fi
      fi

      if (( linux_status == 0 )); then
        if (( running_in_wsl == 0 )) || (( windows_status == 0 )); then
          return 0
        fi
      fi

      return 1
      ;;
    *)
      echo "WARN: Unsupported OS '$os_name'; skipping trust store install."
      return 1
      ;;
  esac
}

install_ca_windows_trust_store() {
  if [[ ! -f "$CA_CERT_FILE" ]]; then
    echo "WARN: CA certificate $CA_CERT_FILE missing; cannot install into Windows trust store."
    return 1
  fi

  if ! command_exists wslpath; then
    echo "WARN: wslpath not available; cannot convert path for Windows trust store install."
    return 1
  fi

  local ps_exe=""
  if command_exists powershell.exe; then
    ps_exe="powershell.exe"
  elif command_exists pwsh.exe; then
    ps_exe="pwsh.exe"
  else
    echo "WARN: Neither powershell.exe nor pwsh.exe found; skipping Windows trust store install."
    return 1
  fi

  local win_cert_path
  if ! win_cert_path=$(wslpath -w "$CA_CERT_FILE"); then
    echo "WARN: Unable to convert $CA_CERT_FILE to a Windows path."
    return 1
  fi

  mkdir -p "$CA_DIR"
  local ps_script
  if ! ps_script=$(mktemp "${CA_DIR}/win-ca-import-XXXXXX.ps1"); then
    echo "WARN: Unable to create temporary PowerShell script for Windows trust store install."
    return 1
  fi

  cat >"$ps_script" <<'EOF'
param(
  [Parameter(Mandatory = $true)]
  [string]$CertPath
)

try {
  $null = Import-Certificate -FilePath $CertPath -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction Stop
  Write-Host "Imported certificate into Windows trust store."
  exit 0
} catch {
  Write-Error $_
  exit 1
}
EOF

  local win_script_path
  if ! win_script_path=$(wslpath -w "$ps_script"); then
    echo "WARN: Unable to convert temporary script path $ps_script to a Windows path."
    rm -f "$ps_script"
    return 1
  fi

  local ps_command="\$p = Start-Process PowerShell -ArgumentList '-NoProfile','-File','${win_script_path}','-CertPath','${win_cert_path}' -Verb RunAs -PassThru; \$p.WaitForExit(); exit \$p.ExitCode"

  echo "Attempting Windows trust store install (requires elevation). Approve the Windows prompt if shown."
  if "$ps_exe" -NoProfile -Command "$ps_command"; then
    rm -f "$ps_script"
    echo "Windows trust store install completed."
    return 0
  else
    echo "WARN: Windows trust store install command failed."
    rm -f "$ps_script"
    return 1
  fi
}

ensure_dependencies() {
  for bin in kind kubectl helm python3 openssl; do
    command_exists "$bin" || fatal "Missing dependency: $bin"
  done
}

ensure_kind_cluster() {
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

ensure_ingress_nginx() {
  if kubectl get deployment -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
    echo "ingress-nginx already present. Waiting for controller to become available..."
  else
    echo "Installing ingress-nginx controller for kind..."
    kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
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

  mkdir -p "$CA_DIR"

  if [[ ! -f "$CA_CERT_FILE" || ! -f "$CA_KEY_FILE" ]]; then
    echo "Generating new local CA (stored in $CA_DIR)..."
    cat <<'EOF' | kubectl apply -f -
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ess-ca
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ess-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: ess-ca
  secretName: ess-ca
  duration: 87660h0m0s
  privateKey:
    algorithm: RSA
  issuerRef:
    name: ess-ca
    kind: ClusterIssuer
    group: cert-manager.io
EOF

    kubectl wait \
      --namespace cert-manager \
      --for=condition=Ready \
      certificate/ess-ca \
      --timeout=180s

    local tls_crt_b64
    tls_crt_b64=$(kubectl -n cert-manager get secret ess-ca -o jsonpath="{.data['tls\.crt']}")
    local tls_key_b64
    tls_key_b64=$(kubectl -n cert-manager get secret ess-ca -o jsonpath="{.data['tls\.key']}")

    python3 - "$tls_crt_b64" "$CA_CERT_FILE" <<'PY'
import base64
import sys

data = sys.argv[1]
path = sys.argv[2]
with open(path, 'wb') as fh:
    fh.write(base64.b64decode(data))
PY

    python3 - "$tls_key_b64" "$CA_KEY_FILE" <<'PY'
import base64
import sys

data = sys.argv[1]
path = sys.argv[2]
with open(path, 'wb') as fh:
    fh.write(base64.b64decode(data))
PY

    chmod 0644 "$CA_CERT_FILE"
    chmod 0600 "$CA_KEY_FILE"
  else
    echo "Reusing existing local CA from $CA_DIR..."
    kubectl delete ClusterIssuer ess-ca >/dev/null 2>&1 || true
    kubectl -n cert-manager delete Certificate ess-ca >/dev/null 2>&1 || true
    kubectl -n cert-manager delete Secret ess-ca >/dev/null 2>&1 || true

    local tls_crt_b64
    tls_crt_b64=$(encode_file_base64 "$CA_CERT_FILE")
    local tls_key_b64
    tls_key_b64=$(encode_file_base64 "$CA_KEY_FILE")

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ess-ca
  namespace: cert-manager
type: kubernetes.io/tls
data:
  tls.crt: ${tls_crt_b64}
  tls.key: ${tls_key_b64}
  ca.crt: ${tls_crt_b64}
EOF
  fi

  cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ess-selfsigned
spec:
  ca:
    secretName: ess-ca
EOF

  if [[ -f "$CA_CERT_FILE" ]]; then
    local fingerprint
    fingerprint=$(openssl x509 -in "$CA_CERT_FILE" -noout -fingerprint -sha256 | awk -F= '{print $2}')
    local previous_fingerprint=""
    if [[ -f "$CA_FINGERPRINT_FILE" ]]; then
      previous_fingerprint="$(<"$CA_FINGERPRINT_FILE")"
    fi

    if [[ "$fingerprint" != "$previous_fingerprint" ]]; then
      if [[ "$TRUST_CA" == "true" ]]; then
        echo "CA fingerprint changed; attempting trust store update..."
        if install_ca_trust_store; then
          printf '%s' "$fingerprint" > "$CA_FINGERPRINT_FILE"
        else
          echo "WARN: Automatic trust store update failed. Install ${CA_CERT_FILE} manually if needed."
        fi
      else
        printf '%s' "$fingerprint" > "$CA_FINGERPRINT_FILE"
        echo "CA fingerprint changed; skipping trust store update (ESS_TRUST_CA=false)."
      fi
    fi
  fi
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
  )

  if [[ -d "$VALUES_DIR" ]]; then
    while IFS= read -r file; do
      helm_cmd+=(-f "$file")
    done < <(find "$VALUES_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
  fi

  "${helm_cmd[@]}"

  echo "ESS chart installation command completed."
}

main() {
  ensure_dependencies
  ensure_kind_cluster
  ensure_ingress_nginx
  ensure_cert_manager
  ensure_namespace
  install_ess_chart

  cat <<EOF

ESS should now be installing in namespace '$NAMESPACE'.

Ingress endpoints (once ready):
  Element Web:      https://chat.ess.localhost/
  Admin console:    https://admin.ess.localhost/
  Synapse (Matrix): https://matrix.ess.localhost/
  MAS:              https://account.ess.localhost/
  RTC:              https://rtc.ess.localhost/

EOF
}

main "$@"
