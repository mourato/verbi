#!/usr/bin/env bash
set -euo pipefail

# Determine repo locations before performing updates.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_VERSION_FILE="$REPO_ROOT/Packages/MeetingAssistantCore/Sources/Common/AppVersion.swift"
APP_PLIST="$REPO_ROOT/App/Info.plist"

usage() {
  cat <<'EOF' >&2
Usage: bump-version.sh --version <semantic> --build <number>
  -v | --version  New CFBundleShortVersionString value (e.g. 1.2.3)
  -b | --build    New CFBundleVersion value (e.g. 42)
  -h | --help     Show this help text
EOF
  exit 1
}

version=""
build=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--version)
      if [[ $# -lt 2 ]]; then
        usage
      fi
      version="$2"
      shift 2
      ;;
    -b|--build)
      if [[ $# -lt 2 ]]; then
        usage
      fi
      build="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$version" || -z "$build" ]]; then
  usage
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build" =~ ^[0-9]+$ ]]; then
  echo "Version must use major.minor.patch and build must be a non-negative integer." >&2
  exit 1
fi

# Validate plist fields before writing Swift constants, so stale paths or a
# malformed plist cannot leave a partially applied bump.
if [[ ! -f "$APP_PLIST" ]]; then
  echo "Missing plist: $APP_PLIST" >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST" >/dev/null

update_app_version_constants() {
  python3 - "$APP_VERSION_FILE" "$version" "$build" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f"Missing AppVersion file: {path}")
content = path.read_text()
content, version_count = re.subn(r'private static let hardcodedVersion = "[^"]*"',
                                     f'private static let hardcodedVersion = "{sys.argv[2]}"',
                                     content,
                                     count=1)
content, build_count = re.subn(r'private static let hardcodedBuild = "[^"]*"',
                                   f'private static let hardcodedBuild = "{sys.argv[3]}"',
                                   content,
                                   count=1)
if version_count != 1 or build_count != 1:
    raise SystemExit("AppVersion.swift pattern mismatch while updating constants")
path.write_text(content)
PY
}

update_plist_versions() {
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$APP_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$APP_PLIST"
}

main() {
  update_app_version_constants
  update_plist_versions
  echo "Synchronized version to $version (build $build)"
}

main
