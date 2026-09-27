# Architecture and v0.1 decisions

## Modules

`AtlasCore` contains Foundation models, a bounded Git process runner, NUL parsers, repository scanner, compact graph projector, safe worktree operations, JSON registry and demo fixtures. It builds on Linux and macOS.

The scanner reads both author and committer timestamps plus the full commit body. The native table renders every loaded commit from top to bottom in topological order, with actual parent edges in the left rail, worktree/ref labels next, and subject, author, relative time, and SHA columns. Dirty/unknown/prunable worktrees get attention rows directly above their corresponding HEAD. The main checkout first-parent chain uses the leftmost rail; other lanes keep their relative ordering. Display rows are 22pt high, and the canvas is drawn above row backgrounds so selection cannot hide nodes. Row position does not encode elapsed time. The table pages the loaded history in groups of 40 (overview) or 80 (focused); its horizontal scroll preserves columns in narrow windows. The compact graph projector remains available to core consumers and tests, but the current native table does not contract linear commits.

`WorktreeAtlas` is the SwiftUI/AppKit executable, included in Package.swift only on macOS. `WorkspaceModel` owns the shared registry and snapshots. Window-local dashboard selection is in `DashboardView`; `GraphCanvasView` and the inspector are separate views. `DesktopActions` is the small AppKit boundary for folder panels, clipboard and opening other apps.

`atlas-inspect` is a read-only executable built against the same core. It is for diagnostics/tests, not a replacement for the GUI.

## Identity

A persisted repository has a UUID for UI identity and a canonical `git rev-parse --path-format=absolute --git-common-dir` for deduplication. Importing different linked worktrees of one repo must not create duplicate cards. Worktree identity is its exact path, not its branch: several worktrees can share a SHA, or have detached/unborn HEADs. Non-UTF-8 output is rejected rather than silently corrupted.

## Data acquisition

Each scan reads the common directory, `worktree list --porcelain -z`, per-worktree `status --porcelain=v2 --branch -z`, local/cached remote refs and bounded log history. NUL delimiters preserve whitespace/newlines in paths; rename records skip the extra source-path field. No network fetch is requested. Main and bare worktrees are explicitly identified. Status failure is independent from Git's `prunable` flag.

Default history budget: 1200 commits across worktree heads and the default branch. Old tips omitted by the global cap get a small 40-commit fallback. The union is topologically re-sorted. Missing parents become history boundaries, not fabricated roots. A worktree whose HEAD still cannot be loaded stays visible outside the plotted graph with an explicit label.

## Compact graph invariant

The source graph is a directed acyclic graph, not necessarily a tree. Child-to-parent adjacency is authoritative. Dates only break ordering ties.

Anchors include every worktree HEAD, default branch tip, merge, immediate merge parents, fork, root and loaded-history frontier. Other vertices can be contracted only when they have exactly one parent and one child. Projected edges carry the exact number of hidden commits. For any pair of retained vertices, reachability must equal that in the loaded original graph. Tests verify this on hand-built cases and a deterministic corpus of 80 DAGs.

Immediate merge parents remain anchors so two distinct merge paths do not become overlapping parallel edges with identical IDs. Lane placement derives from GitScope's algorithm. Horizontal placement is topological order, **not time spacing**. Each repository renders separately.

## Concurrency and refresh

The UI model runs on the main actor. Blocking processes execute in detached tasks using synchronized cancellation flags. A scan round allows at most two repositories concurrently; each repo's worktrees are scanned serially. Foreground polling defaults to ten seconds, with pause/settings controls. Generation IDs reject obsolete scan results. UI mutations are serialized and cancel the previous refresh round.

A repository-level refresh failure retains the previous snapshot and displays a stale-data warning. It does not display its old clean status as a verified current state. JSON writes are atomic, and a corrupt registry disables automatic overwrite rather than silently dropping user configuration.

## Safety

Git invocations use argument arrays through `/usr/bin/env git`, not a shell. Inherited `GIT_*` overrides are removed; optional index locks, fsmonitor and hooks are disabled. stdout/stderr are separate private temporary files, avoiding pipe buffer deadlocks; execution has a deadline and output cap. Prune's successful diagnostic output is explicitly read from stderr.

Remove re-reads membership and status, rejects main/bare/locked/unknown/nonexistent paths, checks ignored files as well as tracked/untracked modifications, protects unreferenced detached history and never passes `--force`. Git still performs its own final safety check. A branch is never deleted. There remains a cross-process check/delete race, particularly for ignored files; do not claim transactional deletion safety.

Prune preview uses Git's own dry run and requires the exact same preview immediately before confirmation execution. It is never automatic. A missing external drive can be protected with a lock. Creating a worktree can run repository-defined content filters and therefore requires the explicit UI trust acknowledgement. Hooks are disabled, but arbitrary filter configs are not a sandbox.

## Deliberate exclusions

No terminal emulator, AI provider, Git hosting authentication, telemetry, auto updater, commit/push/merge/rebase, worktree rename/move, remote-machine aggregation, unlimited-history pagination or realtime FSEvents service. These are not hidden “completed” features. macOS signing and notarization are separate distribution work, not prerequisites for local ad-hoc debug builds.
