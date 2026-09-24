# macOS acceptance checklist

Checked boxes reflect the 2026-09-24 Apple Silicon run documented in [VALIDATION.md](VALIDATION.md). The source ZIP has no Git commit metadata. Unchecked boxes remain unverified.

## Build and launch

- [x] `./script/check.sh` runs and passes all 48 Swift Testing tests on this Mac; it rejects a zero-test run.
- [x] `./script/build_and_run.sh --demo` builds the SwiftUI target, creates/signs a real `.app`, and launches a foreground native window.
- [x] The procedural icon builds using AppKit/iconutil.
- [ ] Confirm the icon appears correctly in the Dock and app switcher.
- [x] Restarting the native app restored a disposable real repository registration; demo records did not replace the saved registry.
- [ ] Light, dark, 1380×880 and 980×660 layouts have no clipped or unreadable controls. Light/dark and the macOS half-screen layout were inspected; exact pixel sizes remain untested.
- [x] Opening an inspector collapses the dashboard to an appropriate column count.
- [x] Zooming a real graph creates scrollable space; Fit restores the full graph and follows a wider window.
- [ ] Graph labels, pan/zoom/Fit and scroll areas remain usable with long branch names.

## Disposable real repositories

Run `./script/create_fixtures.sh`. It prints a new temporary root and never overwrites an existing one. Add the printed Example Project folder to the app.

- [x] The main, two feature and detached worktrees appear in one real commit graph.
- [x] Add a second temporary repo: each card is separate; there are no cross-repository edges. A third real repo remains untested.
- [ ] Add an already-registered linked worktree: no duplicate repository card is created.
- [ ] Worktrees sharing HEAD appear as separate labels on the same node.
- [ ] Feature commits, merge commits and loaded-history boundaries render correctly.
- [x] Selecting a worktree opens its own path/branch/HEAD/status details.
- [ ] Create new-branch, existing-branch and detached worktrees through the sheet. New-branch creation passed in the native UI; the other two modes remain to test there.
- [ ] Create a worktree in an external terminal; it appears after the next active-window polling interval.
- [ ] Modify and stage a rename; the dirty file count is correct, not doubled.
- [x] Safe remove keeps the branch in a clean temporary worktree. A locked worktree disabled removal; dirty state disabled it in an earlier native UI check. Untracked and ignored-file refusal passed core tests but still need native UI checks.
- [ ] A detached commit not contained by a local branch/tag cannot be removed.
- [ ] Prune produces a visible preview; cancelling changes nothing. Native UI preview and confirmation passed on a disposable stale record; cancellation remains to inspect. A changed preview is rejected in core tests.
- [ ] An offline drive produces unknown/stale state, not silent cleanup.
- [ ] Open in Finder/Terminal/installed editors uses the intended worktree path.
- [ ] The app remains responsive during scanning, including errors and cancellation.

## Publication

- [x] Confirm that no repository exists, select the new public `SeanYuanWSY/worktree-atlas` target, and review the fixed publication manifest.
- [ ] Create and push the public repository; record the returned URL, visibility, default branch and commit.
- [ ] Read real Actions results; fix macOS compilation before tagging any release.
- [ ] If distributing a trusted binary, perform Developer ID signing, submit for notarization, staple and verify the actual artifact. Ad-hoc signing alone is not notarization.
