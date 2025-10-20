#!/usr/bin/env bash
# Remove the locally-generated ESS CA from system trust stores on macOS and Linux.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CA_DIR="${REPO_ROOT}/.ca"
CA_CERT_FILE="${CA_DIR}/ca.crt"
CA_FINGERPRINT_FILE="${CA_DIR}/ca.sha256"

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

get_ca_fingerprint() {
  if [[ -f "$CA_CERT_FILE" ]]; then
    openssl x509 -in "$CA_CERT_FILE" -noout -fingerprint -sha256 2>/dev/null | awk -F= '{print $2}'
    return
  fi

  if [[ -f "$CA_FINGERPRINT_FILE" ]]; then
    tr -d '\r' <"$CA_FINGERPRINT_FILE"
    return
  fi

  echo ""
}

remove_ca_windows_trust_store() {
  if ! is_wsl; then
    return 0
  fi

  if ! command_exists wslpath; then
    echo "WARN: wslpath not available; cannot convert paths for Windows trust removal."
    return 1
  fi

  local ps_exe=""
  if command_exists powershell.exe; then
    ps_exe="powershell.exe"
  elif command_exists pwsh.exe; then
    ps_exe="pwsh.exe"
  else
    echo "WARN: Neither powershell.exe nor pwsh.exe found; skipping Windows trust removal."
    return 1
  fi

  local ca_thumbprint
  ca_thumbprint="$(get_ca_fingerprint | tr -d '[:space:]')"
  if [[ -z "$ca_thumbprint" ]]; then
    echo "WARN: Unable to determine CA fingerprint; skipping Windows trust removal."
    return 1
  fi

  local normalized_thumbprint="${ca_thumbprint//:/}"
  if [[ -z "$normalized_thumbprint" ]]; then
    echo "WARN: Unable to normalize CA fingerprint; skipping Windows trust removal."
    return 1
  fi

  local ps_script
  if ! ps_script=$(mktemp "${CA_DIR}/win-ca-remove-XXXXXX.ps1"); then
    echo "WARN: Unable to create temporary PowerShell script for Windows trust removal."
    return 1
  fi

  cat >"$ps_script" <<'EOF'
param(
  [Parameter(Mandatory = $true)]
  [string]$Thumbprint
)

$normalized = $Thumbprint -replace ":", ""
try {
  $cert = Get-ChildItem -Path 'Cert:\LocalMachine\Root' | Where-Object { $_.Thumbprint -ieq $normalized }
  if ($cert) {
    $cert | Remove-Item -Force
    Write-Host "Removed ess-ca from Windows trust store."
  } else {
    Write-Host "No ess-ca certificate found in Windows trust store."
  }
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

  local ps_command="\$p = Start-Process PowerShell -ArgumentList '-NoProfile','-File','${win_script_path}','-Thumbprint','${normalized_thumbprint}' -Verb RunAs -PassThru; \$p.WaitForExit(); exit \$p.ExitCode"

  echo "Attempting Windows trust removal (requires elevation). Approve the Windows prompt if shown."
  if "$ps_exe" -NoProfile -Command "$ps_command"; then
    rm -f "$ps_script"
    return 0
  else
    echo "WARN: Windows trust removal command failed."
    rm -f "$ps_script"
    return 1
  fi
}

echo "Removing ESS local CA trust..."

if [[ ! -f "$CA_CERT_FILE" ]]; then
  echo "WARN: CA certificate '$CA_CERT_FILE' not found. Nothing to remove from trust stores."
else
  os_name="$(uname -s)"
  case "$os_name" in
    Darwin)
      if command_exists security && command_exists sudo; then
        if sudo security delete-certificate -c "ess-ca" /Library/Keychains/System.keychain >/dev/null 2>&1; then
          echo "Removed ess-ca from macOS system keychain."
        else
          echo "No ess-ca certificate found in macOS system keychain (or removal failed)."
        fi
      else
        echo "WARN: Unable to remove macOS trust automatically (requires sudo + security)."
      fi
      ;;
    Linux)
      if command_exists sudo; then
        if command_exists update-ca-certificates; then
          if sudo rm -f /usr/local/share/ca-certificates/ess-ca.crt; then
            if sudo update-ca-certificates; then
              echo "Removed ess-ca via update-ca-certificates."
            else
              echo "WARN: update-ca-certificates did not complete successfully."
            fi
          fi
        fi
        if command_exists trust; then
          if sudo trust anchor --remove "$CA_CERT_FILE" >/dev/null 2>&1; then
            echo "Removed ess-ca via trust anchor."
          fi
        fi
      else
        echo "WARN: sudo not available; skipping Linux trust removal."
      fi

      remove_ca_windows_trust_store || true
      ;;
    *)
      echo "WARN: Unsupported OS '$os_name'; skipping trust removal."
      ;;
  esac
fi

rm -f "$CA_FINGERPRINT_FILE"

echo "Trust removal complete. Fingerprint cache cleared; rerun launch-local.sh with ESS_TRUST_CA=true to reinstall if desired."
