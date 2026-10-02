#!/usr/bin/env bash
# Hook/index boundary checks for scripts/hooks/pre-commit using temp repos.
# Usage: scripts/test-precommit-hook.sh [SRC]
set -euo pipefail

SRC="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
HOOK="$SRC/scripts/hooks/pre-commit"
export AGENT_CONFIG_HOME="${AGENT_CONFIG_HOME:-$HOME/.agents}"

git_local() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES git "$@"
}

have_swift_tools=0
if command -v swiftformat >/dev/null 2>&1 && command -v swiftlint >/dev/null 2>&1; then
  have_swift_tools=1
fi

# Fresh fixture repo with the real hook and checker wiring plus the minimum
# tree both validators require.
make_fixture() {
  fix=$(mktemp -d "${TMPDIR:-/tmp}/verbi-hook-fixture.XXXXXX")
  git_local init -q -b main "$fix"
  git_local -C "$fix" config user.email test@example.com
  git_local -C "$fix" config user.name test
  mkdir -p "$fix/scripts/hooks" "$fix/scripts/lib" "$fix/.agents/docs" \
    "$fix/.agents/skills" "$fix/App" "$fix/docs" \
    "$fix/Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj" \
    "$fix/Packages/MeetingAssistantCore/Sources/Common/Resources/pt.lproj"
  cp "$SRC/scripts/validate-agent-guidance.py" "$SRC/scripts/check-localization.py" \
    "$SRC/scripts/lint.sh" "$fix/scripts/"
  cp -r "$SRC/scripts/lib/." "$fix/scripts/lib/"
  cp "$HOOK" "$fix/scripts/hooks/pre-commit"
  chmod +x "$fix/scripts/hooks/pre-commit"
  printf '%s\n' '# Agents' 'See [UI](docs/ui.md).' >"$fix/AGENTS.md"
  printf '%s\n' '# UI' >"$fix/docs/ui.md"
  printf '%s\n' '# Routing' 'Owner: `valid`.' >"$fix/.agents/docs/skill-routing.md"
  mkdir -p "$fix/.agents/skills/valid"
  printf '%s\n' '# Valid' '## Role' 'Fixture role.' '## When to Use' 'Fixture use.' '## Scope Boundary' 'Fixture scope.' >"$fix/.agents/skills/valid/SKILL.md"
  printf '%s\n' '.PHONY: check' 'check:' >"$fix/Makefile"
  printf '%s\n' 'import Foundation' >"$fix/App/Placeholder.swift"
  printf '%s\n' '"hello" = "hello";' >"$fix/Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj/Localizable.strings"
  printf '%s\n' '"hello" = "ola";' >"$fix/Packages/MeetingAssistantCore/Sources/Common/Resources/pt.lproj/Localizable.strings"
  git_local -C "$fix" add -A
  git_local -C "$fix" commit -qm init
}

run_hook() {
  case_tmp=$(mktemp -d "${TMPDIR:-/tmp}/verbi-hook-tmp.XXXXXX")
  # Real hooks run with the repo root as cwd; reproduce that here.
  set +e
  ( cd "$fix" && TMPDIR="$case_tmp" bash "$fix/scripts/hooks/pre-commit" >"$fix/hook.log" 2>&1 )
  status=$?
  set -e
  if [[ -z "$(ls -A "$case_tmp")" ]]; then
    rm -rf "$case_tmp"
  else
    printf 'leaked %s\n' "$case_tmp" >>"$fix/hook-leaks"
    rm -rf "$case_tmp"
  fi
  printf '%s' "$status"
}

fail_case() { printf 'hook test FAILED: %s\n' "$1" >&2; sed 's/^/  /' "$fix/hook.log" >&2; exit 1; }

make_fixture
trap 'rm -rf "$fix"' EXIT

# 1. Bad staged guidance is rejected with an actionable diagnostic.
printf '%s\n' '# Agents' 'See [gone](docs/missing.md).' >"$fix/AGENTS.md"
git_local -C "$fix" add AGENTS.md
[[ $(run_hook) != 0 ]] || fail_case 'bad staged guidance passed'
grep -q 'missing.md' "$fix/hook.log" || fail_case 'diagnostic lacks path'

# 2. Good staged guidance passes.
printf '%s\n' '# Agents' 'See [UI](docs/ui.md).' >"$fix/AGENTS.md"
git_local -C "$fix" add AGENTS.md
[[ $(run_hook) == 0 ]] || fail_case 'good staged guidance failed'

# 3. An unstaged fix cannot mask a broken staged commit.
printf '%s\n' '# Agents' 'See [gone](docs/missing.md).' >"$fix/AGENTS.md"
git_local -C "$fix" add AGENTS.md
printf '%s\n' '# Agents' 'See [UI](docs/ui.md).' >"$fix/AGENTS.md"
[[ $(run_hook) != 0 ]] || fail_case 'unstaged fix masked staged failure'

# 4. Unstaged breakage cannot fail a valid staged commit.
printf '%s\n' '# Agents' 'See [UI](docs/ui.md).' >"$fix/AGENTS.md"
git_local -C "$fix" add AGENTS.md
printf '%s\n' '# Agents' 'See [gone](docs/missing.md).' >"$fix/AGENTS.md"
[[ $(run_hook) == 0 ]] || fail_case 'unstaged breakage failed valid staged commit'
git_local -C "$fix" checkout -q -- AGENTS.md

# 5. Hook preserves the index and worktree and never stashes.
printf '%s\n' '# Agents' 'See [gone](docs/missing.md).' >"$fix/AGENTS.md"
git_local -C "$fix" add AGENTS.md
index_before=$(git_local -C "$fix" write-tree)
work_before=$(shasum -a 256 "$fix/AGENTS.md" | cut -d' ' -f1)
[[ $(run_hook) != 0 ]] || fail_case 'expected failure for preservation check'
[[ "$(git_local -C "$fix" write-tree)" == "$index_before" ]] || fail_case 'index changed by hook'
[[ "$(shasum -a 256 "$fix/AGENTS.md" | cut -d' ' -f1)" == "$work_before" ]] || fail_case 'worktree changed by hook'
[[ -z "$(git_local -C "$fix" stash list)" ]] || fail_case 'hook stashed changes'

# 6. Dangling skill symlinks fail the staged gate.
git_local -C "$fix" reset -q
ln -s nonexistent-target "$fix/.agents/skills/dangling"
printf '%s\n' '# Agents' 'See [UI](docs/ui.md).' >"$fix/AGENTS.md"
git_local -C "$fix" add AGENTS.md .agents/skills/dangling
[[ $(run_hook) != 0 ]] || fail_case 'dangling skill symlink passed'
grep -q 'Dangling skill symlink' "$fix/hook.log" || fail_case 'dangling diagnostic missing'
git_local -C "$fix" rm -q --cached .agents/skills/dangling
rm "$fix/.agents/skills/dangling"

# 7. Staged localization breakage fails; staged Swift key registration is checked.
git_local -C "$fix" reset -q
printf '%s\n' '"hello" = "hello";' '"bye" = "bye";' >"$fix/Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj/Localizable.strings"
git_local -C "$fix" add Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj/Localizable.strings
[[ $(run_hook) != 0 ]] || fail_case 'asymmetric locales passed'
grep -q 'Missing from pt' "$fix/hook.log" || fail_case 'localization diagnostic missing'
git_local -C "$fix" checkout -q -- Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj/Localizable.strings
git_local -C "$fix" reset -q

# 8. Staged Swift triggers scoped lint; divergence defers it.
if ((have_swift_tools)); then
  printf 'import Foundation\nlet  x=1\n' >"$fix/App/Dirty.swift"
  git_local -C "$fix" add App/Dirty.swift
  [[ $(run_hook) != 0 ]] || fail_case 'staged Swift lint failure passed'
  grep -q 'staged Swift failed lint' "$fix/hook.log" || fail_case 'lint diagnostic missing'
  printf 'import Foundation\nlet  y=2\n' >"$fix/App/Dirty.swift"
  [[ $(run_hook) == 0 ]] || fail_case 'diverged Swift should defer lint, not fail'
  grep -q 'scoped lint deferred' "$fix/hook.log" || fail_case 'deferral note missing'
  git_local -C "$fix" reset -q
  rm "$fix/App/Dirty.swift"
else
  printf 'import Foundation\nlet x = 1\n' >"$fix/App/Clean.swift"
  git_local -C "$fix" add App/Clean.swift
  [[ $(run_hook) == 0 ]] || fail_case 'missing tools should defer, not fail'
  grep -q 'not installed; scoped lint deferred' "$fix/hook.log" || fail_case 'tool deferral note missing'
  git_local -C "$fix" reset -q
  rm "$fix/App/Clean.swift"
fi

# 9. Empty stage passes without error.
[[ $(run_hook) == 0 ]] || fail_case 'empty stage failed'

# 10. No hook snapshot leaked across all runs.
[[ ! -s "$fix/hook-leaks" ]] || fail_case 'hook temp leaked'

printf '%s\n' 'pre-commit hook boundary checks passed'
