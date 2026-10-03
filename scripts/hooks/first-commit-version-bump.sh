#!/bin/bash
# Bump app version on first commit of the day using format: <major>.<month>.<day>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_PLIST="${PROJECT_ROOT}/App/Info.plist"
BUMP_SCRIPT="${PROJECT_ROOT}/scripts/bump-version.sh"

if [[ "${SKIP_DAILY_VERSION_BUMP:-0}" == "1" ]]; then
    exit 0
fi

force_bump="${FORCE_DAILY_VERSION_BUMP:-0}"

if [[ ! -x "${BUMP_SCRIPT}" ]]; then
    echo "⚠️  Daily version bump skipped: missing executable ${BUMP_SCRIPT}"
    exit 0
fi

if [[ ! -f "${APP_PLIST}" ]]; then
    echo "⚠️  Daily version bump skipped: missing ${APP_PLIST}"
    exit 0
fi

git_user_email="$(git config user.email || true)"
if [[ -z "${git_user_email}" ]]; then
    echo "⚠️  Daily version bump skipped: git user.email is not configured."
    exit 0
fi

# Repo-wide check: if this author already committed today, skip bump unless forced.
if [[ "${force_bump}" != "1" ]]; then
    if git log --all --author="${git_user_email}" --since="today 00:00:00" --format="%H" -n 1 | grep -q .; then
        exit 0
    fi
fi

current_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PLIST}")"
current_build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PLIST}")"

major="${current_version%%.*}"
if [[ ! "${major}" =~ ^[0-9]+$ ]]; then
    echo "⚠️  Daily version bump skipped: invalid current version '${current_version}'."
    exit 0
fi

month_raw="$(date +%m)"
day_raw="$(date +%d)"
month="$((10#${month_raw}))"
day="$((10#${day_raw}))"
target_version="${major}.${month}.${day}"

if [[ "${current_version}" == "${target_version}" && "${force_bump}" != "1" ]]; then
    exit 0
fi

if [[ ! "${current_build}" =~ ^[0-9]+$ ]]; then
    echo "⚠️  Daily version bump skipped: invalid build '${current_build}'."
    exit 0
fi
next_build="$((current_build + 1))"

# bump-version.sh rewrites and git-adds these complete paths. Once a bump is
# known to be necessary, fail before mutation if any contains unstaged work.
bump_paths=(
    "App/Info.plist"
    "Packages/MeetingAssistantCore/Sources/Common/AppVersion.swift"
)
dirty_bump_paths=()
for file in "${bump_paths[@]}"; do
    if ! git diff --quiet -- "${file}"; then
        dirty_bump_paths+=("${file}")
    fi
done

if [[ "${#dirty_bump_paths[@]}" -gt 0 ]]; then
    echo "❌ Cannot run the daily version bump with unstaged changes in version files:"
    for file in "${dirty_bump_paths[@]}"; do
        printf '   - %s\n' "${file}"
    done
    echo "   Stage or stash those changes, then retry."
    exit 1
fi

"${BUMP_SCRIPT}" --version "${target_version}" --build "${next_build}" >/dev/null
git add "${bump_paths[@]}"

echo "📌 Daily version bump applied: ${target_version} (build ${next_build})"
