#!/bin/bash
# =============================================================================
# setup-self-signed-cert.sh - Create/import a reusable local code signing cert
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/config/release_signing.sh
source "${SCRIPT_DIR}/config/release_signing.sh"

CERT_NAME="${MA_SELF_SIGNED_IDENTITY:-Vozinha Local Self-Signed}"
VALID_DAYS="${MA_SELF_SIGNED_VALID_DAYS:-3650}"
KEYCHAIN_PATH="${HOME}/Library/Keychains/login.keychain-db"
if [ -x "/usr/bin/openssl" ]; then
  OPENSSL_BIN="${MA_OPENSSL_BIN:-/usr/bin/openssl}"
else
  OPENSSL_BIN="${MA_OPENSSL_BIN:-$(command -v openssl)}"
fi

usage() {
  cat <<'USAGE'
Usage: scripts/setup-self-signed-cert.sh [options]

Options:
  --name <common-name>   Certificate name (default: MA_SELF_SIGNED_IDENTITY)
  --days <n>             Validity in days (default: 3650)
  --help                 Show help

Environment:
  MA_SELF_SIGNED_IDENTITY         Default common name
  MA_SELF_SIGNED_VALID_DAYS       Default validity in days
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      CERT_NAME="$2"
      shift 2
      ;;
    --days)
      VALID_DAYS="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "${VALID_DAYS}" =~ ^[0-9]+$ ]] || [ "${VALID_DAYS}" -le 0 ]; then
  echo "Invalid --days value: ${VALID_DAYS}" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "OpenSSL is required but not found in PATH." >&2
  exit 1
fi

if [ ! -x "${OPENSSL_BIN}" ]; then
  echo "Configured OpenSSL binary not executable: ${OPENSSL_BIN}" >&2
  exit 1
fi

existing_identity_state=1
if ma_codesign_identity_is_stable "${CERT_NAME}" 3 0.20; then
  echo "A code-signing identity named '${CERT_NAME}' already exists."
  echo "Nothing to do."
  exit 0
else
  existing_identity_state=$?
fi

if [ "${existing_identity_state}" -eq 2 ]; then
  cat >&2 <<EOF
Identity '${CERT_NAME}' was detected intermittently.
Refusing to continue because keychain visibility is unstable for this shell session.
EOF
  ma_print_codesign_identity_diagnostics "${CERT_NAME}"
  exit 1
fi

TMP_DIR="$(mktemp -d /tmp/prisma-self-signed.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

OPENSSL_CONF="${TMP_DIR}/openssl.cnf"
KEY_PATH="${TMP_DIR}/codesign.key"
CERT_PATH="${TMP_DIR}/codesign.crt"
P12_PATH="${TMP_DIR}/codesign.p12"
P12_PASSWORD="${MA_SELF_SIGNED_P12_PASSWORD:-$(uuidgen | tr -d '-')}"
PKCS12_FLAGS=()

cat > "${OPENSSL_CONF}" <<EOF
[ req ]
default_bits = 2048
distinguished_name = req_dn
prompt = no
x509_extensions = v3_codesign

[ req_dn ]
CN = ${CERT_NAME}

[ v3_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

"${OPENSSL_BIN}" req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -days "${VALID_DAYS}" \
  -keyout "${KEY_PATH}" \
  -out "${CERT_PATH}" \
  -config "${OPENSSL_CONF}" >/dev/null 2>&1

if "${OPENSSL_BIN}" pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
  PKCS12_FLAGS+=("-legacy")
fi

if [ "${#PKCS12_FLAGS[@]}" -gt 0 ]; then
  "${OPENSSL_BIN}" pkcs12 \
    "${PKCS12_FLAGS[@]}" \
    -export \
    -inkey "${KEY_PATH}" \
    -in "${CERT_PATH}" \
    -name "${CERT_NAME}" \
    -passout "pass:${P12_PASSWORD}" \
    -out "${P12_PATH}" >/dev/null 2>&1
else
  "${OPENSSL_BIN}" pkcs12 \
    -export \
    -inkey "${KEY_PATH}" \
    -in "${CERT_PATH}" \
    -name "${CERT_NAME}" \
    -passout "pass:${P12_PASSWORD}" \
    -out "${P12_PATH}" >/dev/null 2>&1
fi

import_output=""
if ! import_output="$(
  security import "${P12_PATH}" \
    -k "${KEYCHAIN_PATH}" \
    -P "${P12_PASSWORD}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security 2>&1
)"; then
  cat >&2 <<EOF
Failed to import generated certificate into keychain '${KEYCHAIN_PATH}'.
security import output:
${import_output}
EOF
  ma_print_codesign_identity_diagnostics "${CERT_NAME}"
  exit 1
fi

post_import_state=1
if ma_codesign_identity_is_stable "${CERT_NAME}" 3 0.20; then
  post_import_state=0
else
  post_import_state=$?
fi

if [ "${post_import_state}" -eq 2 ]; then
  cat >&2 <<EOF
Certificate import succeeded, but identity visibility is unstable for '${CERT_NAME}'.
EOF
  ma_print_codesign_identity_diagnostics "${CERT_NAME}"
  exit 1
fi

if [ "${post_import_state}" -ne 0 ]; then
  cat >&2 <<EOF
Certificate import completed but no usable code-signing identity was found for '${CERT_NAME}'.
This usually means the private key was not registered in Keychain.

Try:
  1) Open Keychain Access -> login -> Certificate Assistant -> Create a Certificate
     - Name: ${CERT_NAME}
     - Identity Type: Self Signed Root
     - Certificate Type: Code Signing
  2) Re-run:
     make setup-self-signed-cert
  3) Verify:
     security find-identity -v -p codesigning
EOF
  ma_print_codesign_identity_diagnostics "${CERT_NAME}"
  exit 1
fi

echo "Created and imported self-signed code-signing identity:"
echo "  ${CERT_NAME}"
echo ""
echo "Available signing identities:"
security find-identity -v -p codesigning | sed -n '1,20p'
