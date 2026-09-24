# Contributing

Keep the product focused on worktree visibility and lifecycle. Read AGENTS.md and docs/ARCHITECTURE.md before changes. Discuss larger scope changes first.

Use Swift 6, small SwiftUI views, Foundation-only core modules and disposable Git fixtures. Run `swift test` and `script/check.sh`. Changes to compact graph projection need reachability/topology tests; changes to write operations need negative safety tests.

For UI pull requests attach actual Mac screenshots in light and dark mode, with long branch/path fixtures and a narrow window. Label design mockups separately. Never present a browser preview as a native screenshot.

Do not upload private repository content or credentials in issues, screenshots or logs. Preserve the original MIT attribution for upstream-derived code.
