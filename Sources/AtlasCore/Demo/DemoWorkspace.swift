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
        func commit(_ n: Int, _ parents: [Int], _ title: String, refs: [GitRef] = []) -> CommitNode {
            CommitNode(sha: sha(n), parentSHAs: parents.map(sha), authorName: "Demo", authoredDate: Date(timeIntervalSince1970: Double(1000+n)), subject: title, refs: refs)
        }
        let path = "/demo/" + name
        let commits = [commit(9, [7], "Refine graph interactions"), commit(8, [6], "Improve diagnostics"),
                       commit(7, [5], "Add graph canvas"), commit(6, [5], "Scanner fixtures"),
                       commit(5, [4], "Shared base"), commit(10, [4], "Mainline updates", refs: [GitRef(name: "main", kind: .localBranch)]),
                       commit(4, [3], "Workspace registry"), commit(3, [2], "Core models"),
                       commit(2, [1], "Bootstrap"), commit(1, [], "Initial commit")]
        let worktrees = [GitWorktree(path: path, headSHA: sha(10), branchName: "main", isMain: true, hasUpstream: true, statusKnown: true),
                        GitWorktree(path: path + "-graph", headSHA: sha(9), branchName: branchNames[0], dirtyCount: index == 1 ? 3 : 0, aheadCount: 2, hasUpstream: true, statusKnown: true),
                        GitWorktree(path: path + "-fix", headSHA: sha(8), branchName: branchNames[1], isLocked: index == 2, statusKnown: true)]
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
        return RepositorySnapshot(record: RepositoryRecord(id: id, displayName: name, rootPath: path, commonDirectory: path + "/.git", defaultBranch: "main", lastScannedAt: Date()),
                                  worktrees: worktrees, commits: commits, branches: [BranchStatus(branchName: "main", headSHA: sha(10))])
    }
}
