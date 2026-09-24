# Development handoff

## Product contract

A beautiful **native macOS, worktree-only, multi-repository graph dashboard**. Do not turn it into a path list, AI chat app or full Git client. Default to all-repository cards. Worktrees label Git commits. Edges only mean actual ancestry; unrelated repositories never share graph edges.

## Read first

`README.md`, `docs/ARCHITECTURE.md`, `docs/VALIDATION.md`, `docs/LOCAL_TEST.md`, `THIRD_PARTY_NOTICES.md`.

## Commands

- `./script/check.sh`: compile, run at least 48 Swift Testing core/unit/integration tests, check Swift and shell syntax and diff whitespace; also build the native app on macOS. It supplies framework paths for Command Line Tools to avoid a zero-test false pass.
- `./script/build_and_run.sh --demo`: canonical native app demo run.
- `./script/build_and_run.sh --verify`: launch and process check, not UI proof.
- `./script/create_fixtures.sh`: new disposable fixture without replacing any user directory.

## Current Mac handoff

The ZIP was extracted into this project directory. The 2026-09-24 Apple Silicon build, 48 passing Swift Testing tests, and native UI checks are recorded in `docs/VALIDATION.md`; continue from its unchecked items rather than repeating the Linux-only handoff. This Mac has Swift 6.3.1 Command Line Tools but no full Xcode. The source ZIP had no `.git`; the owner confirmed that no GitHub repository existed and authorized creating the public `SeanYuanWSY/worktree-atlas` repository. The initial publish script is for that new target only. Use disposable fixture repos for write-operation testing.

## Engineering boundaries

- `AtlasCore` stays Foundation-only and Linux-testable; no AppKit imports.
- All Git commands go through an argument-array runner. Do not use `sh -c` or interpolate branch/path into shell source.
- Never use `--force`, `-B`, branch delete, reset, or automatic prune.
- Keep unknown status and stale repository snapshots visible. Missing drives are not cleanup instructions.
- Preserve every active worktree HEAD and merge topology in compact graphs. Test all retained-vertex reachability.
- Do not collapse both merge paths into duplicate visually overlapping edges. Immediate merge parents are anchors.
- Never infer “worktree A was created from worktree B” from a merge base.
- No hardcoded user project names, private paths, credentials or model sessions in demo data.
- Tests use temporary fixtures; never delete paths supplied by the user.
- Preserve upstream MIT copyright and distinguish adapted code from original Atlas code.
- No success claims for CI, signing, notarization or app execution without observed evidence.
