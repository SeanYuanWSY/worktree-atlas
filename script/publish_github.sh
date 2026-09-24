#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OWNER="SeanYuanWSY"
NAME="worktree-atlas"
MODE="${1:-create}"
case "$MODE" in create|--resume) ;; *) echo "Usage: $0 [--resume]" >&2; exit 2;; esac
command -v gh >/dev/null || { echo "GitHub CLI is required." >&2; exit 1; }
LOGIN="$(gh api user --jq .login)"
[[ "$LOGIN" == "$OWNER" ]] || { echo "Refusing: gh is not authenticated as $OWNER." >&2; exit 1; }
USER_ID="$(gh api user --jq .id)"
[[ "$USER_ID" =~ ^[0-9]+$ ]] || { echo "Cannot resolve the GitHub account ID." >&2; exit 1; }
PUBLIC_EMAIL="$USER_ID+$OWNER@users.noreply.github.com"
cd "$ROOT"

# The initial public commit has a fixed file list. Directory-wide staging or
# publishing an arbitrary pre-existing commit could disclose unrelated files.
PROJECT_FILES=(
  .codex/environments/environment.toml
  .github/ISSUE_TEMPLATE/bug.md
  .github/ISSUE_TEMPLATE/feature.md
  .github/pull_request_template.md
  .github/workflows/ci.yml
  .github/workflows/release-build.yml
  .gitignore AGENTS.md CHANGELOG.md CONTRIBUTING.md LICENSE Package.swift
  README.en.md README.md SECURITY.md THIRD_PARTY_NOTICES.md
  Sources/AtlasCLI/main.swift
  Sources/AtlasCore/Demo/DemoWorkspace.swift
  Sources/AtlasCore/Git/GitCommandRunner.swift
  Sources/AtlasCore/Git/GitParser.swift
  Sources/AtlasCore/Git/RepositoryScanner.swift
  Sources/AtlasCore/Git/WorktreeOperator.swift
  Sources/AtlasCore/Graph/GraphLayoutEngine.swift
  Sources/AtlasCore/Graph/WorktreeGraph.swift
  Sources/AtlasCore/Models/GitModels.swift
  Sources/AtlasCore/Persistence/RepositoryStore.swift
  Sources/WorktreeAtlas/App/WorktreeAtlasApp.swift
  Sources/WorktreeAtlas/Services/DesktopActions.swift
  Sources/WorktreeAtlas/Services/WorkspaceModel.swift
  Sources/WorktreeAtlas/Support/AtlasStyle.swift
  Sources/WorktreeAtlas/Views/CreateWorktreeSheet.swift
  Sources/WorktreeAtlas/Views/DashboardView.swift
  Sources/WorktreeAtlas/Views/GraphCanvasView.swift
  Sources/WorktreeAtlas/Views/RepositoryCardView.swift
  Sources/WorktreeAtlas/Views/SettingsView.swift
  Sources/WorktreeAtlas/Views/WorktreeInspector.swift
  Tests/AtlasCoreTests/GraphTests.swift
  Tests/AtlasCoreTests/IntegrationTests.swift
  Tests/AtlasCoreTests/ParserTests.swift
  docs/ARCHITECTURE.md docs/LOCAL_TEST.md docs/VALIDATION.md
  docs/evidence/html-preview-checks.json docs/evidence/linux-check.log
  docs/preview-dark.png docs/preview-light.png docs/preview.html
  script/build_and_run.sh script/check.sh script/check_preview.py
  script/create_fixtures.sh script/make_icon.swift script/package_release.sh
  script/publish_github.sh
)
EXPECTED="$(printf '%s\n' "${PROJECT_FILES[@]}" | LC_ALL=C sort)"
verify_files() {
  local file part current
  local -a parts
  for file in "${PROJECT_FILES[@]}"; do
    current="$ROOT"
    IFS='/' read -r -a parts <<< "$file"
    for part in "${parts[@]}"; do
      current="$current/$part"
      [[ ! -L "$current" ]] || { echo "Refusing symlink: $file" >&2; exit 1; }
    done
    [[ -f "$current" ]] || { echo "Missing project file: $file" >&2; exit 1; }
  done
}
verify_commit() {
  local actual_identity expected_identity
  [[ "$(git rev-list --count HEAD)" == 1 ]] || { echo "This script only supports its single initial commit." >&2; exit 1; }
  [[ "$(git ls-tree -r --name-only HEAD | LC_ALL=C sort)" == "$EXPECTED" ]] || {
    echo "Committed file list differs from the reviewed project manifest." >&2; exit 1;
  }
  actual_identity="$(git show -s --format='%an%n%ae%n%cn%n%ce' HEAD)"
  expected_identity="$(printf '%s\n%s\n%s\n%s' "$OWNER" "$PUBLIC_EMAIL" "$OWNER" "$PUBLIC_EMAIL")"
  [[ "$actual_identity" == "$expected_identity" ]] || {
    echo "Commit author or committer is not the reviewed public identity." >&2; exit 1;
  }
  [[ -z "$(git status --porcelain)" ]] || { echo "Working tree is dirty; review it before publishing." >&2; exit 1; }
}

if [[ "$MODE" == --resume ]]; then
  [[ "$(git rev-parse --show-toplevel 2>/dev/null)" == "$ROOT" ]] || { echo "Not a standalone project checkout." >&2; exit 1; }
  [[ "$(git branch --show-current)" == main ]] || { echo "Resume from main." >&2; exit 1; }
  verify_files
  verify_commit
  REMOTE="$(git remote get-url origin)"
  case "$REMOTE" in "https://github.com/$OWNER/$NAME.git"|"https://github.com/$OWNER/$NAME"|"git@github.com:$OWNER/$NAME.git") ;; *) echo "Origin does not match the intended repository." >&2; exit 1;; esac
  [[ "$(gh repo view "$OWNER/$NAME" --json visibility --jq .visibility)" == PUBLIC ]] || { echo "Target repository is not public." >&2; exit 1; }
  git -c core.hooksPath=/dev/null push --set-upstream origin main
  exit 0
fi

if gh repo view "$OWNER/$NAME" --json nameWithOwner >/dev/null 2>&1; then
  echo "Repository already exists. Integrate changes in its checkout; this script never replaces it." >&2
  exit 1
fi
if TOP="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  [[ "$TOP" == "$ROOT" ]] || { echo "Refusing to use a parent repository." >&2; exit 1; }
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "Existing Git history found. Integrate it manually; this script only creates an initial commit." >&2
    exit 1
  fi
  [[ -z "$(git diff --cached --name-only)" ]] || { echo "Pre-staged files found; review them before publishing." >&2; exit 1; }
else
  git init -b main
fi
[[ "$(git branch --show-current)" == main ]] || { echo "Publish from main." >&2; exit 1; }
[[ -z "$(git remote)" ]] || { echo "Existing Git remote found; refusing to replace it." >&2; exit 1; }
verify_files
git add -- "${PROJECT_FILES[@]}"
[[ "$(git diff --cached --name-only | LC_ALL=C sort)" == "$EXPECTED" ]] || {
  echo "Staged file list differs from the reviewed project manifest." >&2; exit 1;
}
for file in "${PROJECT_FILES[@]}"; do
  [[ "$(git hash-object --no-filters "$file")" == "$(git rev-parse ":$file")" ]] || {
    echo "Staged content differs from source file: $file" >&2; exit 1;
  }
done
git diff --cached --check
GIT_AUTHOR_NAME="$OWNER" GIT_AUTHOR_EMAIL="$PUBLIC_EMAIL" \
GIT_COMMITTER_NAME="$OWNER" GIT_COMMITTER_EMAIL="$PUBLIC_EMAIL" \
git -c core.hooksPath=/dev/null -c commit.gpgsign=false commit \
  -m "feat: introduce native multi-repository worktree graph workspace"
verify_commit
echo "Creating PUBLIC repository $OWNER/$NAME with the reviewed initial commit. No force push."
gh repo create "$OWNER/$NAME" --public --source "$ROOT" --remote origin \
  --description "A focused native macOS worktree graph: every repository, every worktree, real Git ancestry."
[[ "$(gh repo view "$OWNER/$NAME" --json visibility --jq .visibility)" == PUBLIC ]] || { echo "Target repository is not public; main was not pushed." >&2; exit 1; }
git -c core.hooksPath=/dev/null push --set-upstream origin main
gh repo view "$OWNER/$NAME" --json url --jq .url
