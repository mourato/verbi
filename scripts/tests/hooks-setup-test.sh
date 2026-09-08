#!/bin/bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-hooks-setup-test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

setup_fixture() {
    local fixture="${TMP_ROOT}/repo"
    rm -rf "${fixture}"
    mkdir -p "${fixture}/scripts/lib" "${fixture}/scripts/hooks"
    cp "${SCRIPT_ROOT}/scripts/lib/configure-git-hooks.sh" "${fixture}/scripts/lib/"
    touch "${fixture}/scripts/hooks/pre-commit" \
        "${fixture}/scripts/hooks/pre-push" \
        "${fixture}/scripts/hooks/first-commit-version-bump.sh"

    git -C "${fixture}" init -q
    git -C "${fixture}" config user.email hooks-setup-test@example.invalid
    git -C "${fixture}" config user.name hooks-setup-test
    printf '%s\n' "${fixture}"
}

fixture="$(setup_fixture)"

# shellcheck source=/dev/null
source "${fixture}/scripts/lib/configure-git-hooks.sh"
configure_git_hooks "${fixture}" || fail "configure_git_hooks failed"

hooks_path="$(git -C "${fixture}" config --local --get core.hooksPath)"
test "${hooks_path}" = "scripts/hooks" || fail "expected scripts/hooks, got ${hooks_path}"

non_exec="$(find "${fixture}/scripts/hooks" -maxdepth 1 -type f ! -perm -u+x -print)"
test -z "${non_exec}" || fail "non-executable hooks: ${non_exec}"

overwrite_fixture="$(setup_fixture)"
git -C "${overwrite_fixture}" config --local core.hooksPath custom-hooks
# shellcheck source=/dev/null
source "${overwrite_fixture}/scripts/lib/configure-git-hooks.sh"
output="$(configure_git_hooks "${overwrite_fixture}" 2>&1)" || fail "overwrite configure_git_hooks failed: ${output}"
printf '%s\n' "${output}" | grep -Fq "Warning: overwriting core.hooksPath 'custom-hooks'" \
    || fail "expected overwrite warning, got: ${output}"
hooks_path="$(git -C "${overwrite_fixture}" config --local --get core.hooksPath)"
test "${hooks_path}" = "scripts/hooks" || fail "expected scripts/hooks after overwrite, got ${hooks_path}"

keep_fixture="$(setup_fixture)"
git -C "${keep_fixture}" config --local core.hooksPath custom-hooks
# shellcheck source=/dev/null
source "${keep_fixture}/scripts/lib/configure-git-hooks.sh"
output="$(MA_KEEP_HOOKS_PATH=1 configure_git_hooks "${keep_fixture}" 2>&1)" || fail "keep-path configure_git_hooks failed: ${output}"
printf '%s\n' "${output}" | grep -Fq "Skipping hooksPath configuration (MA_KEEP_HOOKS_PATH=1)" \
    || fail "expected keep-path skip message, got: ${output}"
hooks_path="$(git -C "${keep_fixture}" config --local --get core.hooksPath)"
test "${hooks_path}" = "custom-hooks" || fail "expected custom-hooks preserved, got ${hooks_path}"

echo "HOOKS_SETUP_TEST_STATUS=PASS"
