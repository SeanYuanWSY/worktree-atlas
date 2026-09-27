import Foundation

public enum DemoWorkspace {
    /// Pure in-memory fixtures. Demo mode cannot invoke mutations or persist these records.
    public static var snapshots: [RepositorySnapshot] {
        [make("Atlas", index: 1, branchNames: ["feature/graph", "fix/scanner"]),
         make("Research", index: 2, branchNames: ["experiment/model-v2", "benchmark"]),
         make("Website", index: 3, branchNames: ["design/landing", "docs/getting-started"])]
    }
    private static func make(_ name: String, index: Int, branchNames: [String]) -> RepositorySnapshot {
        func sha(_ value: Int) -> String {
            String(format: "%07x", 0xa000000 | (index << 16) | (value << 8) | 0x5a)
                + String(repeating: "0", count: 33)
        }
        let subjects = [
            "Initialize workspace registry", "Read Git worktree porcelain records", "Resolve repository identities",
            "Track local branches and cached remote refs", "Add filesystem identity checks", "Preserve detached worktree heads",
            "Build repository discovery pipeline", "Add refresh cancellation support", "Show unknown worktree status",
            "Validate branch names before creation", "Keep locked worktrees protected", "Add disposable repository fixtures",
            "Handle repositories with unrelated histories", "Preserve merge parent relationships", "Improve history boundary labels",
            "Read complete commit messages", "Add branch and path filtering", "Restore registered workspaces on launch",
            "Keep selection stable during refresh", "Show cached ahead and behind counts", "Add worktree inspection panel",
            "Retain Unicode paths and branch names", "Improve error messages for offline volumes", "Bound concurrent repository scans",
            "Add native keyboard shortcuts", "Keep commit graph colors consistent", "Support multiple worktrees at one HEAD",
            "Add safe worktree removal checks", "Preserve branch references after removal", "Add pruning preview confirmation",
            "Document worktree lifecycle", "Improve repository switcher", "Add scanner regression fixtures",
            "Align commit metadata columns", "Refine branch rail geometry", "Polish worktree navigation",
            "Add compact graph labels", "Preserve graph selection while scrolling", "Handle stale directory records",
            "Verify scanner recovery paths", "Draft workspace navigation guide", "Document graph history limits",
            "Refine repository toolbar", "Improve native window layout", "Merge scanner diagnostics",
            "Keep workspace controls compact", "Refine graph node interactions", "Expand worktree documentation"
        ]
        func commit(_ n: Int, _ parents: [Int], refs: [GitRef] = []) -> CommitNode {
            let date = Date().addingTimeInterval(-Double((49 - n) * 14400 + index * 3600))
            return CommitNode(sha: sha(n), parentSHAs: parents.map(sha),
                              authorName: ["Alex", "Morgan", "Sam"][(n + index) % 3], authoredDate: date,
                              subject: subjects[n - 1],
                              body: "\(subjects[n - 1]).\n\nKeep the worktree state visible in its repository graph and preserve the original commit relationships.", refs: refs)
        }
        let path = "/demo/" + name
        var commits = (1...36).map { commit($0, $0 == 1 ? [] : [$0 - 1]) }
        commits += [commit(37, [34]), commit(38, [37]), commit(39, [33]),
                    commit(40, [39], refs: [GitRef(name: branchNames[1], kind: .localBranch)]),
                    commit(41, [31]), commit(42, [41]), commit(43, [36]), commit(44, [43]),
                    commit(45, [44, 40]),
                    commit(46, [45], refs: [GitRef(name: "main", kind: .localBranch), GitRef(name: "origin/main", kind: .remoteBranch)]),
                    commit(47, [38], refs: [GitRef(name: branchNames[0], kind: .localBranch)]),
                    commit(48, [42], refs: [GitRef(name: "docs/worktree-guide", kind: .localBranch)])]
        let worktrees = [GitWorktree(path: path, headSHA: sha(46), branchName: "main", isMain: true, hasUpstream: true, statusKnown: true),
                        GitWorktree(path: path + "-graph", headSHA: sha(47), branchName: branchNames[0], dirtyCount: index == 1 ? 3 : 0, aheadCount: 2, hasUpstream: true, statusKnown: true),
                        GitWorktree(path: path + "-fix", headSHA: sha(40), branchName: branchNames[1], isLocked: index == 2, statusKnown: true),
                        GitWorktree(path: path + "-docs", headSHA: sha(48), branchName: "docs/worktree-guide", dirtyCount: index == 1 ? 1 : 0, statusKnown: true)]
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
        return RepositorySnapshot(record: RepositoryRecord(id: id, displayName: name, rootPath: path, commonDirectory: path + "/.git", defaultBranch: "main", lastScannedAt: Date()),
                                  worktrees: worktrees, commits: commits, branches: [BranchStatus(branchName: "main", headSHA: sha(46))])
    }
}
