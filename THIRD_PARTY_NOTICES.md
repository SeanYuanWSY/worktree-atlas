# Third-party attribution

Worktree Atlas is a derivative project, not an official GitScope release or an endorsed successor.

## GitScope

- Upstream: https://github.com/Oreo992/GitScope
- Inspected source commit: `5dc3f368af5b4703cbab72b55af9be86c864c8a1`
- Copyright: Copyright (c) 2026 Oreo
- License: MIT; the required copyright and permission text is retained in `LICENSE`, which is also bundled in the app.

### Precisely what was reused

| Upstream source | Atlas source | Changes |
| --- | --- | --- |
| `Sources/GitScopeCore/Models/GitModels.swift` | `Sources/AtlasCore/Models/GitModels.swift` | Retained and adapted the repository / snapshot / worktree / commit / ref model design; simplified branch fields; added explicit unknown state, common-directory identity and truncation metadata. |
| `Sources/GitScopeCore/Graph/GraphLayoutEngine.swift` | `Sources/AtlasCore/Graph/GraphLayoutEngine.swift` | Adapted the lane-assignment algorithm and helper methods; removed upstream row and badge UI types. |
| `Sources/GitScopeCore/Git/RepositoryScanner.swift` | `Sources/AtlasCore/Git/RepositoryScanner.swift` | Followed the scanner architecture; rewrote process integration, NUL-delimited parsing, identity handling and bounded history. |

The multi-repository state coordinator, compact graph projection, defensive runner, operation safeguards, new SwiftUI interface, demonstration data, tests, scripts and documentation were implemented for Atlas. This deliverable does not pretend to include the entire upstream Git history. It is a new repository-ready derivative, not a GitHub fork that has already been created.

## Build-time actions

The GitHub Actions workflows reference official `actions/checkout` and `actions/upload-artifact`, pinned to commit SHAs resolved on 2026-09-24. These are CI dependencies, not bundled application code. The Swift package itself has no external package dependencies.
