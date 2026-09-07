#!/bin/bash
# Shared release signing configuration for local and CI packaging workflows.

MA_RELEASE_SIGNING_MODE="${MA_RELEASE_SIGNING_MODE:-identity}"
MA_RELEASE_CODE_SIGN_IDENTITY="${MA_RELEASE_CODE_SIGN_IDENTITY:-Apple Development}"

ma_list_user_keychains() {
  local login_keychain="${HOME}/Library/Keychains/login.keychain-db"
  printf '%s\n' "${login_keychain}"

  security list-keychains -d user 2>/dev/null \
    | tr -d '"' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | awk 'NF > 0'
}

ma_validate_release_signing_mode() {
  case "${MA_RELEASE_SIGNING_MODE}" in
    adhoc|identity|self-signed)
      return 0
      ;;
    *)
      echo "Invalid MA_RELEASE_SIGNING_MODE='${MA_RELEASE_SIGNING_MODE}'. Use 'adhoc' or 'identity'." >&2
      return 1
      ;;
  esac
}

ma_release_signing_description() {
  case "${MA_RELEASE_SIGNING_MODE}" in
    identity) printf 'keychain identity (%s)' "${MA_RELEASE_CODE_SIGN_IDENTITY}" ;;
    self-signed) printf 'legacy self-signed (%s)' "${MA_RELEASE_CODE_SIGN_IDENTITY}" ;;
    *) printf 'adhoc' ;;
  esac
}

ma_release_effective_identity() {
  if ma_release_uses_keychain_identity; then
    printf '%s' "${MA_RELEASE_CODE_SIGN_IDENTITY}"
  else
    printf '%s' "-"
  fi
}

ma_release_uses_keychain_identity() {
  case "${MA_RELEASE_SIGNING_MODE}" in
    identity|self-signed) return 0 ;;
    *) return 1 ;;
  esac
}

ma_resolve_codesign_identity() {
  local requested="$1"
  local hash=""
  local name=""

  if [[ "${requested}" =~ ^[[:xdigit:]]{40}$ ]]; then
    printf '%s\n' "${requested}"
    return 0
  fi

  while IFS=$'\t' read -r hash name; do
    if [ "${name}" = "${requested}" ] || {
      [ "${requested}" = "Apple Development" ] && [[ "${name}" == "Apple Development:"* ]]
    }; then
      printf '%s\n' "${hash}"
      return 0
    fi
  done < <(security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/^[[:space:]]*[0-9]+\) ([[:xdigit:]]{40}) "([^"]+)".*/\1\t\2/p')

  printf '%s\n' "${requested}"
}

ma_autodetect_release_signing_mode() {
  if ma_codesign_identity_is_stable "${MA_RELEASE_CODE_SIGN_IDENTITY}" 2 0.10; then
    printf '%s' "identity"
  else
    printf '%s' "adhoc"
  fi
}

ma_codesign_identity_exists() {
  local identity="$1"
  local kc=""
  local available_identity=""

  while IFS= read -r kc; do
    while IFS= read -r available_identity; do
      if [ "${available_identity}" = "${identity}" ] || {
        [ "${identity}" = "Apple Development" ] && [[ "${available_identity}" == "Apple Development:"* ]]
      }; then
        return 0
      fi
    done < <(security find-identity -v -p codesigning "${kc}" 2>/dev/null | awk -F'"' '/"/ { print $2 }')
  done < <(ma_list_user_keychains | awk '!seen[$0]++')

  return 1
}

# Returns:
#   0 -> identity visible in every attempt
#   1 -> identity missing in every attempt
#   2 -> identity visibility is unstable/flaky across attempts
ma_codesign_identity_is_stable() {
  local identity="$1"
  local attempts="${2:-3}"
  local interval_seconds="${3:-0.20}"
  local observed_present=0
  local observed_missing=0
  local i=1

  while [ "${i}" -le "${attempts}" ]; do
    if ma_codesign_identity_exists "${identity}"; then
      observed_present=$((observed_present + 1))
    else
      observed_missing=$((observed_missing + 1))
    fi

    if [ "${i}" -lt "${attempts}" ]; then
      sleep "${interval_seconds}"
    fi
    i=$((i + 1))
  done

  if [ "${observed_present}" -eq "${attempts}" ]; then
    return 0
  fi

  if [ "${observed_present}" -eq 0 ]; then
    return 1
  fi

  return 2
}

ma_print_codesign_identity_diagnostics() {
  local identity="$1"
  local login_keychain="${HOME}/Library/Keychains/login.keychain-db"

  cat >&2 <<EOF
Keychain diagnostics for '${identity}':
  default-keychain: $(security default-keychain -d user 2>/dev/null | tr -d '"' || printf 'unavailable')
  search-list:
$(security list-keychains -d user 2>/dev/null | sed 's/^/    /' || printf '    unavailable\n')
  valid identities:
$(security find-identity -v -p codesigning 2>/dev/null | sed 's/^/    /' || printf '    unavailable\n')
EOF

  if security find-certificate -a -c "${identity}" "${login_keychain}" >/dev/null 2>&1; then
    printf '%s\n' "  certificate entry found in login keychain, but no stable usable identity was detected." >&2
  else
    printf '%s\n' "  certificate entry not found in login keychain." >&2
  fi
}

ma_require_release_identity() {
  if ! ma_release_uses_keychain_identity; then
    return 0
  fi

  local identity_state=1
  if ma_codesign_identity_is_stable "${MA_RELEASE_CODE_SIGN_IDENTITY}" 3 0.20; then
    return 0
  else
    identity_state=$?
  fi

  if [ "${identity_state}" -eq 2 ]; then
    cat >&2 <<EOF
Code signing identity '${MA_RELEASE_CODE_SIGN_IDENTITY}' was detected intermittently.
The keychain visibility is unstable for this shell session.

This can happen when login keychain state changes across sessions (GUI vs non-interactive shell).
Retry the command from the same terminal session where 'security find-identity -v -p codesigning' is stable.
EOF
    ma_print_codesign_identity_diagnostics "${MA_RELEASE_CODE_SIGN_IDENTITY}"
    return 1
  fi

  cat >&2 <<EOF
Missing code signing identity '${MA_RELEASE_CODE_SIGN_IDENTITY}' in keychain.

Use an available Apple Development identity or set MA_RELEASE_CODE_SIGN_IDENTITY to its exact name.
  security find-identity -v -p codesigning
EOF
  if [ "${MA_RELEASE_SIGNING_MODE}" = "self-signed" ]; then
    printf '%s\n' "For the legacy self-signed mode, create it with:" >&2
    printf '  ./scripts/setup-self-signed-cert.sh --name "%s"\n' "${MA_RELEASE_CODE_SIGN_IDENTITY}" >&2
  fi
  ma_print_codesign_identity_diagnostics "${MA_RELEASE_CODE_SIGN_IDENTITY}"
  return 1
}
