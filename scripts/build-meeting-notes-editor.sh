#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
EDITOR_DIR="$ROOT/Editor"
OUTPUT_DIR="$ROOT/Packages/VerbiCore/Sources/UI/Resources/MeetingNotesEditor/dist"
BUNDLE_MARKER="$OUTPUT_DIR/main.js"

if [[ ! -d "$EDITOR_DIR" ]]; then
  echo "Editor/ package not found; using committed dist bundle." >&2
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found; using committed MeetingNotesEditor dist bundle." >&2
  exit 0
fi

editor_sources_newer_than_bundle() {
  [[ -f "$BUNDLE_MARKER" ]] || return 0
  find "$EDITOR_DIR" \
    \( -path "$EDITOR_DIR/node_modules" -o -path "$EDITOR_DIR/node_modules/*" -o -path "$EDITOR_DIR/dist" -o -path "$EDITOR_DIR/dist/*" \) -prune \
    -o -type f -newer "$BUNDLE_MARKER" -print -quit | grep -q .
}

needs_node_modules_refresh() {
  [[ -d "$EDITOR_DIR/node_modules" ]] || return 0
  [[ -f "$EDITOR_DIR/package-lock.json" ]] || return 0
  [[ "$EDITOR_DIR/package-lock.json" -nt "$EDITOR_DIR/node_modules/.package-lock.json" ]]
}

if ! editor_sources_newer_than_bundle; then
  echo "Meeting notes editor bundle is up to date at $OUTPUT_DIR"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"
pushd "$EDITOR_DIR" >/dev/null
if needs_node_modules_refresh; then
  npm install
else
  echo "node_modules up to date; skipping npm install"
fi
npm run build
popd >/dev/null

rsync -a --delete "$EDITOR_DIR/dist/" "$OUTPUT_DIR/"
echo "Meeting notes editor bundle copied to $OUTPUT_DIR"
