#!/bin/bash
# build-and-run.sh - Build Debug or install the signed Release app transactionally.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/scripts/config/app_identity.sh"
CONFIGURATION=""; CLEAN=0; NO_INTERACTIVE=0; FORCE_TERMINATE=0; SKIP_LAUNCH=0
CONFIRM_INSTALL=1
APPLICATIONS_DIR="${VERBI_APPLICATIONS_DIR:-/Applications}"
SHUTDOWN_TIMEOUT="${VERBI_SHUTDOWN_TIMEOUT_SECONDS:-15}"; STARTUP_TIMEOUT="${VERBI_STARTUP_TIMEOUT_SECONDS:-15}"
APP_BUNDLE_IDENTIFIER="$(/usr/bin/plutil -extract technical.bundleIdentifier raw -o - "${PROJECT_ROOT}/Config/AppIdentity.plist" 2>/dev/null || true)"
usage() { cat <<'USAGE'
Usage: scripts/build-and-run.sh [options]

Build Debug for local iteration or build/sign/install Release into the exact Verbi.app target.
Options:
  --configuration Debug|Release  Select a deterministic build mode.
  --clean                       Remove .xcode-build before building (default: keep cache).
  --no-interactive              Never read stdin; requires --configuration.
  --force-terminate             Allow exact-process TERM fallback after graceful timeout.
  --skip-launch                 Verify Release installation without relaunching it.
  --yes                         Skip the Release replacement confirmation.
  --shutdown-timeout SECONDS    Graceful shutdown wait (default: 15).
  --startup-timeout SECONDS     Launch verification wait (default: 15).
  --applications-dir PATH       Test-only applications root; defaults to /Applications.
  --help                        Show this help without building.
USAGE
}
fail() { echo "Error: $*" >&2; exit 1; }
confirm_default_yes() {
    local reply
    read -r -p "$1 [Y/n]: " reply < /dev/tty || reply=""
    case "$reply" in ""|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
confirm_default_no() {
    local reply
    read -r -p "$1 [y/N]: " reply < /dev/tty || reply=""
    case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
prompt_clean() {
    if confirm_default_no "Clean build artifacts first?"; then
        CLEAN=1
    fi
}
require_positive_integer() { [[ "$1" =~ ^[1-9][0-9]*$ ]] || fail "timeout must be a positive integer: $1"; }
validate_applications_dir() {
    local root="$1" resolved
    [ -d "$root" ] || fail "applications directory does not exist: $root"
    resolved="$(cd "$root" && pwd -P)"
    [ "$resolved" != "/" ] || fail "refusing the filesystem root as an installation target"
    [ "$resolved" != "${HOME:-}" ] || fail "refusing the home directory as an installation target"
    printf '%s\n' "$resolved"
}
bundle_path() { printf '%s/%s.app\n' "$1" "$APP_PRODUCT_NAME"; }
validate_bundle() {
    local bundle="$1" identifier
    [ -d "$bundle" ] || return 1
    [ "$(basename "$bundle")" = "${APP_PRODUCT_NAME}.app" ] || return 1
    [ -f "$bundle/Contents/Info.plist" ] || return 1
    identifier="$(plutil -extract CFBundleIdentifier raw -o - "$bundle/Contents/Info.plist" 2>/dev/null || true)"
    [ "$identifier" = "$APP_BUNDLE_IDENTIFIER" ] || return 1
    [ -f "$bundle/Contents/MacOS/${APP_PRODUCT_NAME}" ] || return 1
    codesign --verify --deep --strict "$bundle" >/dev/null 2>&1 || return 1
}
app_process_pids() { pgrep -x "$APP_PRODUCT_NAME" 2>/dev/null || true; }

process_uses_binary() {
    local pid="$1" expected_binary="$2"
    /usr/sbin/lsof -a -p "$pid" -d txt -Fn 2>/dev/null \
        | awk -v expected="n$expected_binary" '$0 == expected { found = 1 } END { exit !found }'
}

wait_for_exit() {
    local deadline=$((SECONDS + SHUTDOWN_TIMEOUT))
    while [ "$SECONDS" -lt "$deadline" ]; do [ -z "$(app_process_pids)" ] && return 0; sleep 1; done
    return 1
}

wait_for_app_binary() {
    local expected_binary="$1" deadline pid
    deadline=$((SECONDS + STARTUP_TIMEOUT))
    while [ "$SECONDS" -lt "$deadline" ]; do
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            if process_uses_binary "$pid" "$expected_binary"; then
                printf '%s\n' "$pid"
                return 0
            fi
        done < <(app_process_pids)
        sleep 1
    done
    echo "Error: ${APP_PRODUCT_NAME} did not start the expected executable within ${STARTUP_TIMEOUT}s: $expected_binary" >&2
    return 1
}

stop_running_apps() {
    local pids pid
    pids="$(app_process_pids)"
    [ -z "$pids" ] && return 0
    echo "Requesting graceful shutdown for existing ${APP_PRODUCT_NAME} process(es)..."
    osascript -e "tell application id \"${APP_BUNDLE_IDENTIFIER}\" to quit" >/dev/null 2>&1 || true
    wait_for_exit && return 0
    [ "$FORCE_TERMINATE" -eq 1 ] || fail "Verbi did not terminate gracefully within ${SHUTDOWN_TIMEOUT}s; rerun with --force-terminate only if intended"
    echo "Graceful shutdown timed out; using explicit TERM fallback for PID(s): ${pids}" >&2
    while IFS= read -r pid; do [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true; done <<< "$pids"
    wait_for_exit || fail "${APP_PRODUCT_NAME} remained running after SIGTERM"
}
rollback() {
    local target="$1" backup="$2"; rm -rf "$target"
    if [ -d "$backup" ]; then mv "$backup" "$target"; echo "Rollback restored ${target}" >&2; else echo "Rollback had no previous bundle to restore" >&2; fi
}
install_release() {
    local candidate="$PROJECT_ROOT/dist/${APP_PRODUCT_NAME}.app" target stage backup had_backup=0
    target="$(bundle_path "$APPLICATIONS_DIR")"; stage="${target}.stage.$$"; backup="${target}.backup.$$"
    validate_bundle "$candidate" || fail "Release candidate is not installable"
    case "$target" in "${APPLICATIONS_DIR}/${APP_PRODUCT_NAME}.app") ;; *) fail "Refusing unexpected installation target: $target" ;; esac
    if [ "$CONFIRM_INSTALL" -eq 1 ] && [ "$NO_INTERACTIVE" -eq 0 ] && ! confirm_default_yes "Replace ${target} with the signed Release build?"; then
        echo "Installation cancelled"
        return 0
    fi
    stop_running_apps; rm -rf "$stage"
    ditto "$candidate" "$stage" || { rm -rf "$stage"; fail "Could not stage Release candidate"; }
    if [ -e "$target" ]; then mv "$target" "$backup" || { rm -rf "$stage"; fail "Could not create installation backup"; }; had_backup=1; fi
    if ! mv "$stage" "$target" || ! validate_bundle "$target"; then rm -rf "$stage"; [ "$had_backup" -eq 1 ] && mv "$backup" "$target"; fail "Release installation failed; rollback was attempted"; fi
    if ! "$PROJECT_ROOT/scripts/clean-launch-services.sh" "$target"; then rollback "$target" "$backup"; fail "Could not clean stale LaunchServices registrations; rollback attempted"; fi
    if [ "$SKIP_LAUNCH" -eq 0 ]; then
        open -n "$target" >/dev/null 2>&1 || { rollback "$target" "$backup"; fail "Release app failed to launch"; }
        wait_for_app_binary "$target/Contents/MacOS/${APP_PRODUCT_NAME}" >/dev/null || { rollback "$target" "$backup"; fail "Release app did not remain alive after launch"; }
    fi
    rm -rf "$backup"; echo "Installed and validated ${target}"
}
run_selected() {
    [ "$CLEAN" -eq 1 ] && rm -rf "$PROJECT_ROOT/.xcode-build"
    stop_running_apps
    if [ "$CONFIGURATION" = "Debug" ]; then
        "$PROJECT_ROOT/scripts/run-build.sh" --configuration Debug
        local app_bundle="$PROJECT_ROOT/.xcode-build/Build/Products/Debug/${APP_PRODUCT_NAME}.app"
        validate_bundle "$app_bundle" || fail "Debug app bundle failed validation: $app_bundle"
        stop_running_apps
        open -n "$app_bundle"
        local pid
        if ! pid="$(wait_for_app_binary "$app_bundle/Contents/MacOS/${APP_PRODUCT_NAME}")"; then
            fail "${APP_PRODUCT_NAME} did not remain running from the expected executable."
        fi
        echo "Launched ${app_bundle} (pid ${pid})"
    else
        local release_signing_mode="${MA_RELEASE_SIGNING_MODE:-}"
        if [ -z "$release_signing_mode" ]; then
            # shellcheck source=scripts/config/release_signing.sh
            source "${PROJECT_ROOT}/scripts/config/release_signing.sh"
            release_signing_mode="$(ma_autodetect_release_signing_mode)"
        fi
        MA_RELEASE_SIGNING_MODE="$release_signing_mode" "$PROJECT_ROOT/scripts/build-release.sh" --no-interactive
        install_release
    fi
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration) [ $# -ge 2 ] || fail "--configuration requires Debug or Release"; CONFIGURATION="$2"; shift 2 ;;
        --clean) CLEAN=1; shift ;;
        --no-interactive) NO_INTERACTIVE=1; shift ;;
        --force-terminate) FORCE_TERMINATE=1; shift ;;
        --shutdown-timeout) [ $# -ge 2 ] || fail "--shutdown-timeout requires a value"; SHUTDOWN_TIMEOUT="$2"; shift 2 ;;
        --startup-timeout) [ $# -ge 2 ] || fail "--startup-timeout requires a value"; STARTUP_TIMEOUT="$2"; shift 2 ;;
        --skip-launch) SKIP_LAUNCH=1; shift ;;
        --yes) CONFIRM_INSTALL=0; shift ;;
        --applications-dir) [ $# -ge 2 ] || fail "--applications-dir requires a path"; APPLICATIONS_DIR="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown option: $1" ;;
    esac
done
require_positive_integer "$SHUTDOWN_TIMEOUT"; require_positive_integer "$STARTUP_TIMEOUT"
[[ -x /usr/sbin/lsof ]] || fail "Missing required command: /usr/sbin/lsof"
command -v osascript >/dev/null 2>&1 || fail "Missing required command: osascript"
if [ "$NO_INTERACTIVE" -eq 1 ]; then
    [ -n "$CONFIGURATION" ] || fail "--no-interactive requires --configuration Debug|Release"
elif [ -z "$CONFIGURATION" ]; then
    [ -t 0 ] && [ -t 1 ] || fail "interactive selection requires a TTY; pass --no-interactive --configuration ..."
    printf '%s\n' '1) Debug' '2) Release (default)' '3) Exit'; read -r -p "Choose [1/2/3] [2]: " choice
    case "$choice" in 1) CONFIGURATION=Debug ;; 2|'') CONFIGURATION=Release ;; 3) exit 0 ;; *) fail "invalid choice: $choice" ;; esac
    prompt_clean
fi
case "$CONFIGURATION" in Debug) ;; Release) APPLICATIONS_DIR="$(validate_applications_dir "$APPLICATIONS_DIR")" ;; *) fail "configuration must be Debug or Release" ;; esac
run_selected
