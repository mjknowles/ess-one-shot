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
      ;;
    *)
      echo "WARN: Unsupported OS '$os_name'; skipping trust removal."
      ;;
  esac
fi

rm -f "$CA_FINGERPRINT_FILE"

echo "Trust removal complete. Fingerprint cache cleared; rerun launch-local.sh with ESS_TRUST_CA=true to reinstall if desired."
