# Changelog

## 0.1.0-dev — 2026-09-24

Initial repository-ready implementation, based on selected GitScope MIT components.

- Native SwiftUI multi-repository dashboard, horizontal graph canvas, inspector, create sheet and settings.
- Worktree-focused graph projection preserving ancestry, merges, old/detached tips and loaded-history boundaries.
- NUL-delimited Git parsing, canonical common-directory deduplication and explicit unknown state.
- Defensive process runner and conservative create/remove/lock/unlock/prune operations.
- Foreground refresh, external app handoff, local registry and mutation-disabled demo mode.
- Foundation core tests, live local-Git fixtures, package/build/publish scripts and macOS CI definitions.

Verified on Apple Silicon macOS: native build and UI, disposable Git worktree operations, and 48 Swift Testing tests. GitHub publication and Actions, Intel execution, DMG generation and Apple notarization require separate observed results. See docs/VALIDATION.md for the exact scope.
