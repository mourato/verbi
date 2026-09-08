#!/usr/bin/env bash
set -euo pipefail

# test-hygiene: this is an explicit live microphone/AppKit exception. It is
# opt-in, uses a stable isolated bundle/defaults domain and temporary HOME,
# and the trap removes the launched process and seeded state.

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_NAME='Verbi'
BUNDLE_ID='com.mourato.verbi.runtime-smoke'
STARTUP_TIMEOUT="${VERBI_RUNTIME_SMOKE_TIMEOUT:-40}"

if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then
    cat <<'EOF'
Usage: scripts/runtime-smoke.sh

Builds Debug, launches an isolated app instance, requests microphone dictation
through the DEBUG runtime hook, and waits for the recorder-start marker.
The smoke requires microphone permission for com.mourato.verbi.runtime-smoke.
EOF
    exit 0
fi

[[ $# -eq 0 ]] || { printf 'error: unknown argument: %s\n' "$1" >&2; exit 2; }
[[ "$STARTUP_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { printf 'error: invalid startup timeout\n' >&2; exit 2; }

BUILD_ROOT="$PROJECT_ROOT/.xcode-build"
mkdir -p "$BUILD_ROOT"
DERIVED_DATA="$(mktemp -d "$BUILD_ROOT/runtime-smoke.XXXXXX")"
LOG_PATH="$DERIVED_DATA/runtime.log"
HOME_ROOT="$DERIVED_DATA/home"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
PID=''

cleanup() {
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.2
        done
        if kill -0 "$PID" 2>/dev/null; then
            kill -KILL "$PID" 2>/dev/null || true
        fi
        wait "$PID" 2>/dev/null || true
    fi
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$DERIVED_DATA"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'RUNTIME_SMOKE: FAIL reason=%s\n' "$1" >&2
    if [[ -s "$LOG_PATH" ]]; then
        grep -E '^RUNTIME_SMOKE:' "$LOG_PATH" >&2 || true
    fi
    exit 1
}

mkdir -p "$HOME_ROOT"
defaults write "$BUNDLE_ID" hasCompletedOnboarding -bool true
defaults write "$BUNDLE_ID" isMeetingTranscriptionEnabled -bool false
defaults write "$BUNDLE_ID" isAssistantEnabled -bool false
defaults write "$BUNDLE_ID" isAssistantIntegrationsEnabled -bool false
defaults write "$BUNDLE_ID" autoStartRecording -bool false
defaults write "$BUNDLE_ID" showSettingsOnLaunch -bool false
defaults write "$BUNDLE_ID" recordingIndicatorEnabled -bool false

if ! "$PROJECT_ROOT/scripts/xcodebuild-safe.sh" \
    --project "$PROJECT_ROOT/MeetingAssistant.xcodeproj" \
    --scheme MeetingAssistant \
    --configuration Debug \
    --derived-data "$DERIVED_DATA" \
    --destination 'platform=macOS' \
    --action build \
    -- APP_BUNDLE_ID="$BUNDLE_ID" >"$LOG_PATH" 2>&1; then
    fail 'debug build failed'
fi

[[ -x "$APP_PATH/Contents/MacOS/$APP_NAME" ]] || fail 'built executable is missing'
printf 'RUNTIME_SMOKE: BUILT bundle=%s\n' "$BUNDLE_ID"

MA_RUNTIME_SMOKE=recording-start HOME="$HOME_ROOT" \
    "$APP_PATH/Contents/MacOS/$APP_NAME" >"$LOG_PATH" 2>&1 &
PID=$!

for _ in $(seq 1 "$STARTUP_TIMEOUT"); do
    if grep -q '^RUNTIME_SMOKE: PASS recording-start$' "$LOG_PATH" 2>/dev/null; then
        printf 'RUNTIME_SMOKE: PASS recording-start\n'
        exit 0
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
        wait "$PID" 2>/dev/null || true
        fail 'app exited before recording start passed'
    fi
    sleep 1
done

fail 'recording start timed out'
