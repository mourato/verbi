#!/bin/bash

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'USAGE'
Usage: ./scripts/tests/localization-check-test.sh

Description: Run isolated pass/fail fixtures for the deterministic localization checker.
USAGE
    exit 0
fi

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-localization-test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    printf '%s\n' "${haystack}" | grep -Fq -- "${needle}" || fail "missing: ${needle}"
}

new_fixture() {
    local fixture="$1"
    mkdir -p \
        "${fixture}/App" \
        "${fixture}/Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj" \
        "${fixture}/Packages/MeetingAssistantCore/Sources/Common/Resources/pt.lproj"

    printf '%s\n' \
        '"common.title" = "Title";' \
        '"settings.ready" = "Ready";' \
        > "${fixture}/Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj/Localizable.strings"
    printf '%s\n' \
        '"common.title" = "Título";' \
        '"settings.ready" = "Pronto";' \
        > "${fixture}/Packages/MeetingAssistantCore/Sources/Common/Resources/pt.lproj/Localizable.strings"
    printf '%s\n' \
        'let title = "common.title".localized' \
        'let status = "settings.ready".localized()' \
        > "${fixture}/App/Fixture.swift"
}

fixture="${TMP_ROOT}/valid"
new_fixture "${fixture}"
output="$(python3 "${SCRIPT_ROOT}/scripts/check-localization.py" --root "${fixture}")"
assert_contains "${output}" "LOCALIZATION_CHECK_STATUS=PASS"

bad_fixture="${TMP_ROOT}/invalid"
new_fixture "${bad_fixture}"
printf '%s\n' '"only.in.pt" = "Somente PT";' >> "${bad_fixture}/Packages/MeetingAssistantCore/Sources/Common/Resources/pt.lproj/Localizable.strings"
printf '%s\n' 'let missing = "missing.key".localized' >> "${bad_fixture}/App/Fixture.swift"
set +e
output="$(python3 "${SCRIPT_ROOT}/scripts/check-localization.py" --root "${bad_fixture}" 2>&1)"
status=$?
set -e
test "${status}" -eq 1 || fail "invalid fixture unexpectedly passed"
assert_contains "${output}" "LOCALIZATION_CHECK_STATUS=FAIL"
assert_contains "${output}" "only.in.pt"
assert_contains "${output}" "missing.key"

echo "LOCALIZATION_CHECK_TEST_STATUS=PASS"
