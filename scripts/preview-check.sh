#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="Packages/VerbiCore/Sources/UI"

usage() {
    cat <<'EOF'
Usage: preview-check.sh [--settings | TARGET_DIR]

Checks that every SwiftUI view source file contains its own #Preview or
PreviewProvider declaration. Files may opt out only with an explicit
"preview-check: ignore" or "preview-check: generated" comment.

This command checks declaration coverage only. It does not compile or render
previews.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

SETTINGS_ONLY=0
if [[ "${1:-}" == "--settings" ]]; then
    SETTINGS_ONLY=1
    shift
fi

if [[ "$#" -gt 1 ]]; then
    usage >&2
    exit 2
fi

if [[ "$#" -eq 1 ]]; then
    TARGET_DIR="$1"
fi

if [[ "$SETTINGS_ONLY" -eq 1 && "$#" -eq 0 ]]; then
    SEARCH_PATHS=(
        "Packages/VerbiCore/Sources/UI/pages/settings"
        "Packages/VerbiCore/Sources/UI/components/settings"
    )
else
    SEARCH_PATHS=("$TARGET_DIR")
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "error: 'rg' (ripgrep) is required" >&2
  exit 2
fi

view_files="$(rg -l --glob '*.swift' 'struct[[:space:]]+\w+[[:space:]]*:[[:space:]]*View' "${SEARCH_PATHS[@]}" || true)"

if [[ -z "$view_files" ]]; then
  echo "No SwiftUI views found under $TARGET_DIR"
  exit 0
fi

missing=""
checked=0
excluded=0
while IFS= read -r view_file; do
    [[ -z "$view_file" ]] && continue
    if rg -q 'preview-check:[[:space:]]*(ignore|generated)' "$view_file"; then
        excluded=$((excluded + 1))
        continue
    fi

    checked=$((checked + 1))
    if ! rg -q '^[[:space:]]*#Preview([[:space:](]|$)|^[[:space:]]*(struct|final[[:space:]]+class|class)[[:space:]]+[^:]+:[[:space:]]*PreviewProvider([[:space:]]|$)' "$view_file"; then
        missing+="${view_file}\n"
    fi
done <<< "$view_files"

if [[ -n "$missing" ]]; then
  echo "Missing preview declarations in:"
  printf "%b" "$missing"
  exit 1
fi

scope_label="$TARGET_DIR"
if [[ "$SETTINGS_ONLY" -eq 1 ]]; then
    scope_label="Settings sources"
fi
echo "Preview declaration coverage PASS: ${checked} view files checked, ${excluded} explicitly excluded (${scope_label})."
echo "This command checks declarations only; it does not compile or render previews."
