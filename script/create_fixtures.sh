#!/usr/bin/env bash
set -euo pipefail
# Never accepts a deletion target or overwrites a supplied directory.
fixture_git() {
  local git_var
  local -a unset_git_env=()
  for git_var in "${!GIT_@}"; do
    unset_git_env+=(-u "$git_var")
  done
  env "${unset_git_env[@]}" git "$@"
}
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/atlas-fixtures.XXXXXX")"
REPO="$ROOT/Example Project"
mkdir "$REPO"
fixture_git -C "$REPO" init -b main >/dev/null
fixture_git -C "$REPO" config user.name 'Atlas Fixture'
fixture_git -C "$REPO" config user.email 'fixture@example.invalid'
echo seed > "$REPO/notes.txt"
fixture_git -C "$REPO" add notes.txt
fixture_git -C "$REPO" commit -m 'Initial project' >/dev/null
fixture_git -C "$REPO" worktree add -b feature/graph "$ROOT/Graph Worktree" >/dev/null
printf '\ngraph change\n' >> "$ROOT/Graph Worktree/notes.txt"
fixture_git -C "$ROOT/Graph Worktree" commit -am 'Graph foundations' >/dev/null
fixture_git -C "$REPO" worktree add -b feature/parser "$ROOT/Parser Worktree" >/dev/null
printf '\nparser change\n' >> "$ROOT/Parser Worktree/notes.txt"
fixture_git -C "$ROOT/Parser Worktree" commit -am 'Parser foundations' >/dev/null
fixture_git -C "$REPO" worktree add --detach "$ROOT/Detached Review" HEAD >/dev/null
fixture_git -C "$REPO" worktree lock --reason 'Keep review context' "$ROOT/Detached Review"
echo 'uncommitted demo data' > "$ROOT/Graph Worktree/draft.txt"
echo 'main update' > "$REPO/main.txt"
fixture_git -C "$REPO" add main.txt
fixture_git -C "$REPO" commit -m 'Advance main' >/dev/null
printf '\nFixture repository: %s\nAll disposable fixtures are under: %s\n' "$REPO" "$ROOT"
