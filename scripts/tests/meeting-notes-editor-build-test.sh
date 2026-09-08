#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-meeting-notes-editor-build-test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

fail() {
    echo "MEETING_NOTES_EDITOR_BUILD_TEST_STATUS=FAIL ($1)" >&2
    exit 1
}

fixture="${TMP_ROOT}/fixture"
bin_dir="${TMP_ROOT}/bin"
mkdir -p "${fixture}/scripts" "${fixture}/Editor/dist" "${fixture}/Editor/node_modules" "${fixture}/Packages/MeetingAssistantCore/Sources/UI/Resources/MeetingNotesEditor/dist" "${bin_dir}"
cp "${SCRIPT_ROOT}/scripts/build-meeting-notes-editor.sh" "${fixture}/scripts/build-meeting-notes-editor.sh"
chmod +x "${fixture}/scripts/build-meeting-notes-editor.sh"

cat > "${bin_dir}/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  install) exit 0 ;;
  run)
    shift
    [[ "${1:-}" == "build" ]] || exit 1
    printf '%s\n' "fixture bundle rebuilt" > dist/main.js
    exit 0
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${bin_dir}/npm"

printf '%s\n' '{"name":"fixture-editor","private":true,"type":"module","scripts":{"build":"node build.mjs"}}' > "${fixture}/Editor/package.json"
printf '%s\n' '{}' > "${fixture}/Editor/package-lock.json"
touch "${fixture}/Editor/node_modules/.package-lock.json"
printf '%s\n' 'fixture bundle v1' > "${fixture}/Editor/dist/main.js"
cp "${fixture}/Editor/dist/main.js" "${fixture}/Packages/MeetingAssistantCore/Sources/UI/Resources/MeetingNotesEditor/dist/main.js"

run_build() {
  cd "${fixture}" && PATH="${bin_dir}:/bin:/usr/bin" ./scripts/build-meeting-notes-editor.sh 2>&1
}

output="$(run_build)"
printf '%s\n' "${output}" | grep -Fq 'up to date' || fail "expected skip when bundle is current"

printf '%s\n' 'changed source' > "${fixture}/Editor/source.ts"
output="$(run_build)"
printf '%s\n' "${output}" | grep -Fq 'bundle copied' || fail "expected rebuild when editor sources change"
grep -Fq 'fixture bundle rebuilt' "${fixture}/Packages/MeetingAssistantCore/Sources/UI/Resources/MeetingNotesEditor/dist/main.js" || fail "expected rebuilt bundle content"

echo "MEETING_NOTES_EDITOR_BUILD_TEST_STATUS=PASS"
