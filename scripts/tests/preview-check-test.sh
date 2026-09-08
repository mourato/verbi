#!/bin/bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-preview-check.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    printf '%s\n' "$1" | grep -Fq -- "$2" || fail "missing: $2"
}

fixture="${TMP_ROOT}/fixture"
mkdir -p "${fixture}"
cp "${SCRIPT_ROOT}/scripts/preview-check.sh" "${TMP_ROOT}/preview-check.sh"
chmod +x "${TMP_ROOT}/preview-check.sh"

cat > "${fixture}/SiblingPreview.swift" <<'EOF'
import SwiftUI

struct SiblingPreview: View {
    var body: some View { Text("Preview") }
}

#Preview { SiblingPreview() }
EOF

cat > "${fixture}/MissingPreview.swift" <<'EOF'
import SwiftUI

struct MissingPreview: View {
    var body: some View { Text("Missing") }
}

// #Preview { MissingPreview() } is not a declaration.
EOF

set +e
output="$(${TMP_ROOT}/preview-check.sh "${fixture}" 2>&1)"
status=$?
set -e
test "$status" -eq 1 || fail "a view without its own preview must fail"
assert_contains "$output" "Missing preview declarations in:"
assert_contains "$output" "MissingPreview.swift"

rm "${fixture}/MissingPreview.swift"
cat > "${fixture}/OwnPreview.swift" <<'EOF'
import SwiftUI

struct OwnPreview: View {
    var body: some View { Text("Own") }
}

#Preview { OwnPreview() }
EOF

cat > "${fixture}/Generated.swift" <<'EOF'
// preview-check: generated
import SwiftUI

struct Generated: View {
    var body: some View { Text("Generated") }
}
EOF

output="$(${TMP_ROOT}/preview-check.sh "${fixture}")"
assert_contains "$output" "Preview declaration coverage PASS: 2 view files checked, 1 explicitly excluded ("
assert_contains "$output" "does not compile or render previews"

help_output="$(${TMP_ROOT}/preview-check.sh --help)"
assert_contains "$help_output" "preview-check: ignore"
echo "PREVIEW_CHECK_TEST_STATUS=PASS"
