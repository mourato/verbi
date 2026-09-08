#!/bin/bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-guidance-validation-test.XXXXXX")"
FAILURES=0
trap 'rm -rf "${TMP_ROOT}"' EXIT

record_failure() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

new_fixture() {
    local name="$1"
    local fixture="${TMP_ROOT}/${name}"

    mkdir -p "${fixture}/scripts" \
        "${fixture}/.agents/docs" \
        "${fixture}/.agents/skills"
    cp "${SCRIPT_ROOT}/scripts/validate-agent-guidance.py" \
        "${fixture}/scripts/validate-agent-guidance.py"
    chmod +x "${fixture}/scripts/validate-agent-guidance.py"
    printf '%s\n' '# Fixture guidance' > "${fixture}/AGENTS.md"
    printf '%s\n' 'fixture-target:' $'\t@true' > "${fixture}/Makefile"
    printf '%s\n' '# Skill Routing' > "${fixture}/.agents/docs/skill-routing.md"
    printf '%s\n' "${fixture}"
}

add_skill() {
    local fixture="$1"
    local name="${2:-fixture-skill}"
    local skill_dir="${fixture}/.agents/skills/${name}"

    mkdir -p "${skill_dir}/references"
    printf '%s\n' '' "Use \`${name}\`." \
        >> "${fixture}/.agents/docs/skill-routing.md"
    printf '%s\n' \
        '---' \
        "name: ${name}" \
        'description: Fixture skill.' \
        '---' \
        '' \
        '# Fixture Skill' \
        '' \
        '## Role' \
        '' \
        'Own fixture validation.' \
        '' \
        '## Scope Boundary' \
        '' \
        'Stay inside the fixture.' \
        '' \
        '## When to Use' \
        '' \
        'Use for fixture validation.' \
        > "${skill_dir}/SKILL.md"
}

run_validator() {
    local fixture="$1"
    local output_file="$2"
    local status

    set +e
    (cd "${fixture}" && python3 scripts/validate-agent-guidance.py) \
        > "${output_file}" 2>&1
    status=$?
    set -e
    printf '%s\n' "${status}"
}

expect_pass() {
    local name="$1"
    local fixture="$2"
    local output_file="${TMP_ROOT}/${name}.out"
    local status

    status="$(run_validator "${fixture}" "${output_file}")"
    if [ "${status}" -ne 0 ]; then
        record_failure "${name} expected PASS: $(cat "${output_file}")"
    fi
}

expect_fail() {
    local name="$1"
    local fixture="$2"
    shift 2
    local output_file="${TMP_ROOT}/${name}.out"
    local status
    local needle

    status="$(run_validator "${fixture}" "${output_file}")"
    if [ "${status}" -eq 0 ]; then
        record_failure "${name} expected validator failure"
        return
    fi
    for needle in "$@"; do
        if ! grep -Fq -- "${needle}" "${output_file}"; then
            record_failure "${name} missing diagnostic '${needle}': $(cat "${output_file}")"
        fi
    done
}

test_valid_nested_reference() {
    local fixture

    fixture="$(new_fixture valid-nested-reference)"
    add_skill "${fixture}"
    printf '%s\n' '' '[Nested guidance](references/nested.md)' \
        >> "${fixture}/.agents/skills/fixture-skill/SKILL.md"
    printf '%s\n' '# Nested guidance' \
        > "${fixture}/.agents/skills/fixture-skill/references/nested.md"
    expect_pass valid-nested-reference "${fixture}"
}

test_orphan_skill_directory() {
    local fixture

    fixture="$(new_fixture orphan-skill-directory)"
    mkdir -p "${fixture}/.agents/skills/orphan-skill/references"
    printf '%s\n' '# Orphan guidance' \
        > "${fixture}/.agents/skills/orphan-skill/references/dead.md"
    expect_fail orphan-skill-directory "${fixture}" 'orphan-skill'
}

test_broken_nested_markdown_link() {
    local fixture

    fixture="$(new_fixture broken-nested-link)"
    add_skill "${fixture}"
    printf '%s\n' '# Nested guidance' '' '[Missing](missing.md)' \
        > "${fixture}/.agents/skills/fixture-skill/references/nested.md"
    expect_fail broken-nested-link "${fixture}" \
        '.agents/skills/fixture-skill/references/nested.md' \
        "Missing local reference 'missing.md'"
}

test_markdown_link_does_not_fall_back_to_repo_root() {
    local fixture

    fixture="$(new_fixture markdown-shadow-collision)"
    add_skill "${fixture}"
    printf '%s\n' '# Nested guidance' '' '[Shadow](AGENTS.md)' \
        > "${fixture}/.agents/skills/fixture-skill/references/nested.md"
    expect_fail markdown-shadow-collision "${fixture}" \
        '.agents/skills/fixture-skill/references/nested.md' \
        "Missing local reference 'AGENTS.md'"
}

test_valid_explicit_parent_reference() {
    local fixture

    fixture="$(new_fixture valid-explicit-parent-reference)"
    add_skill "${fixture}"
    printf '%s\n' '# Nested guidance' '' '[Skill](../SKILL.md)' \
        > "${fixture}/.agents/skills/fixture-skill/references/nested.md"
    expect_pass valid-explicit-parent-reference "${fixture}"
}

test_invalid_explicit_parent_reference() {
    local fixture

    fixture="$(new_fixture invalid-explicit-parent-reference)"
    add_skill "${fixture}"
    printf '%s\n' '# Nested guidance' '' '[Missing](../missing.md)' \
        > "${fixture}/.agents/skills/fixture-skill/references/nested.md"
    expect_fail invalid-explicit-parent-reference "${fixture}" \
        '.agents/skills/fixture-skill/references/nested.md' \
        "Missing local reference '../missing.md'"
}

test_broken_inline_reference() {
    local fixture

    fixture="$(new_fixture broken-inline-reference)"
    add_skill "${fixture}"
    printf '%s\n' '' 'Read `references/missing.md`.' \
        >> "${fixture}/.agents/skills/fixture-skill/SKILL.md"
    expect_fail broken-inline-reference "${fixture}" \
        '.agents/skills/fixture-skill/SKILL.md' \
        "Missing local reference 'references/missing.md'"
}

test_valid_inline_reference() {
    local fixture

    fixture="$(new_fixture valid-inline-reference)"
    add_skill "${fixture}"
    printf '%s\n' '# Existing guidance' \
        > "${fixture}/.agents/skills/fixture-skill/references/existing.md"
    printf '%s\n' '' 'Read `references/existing.md`.' \
        >> "${fixture}/.agents/skills/fixture-skill/SKILL.md"
    expect_pass valid-inline-reference "${fixture}"
}

test_inline_repo_root_reference_stays_valid() {
    local fixture

    fixture="$(new_fixture valid-inline-repo-root-reference)"
    add_skill "${fixture}"
    printf '%s\n' '' 'Read `AGENTS.md`.' \
        >> "${fixture}/.agents/skills/fixture-skill/SKILL.md"
    expect_pass valid-inline-repo-root-reference "${fixture}"
}

test_hidden_and_unexpected_skill_children() {
    local fixture

    fixture="$(new_fixture invalid-skill-children)"
    add_skill "${fixture}"
    printf '%s\n' 'hidden' \
        > "${fixture}/.agents/skills/fixture-skill/.secret"
    printf '%s\n' '# Unexpected' \
        > "${fixture}/.agents/skills/fixture-skill/unexpected.md"
    expect_fail invalid-skill-children "${fixture}" \
        "Hidden file or directory '.secret'" \
        "Unexpected file or directory 'unexpected.md'"
}

test_empty_local_skill_directory_is_ignored() {
    local fixture

    fixture="$(new_fixture empty-local-directory)"
    mkdir -p "${fixture}/.agents/skills/empty-local"
    expect_pass empty-local-directory "${fixture}"
}

test_valid_nested_reference
test_orphan_skill_directory
test_broken_nested_markdown_link
test_markdown_link_does_not_fall_back_to_repo_root
test_valid_explicit_parent_reference
test_invalid_explicit_parent_reference
test_broken_inline_reference
test_valid_inline_reference
test_inline_repo_root_reference_stays_valid
test_hidden_and_unexpected_skill_children
test_empty_local_skill_directory_is_ignored

if [ "${FAILURES}" -ne 0 ]; then
    echo "GUIDANCE_VALIDATION_TEST_STATUS=FAIL"
    exit 1
fi

echo "GUIDANCE_VALIDATION_TEST_STATUS=PASS"
