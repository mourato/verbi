#!/bin/bash
# =============================================================================
# xcodebuild-safe.sh - Canonical xcodebuild entrypoint for this repository
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=scripts/config/app_identity.sh
source "${PROJECT_DIR}/scripts/config/app_identity.sh"

XCODEPROJ="${PROJECT_DIR}/${XCODEPROJ_NAME}"
DERIVED_DATA_PATH="${PROJECT_DIR}/.xcode-build"

SCHEME="${APP_SCHEME}"
CONFIGURATION="Debug"
DESTINATION="platform=macOS"
ACTION="build"
DEPENDENCY_FINGERPRINT=""

EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scheme)
            SCHEME="$2"
            shift 2
            ;;
        --project)
            XCODEPROJ="$2"
            shift 2
            ;;
        --configuration|-c)
            CONFIGURATION="$2"
            shift 2
            ;;
        --derived-data)
            DERIVED_DATA_PATH="$2"
            shift 2
            ;;
        --destination)
            DESTINATION="$2"
            shift 2
            ;;
        --action)
            ACTION="$2"
            shift 2
            ;;
        --help|-h)
            cat <<'EOF'
Usage: scripts/xcodebuild-safe.sh [options] [-- <extra xcodebuild args>]

Options:
  --scheme <name>            Xcode scheme (default: ${APP_SCHEME})
  --project <path>           Xcode project path (default: <repo>/${XCODEPROJ_NAME})
  --configuration, -c <cfg>  Build configuration (default: Debug)
    --derived-data <path>      Derived data path (optional)
  --destination <dest>       Destination (default: platform=macOS)
  --action <action>          xcodebuild action (default: build)

Examples:
  scripts/xcodebuild-safe.sh
  scripts/xcodebuild-safe.sh --configuration Release
  scripts/xcodebuild-safe.sh --action test -- --enableCodeCoverage YES
EOF
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS+=("$@")
            break
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ! -d "${XCODEPROJ}" ]]; then
    echo "Error: Xcode project not found at ${XCODEPROJ}" >&2
    exit 1
fi

compute_dependency_fingerprint() {
    local fingerprint_files=()
    local file_path

    fingerprint_files+=("${PROJECT_DIR}/Packages/MeetingAssistantCore/Package.swift")
    fingerprint_files+=("${PROJECT_DIR}/Packages/MeetingAssistantCore/Package.resolved")
    fingerprint_files+=("${PROJECT_DIR}/Package.swift")
    fingerprint_files+=("${PROJECT_DIR}/MeetingAssistant.xcworkspace/xcshareddata/swiftpm/Package.resolved")

    for file_path in "${fingerprint_files[@]}"; do
        if [[ -f "${file_path}" ]]; then
            cat "${file_path}"
        fi
    done | shasum -a 256 | awk '{print $1}'
}

should_resolve_dependencies() {
    local marker_path="$1"
    local current_fingerprint
    local previous_fingerprint

    current_fingerprint="$(compute_dependency_fingerprint)"
    if [[ -z "${current_fingerprint}" ]]; then
        return 0
    fi
    DEPENDENCY_FINGERPRINT="${current_fingerprint}"

    if [[ -f "${marker_path}" ]] && [[ -d "${DERIVED_DATA_PATH}/SourcePackages/checkouts" ]]; then
        previous_fingerprint="$(cat "${marker_path}" 2>/dev/null || true)"
        if [[ "${previous_fingerprint}" = "${current_fingerprint}" ]]; then
            return 1
        fi
    fi

    return 0
}

mkdir -p "${DERIVED_DATA_PATH}"
MARKER_PATH="${DERIVED_DATA_PATH}/.ma-xcode-resolve-${SCHEME}.fingerprint"
if should_resolve_dependencies "${MARKER_PATH}"; then
    xcodebuild \
        -resolvePackageDependencies \
        -project "${XCODEPROJ}" \
        -scheme "${SCHEME}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" >/dev/null

    if [[ -n "${DEPENDENCY_FINGERPRINT}" ]]; then
        printf '%s\n' "${DEPENDENCY_FINGERPRINT}" > "${MARKER_PATH}"
    fi
fi

CMD=(
    xcodebuild
    -project "${XCODEPROJ}"
    -scheme "${SCHEME}"
    -configuration "${CONFIGURATION}"
)

if [[ -n "${DERIVED_DATA_PATH}" ]]; then
    CMD+=( -derivedDataPath "${DERIVED_DATA_PATH}" )
fi

CMD+=(
    -destination "${DESTINATION}"
    "${ACTION}"
)

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    CMD+=("${EXTRA_ARGS[@]}")
fi

# Apply to SwiftPM dependencies too; project-level ARCHS only constrains the app.
CMD+=(ARCHS=arm64)

"${CMD[@]}"
