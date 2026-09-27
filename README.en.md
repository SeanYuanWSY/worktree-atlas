# Worktree Atlas

**Your worktrees, back on the graph.** A focused native macOS workspace that displays multiple repositories and attaches each worktree to its real Git HEAD.

This **0.1.0-dev source release** has been built, ad-hoc signed, and opened as a native app on an Apple Silicon Mac. Its current interface follows the supplied GitLens reference with compact editor chrome, edge-to-edge repository panels, 22pt rows, thin ring nodes, vertical ancestry rails with short bends, and small branch/worktree labels. The main checkout first-parent chain stays on the left; uncommitted changes sit directly above the corresponding HEAD. Subjects, author initials, relative dates, and short SHAs stay aligned. Multiple repositories remain visible as stacked, collapsible panels. Click a subject for the full commit message or a worktree for its details. Disposable repositories verified the native create, lock, unlock, remove, and prune flows. All 49 current Swift Testing tests passed locally and in the [GitHub macOS build for the current editor layout](https://github.com/SeanYuanWSY/worktree-atlas/actions/runs/36331382509). See [validation](docs/VALIDATION.md).

## Scope

Multiple repository panels; real ancestry edges; paged loaded history; worktree inspection; branch/path search; attention filtering; create/remove/lock/unlock/prune; external app launch; foreground polling; native light/dark appearance; demo mode.

No commit, push, pull, fetch, merge, rebase, cherry-pick, branch deletion, built-in terminal or AI agents. Worktrees are labels on commits, not a fabricated parent-child hierarchy.

## Run on macOS

Requires macOS 14+, Swift 6 and Git supporting NUL-delimited worktree porcelain (Git 2.36+ recommended). Command Line Tools can build and test the app on this Mac.

```sh
./script/build_and_run.sh --demo
./script/check.sh
./script/build_and_run.sh
```

The script builds a project-local app bundle and signs it ad hoc. It does not install to `/Applications` or disable Gatekeeper. The check script requires at least 48 executed tests, avoiding a false pass from zero tests on Command Line Tools. `script/package_release.sh` creates a development DMG on macOS. The initial source commit passed GitHub's Xcode 16.4 macOS build and test workflow; the uploaded ZIP is a development artifact, not a notarized release.

## Safety

Never force-removes. Refuses main/bare/locked worktrees, unknown status, modified, untracked **and ignored** files. Detached commits without a protecting local branch/tag are retained. Prune always previews and re-checks; offline disks are not automatically pruned. No arbitrary shell interpolation; Git subprocesses have deadlines, output caps, cancellation and isolated temporary output files. Git hooks/fsmonitor are disabled for the app's commands, but checkout content filters remain a repository trust boundary.

Metadata reads are not an atomic transaction across Git processes. Avoid concurrently writing into a directory while removing it. See [security](SECURITY.md) and [architecture](docs/ARCHITECTURE.md).

Registered repository and worktree paths retain their directory identities across refreshes and restarts. If a directory is replaced at the same path, writes stop until you explicitly re-add the repository. Older saved registrations without identities also require re-adding.

## Publish

The [**public** repository](https://github.com/SeanYuanWSY/worktree-atlas) has been created. `script/publish_github.sh` was used for the initial commit from a fixed 54-file manifest and pushed only `main`. It refuses an existing repository or remote; later updates use normal Git commits.

## Attribution

Derived from selected MIT-licensed GitScope components, pinned at `5dc3f368af5b4703cbab72b55af9be86c864c8a1`. Upstream copyright retained; see [third-party notices](THIRD_PARTY_NOTICES.md). The macOS shell and graph dashboard are new Atlas work. MIT license.

## Design preview

Open `docs/preview.html` locally for an interactive, synthetic-data design preview. `docs/preview-light.png` and `docs/preview-dark.png` are browser renders of that preview, **not native macOS screenshots**. Optional browser checks: `python script/check_preview.py` (requires Python Playwright and Chromium).
