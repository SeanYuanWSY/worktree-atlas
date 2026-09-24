# Security and data safety

This development app reads local Git metadata and can create/remove/lock/unlock worktrees and prune explicitly confirmed stale metadata. Treat filesystem mutations as consequential. Make a backup before testing against valuable worktrees.

Safety rules: argument arrays, command scope limits, bounded subprocess execution, no force removal, no branch deletion, explicit unknown states, ignored-file preservation checks, detached-history protection, and preview-before-prune. These are safeguards, not a formal sandbox or a transaction across independent Git processes.

Repository and worktree directory identities (device and inode) are bound when registered and retained across refreshes. A replaced directory or symlink path disables writes until the repository is explicitly re-added. Removal checks the worktree again immediately before invoking Git. Another process can still change a path between that check and Git's operation, so stop writers in the target directory before removal.

Git checkout can execute repository-defined content filters and access the network (for example LFS). Only create worktrees from repositories you trust. The UI requires acknowledgement; fsmonitor/hooks are disabled by the runner. Do not run the app as root.

No built-in telemetry, cloud service, model connection or credential store is implemented. CLI diagnostic output includes local paths and branch names; redact it before sharing. Failed Git commands may include repository-controlled stderr.

If unexpected data changes occur, stop write operations, preserve the affected directory and report a minimal reproduction using a disposable repository. Until a private reporting channel is configured, do not disclose credentials, exploitable payloads or private code in public issues.

Public distribution has not been notarized in this delivery. Do not disable macOS security globally. Build from reviewed source locally or use a subsequently verified signed release.
