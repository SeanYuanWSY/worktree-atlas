import Foundation

public struct AtlasGraphNode: Identifiable, Equatable, Sendable {
    public var id: String { commit.sha }
    public var commit: CommitNode
    public var lane: Int
    public var row: Int
    public var column: Int
    public var worktrees: [GitWorktree]
    public var isHistoryBoundary: Bool
}
public struct AtlasGraphEdge: Identifiable, Equatable, Sendable {
    public var id: String { "\(childSHA):\(parentSHA)" }
    public var childSHA: String
    public var parentSHA: String
    public var hiddenCommits: Int
}
public struct WorktreeGraph: Equatable, Sendable {
    public var nodes: [AtlasGraphNode]
    public var edges: [AtlasGraphEdge]
    public var unplacedWorktrees: [GitWorktree]
    public var totalCommits: Int
    public init(nodes: [AtlasGraphNode], edges: [AtlasGraphEdge], unplacedWorktrees: [GitWorktree], totalCommits: Int) {
        self.nodes = nodes; self.edges = edges; self.unplacedWorktrees = unplacedWorktrees; self.totalCommits = totalCommits
    }
    public var hiddenCommits: Int { max(0, totalCommits - nodes.count) }
    public var laneCount: Int { (nodes.map(\.lane).max() ?? 0) + 1 }
}

public enum WorktreeGraphProjector {
    /// Contracts only non-anchor vertices with exactly one parent and one child.
    /// Merge vertices, forks, all worktree heads, roots and truncated-history boundaries survive.
    /// An edge is always a real ancestor path; no inferred "parent worktree" is invented.
    public static func project(_ snapshot: RepositorySnapshot, compact: Bool = true) -> WorktreeGraph {
        let ordered = topologicalOrder(snapshot.commits)
        let bySHA = Dictionary(ordered.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(bySHA.keys)
        let worktrees = snapshot.worktrees.filter { !$0.isBare }
        var anchors = Set(worktrees.map(\.headSHA))
        // Keep immediate merge parents: otherwise two parallel paths can contract into
        // visually indistinguishable duplicate edges between the merge and its fork.
        for commit in ordered where commit.parentSHAs.count > 1 { anchors.formUnion(commit.parentSHAs) }
        if let name = snapshot.record.defaultBranch,
           let branch = snapshot.branches.first(where: { !$0.isRemote && $0.branchName == name }) {
            anchors.insert(branch.headSHA)
        }
        var childCounts: [String: Int] = [:]
        for commit in ordered {
            for parent in commit.parentSHAs { childCounts[parent, default: 0] += 1 }
        }
        let kept = ordered.filter { commit in
            !compact || anchors.contains(commit.sha) || commit.parentSHAs.count != 1 ||
            childCounts[commit.sha, default: 0] != 1 || commit.parentSHAs.contains(where: { !known.contains($0) })
        }
        let keptSHAs = Set(kept.map(\.sha))
        var edges: [AtlasGraphEdge] = []
        var reduced: [CommitNode] = []
        for original in kept {
            var commit = original
            var parents: [String] = []
            for first in original.parentSHAs {
                var cursor = first
                var hidden = 0
                var seen: Set<String> = []
                while known.contains(cursor) && !keptSHAs.contains(cursor) && seen.insert(cursor).inserted {
                    guard let next = bySHA[cursor]?.parentSHAs.first else { break }
                    hidden += 1
                    cursor = next
                }
                if keptSHAs.contains(cursor) {
                    parents.append(cursor)
                    edges.append(AtlasGraphEdge(childSHA: original.sha, parentSHA: cursor, hiddenCommits: hidden))
                }
            }
            commit.parentSHAs = parents
            reduced.append(commit)
        }
        let lanes = GraphLayoutEngine().lanes(for: reduced)
        var columns: [String: Int] = [:]
        var occupied = Set<String>()
        for commit in reduced.reversed() {
            var column = (commit.parentSHAs.compactMap { columns[$0] }.max() ?? -1) + 1
            let lane = lanes[commit.sha] ?? 0
            while occupied.contains("\(lane):\(column)") { column += 1 }
            columns[commit.sha] = column; occupied.insert("\(lane):\(column)")
        }
        let grouped = Dictionary(grouping: worktrees, by: \.headSHA)
        let nodes = kept.enumerated().map { index, commit in
            AtlasGraphNode(commit: commit, lane: lanes[commit.sha] ?? 0, row: index, column: columns[commit.sha] ?? index,
                worktrees: (grouped[commit.sha] ?? []).sorted { $0.path < $1.path },
                isHistoryBoundary: commit.parentSHAs.contains { !known.contains($0) })
        }
        return WorktreeGraph(nodes: nodes, edges: edges,
            unplacedWorktrees: worktrees.filter { !known.contains($0.headSHA) }, totalCommits: ordered.count)
    }

    /// Stable Kahn order. Dates are a tie-breaker, never evidence of ancestry.
    public static func topologicalOrder(_ commits: [CommitNode]) -> [CommitNode] {
        let dict = Dictionary(commits.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })
        var children = Dictionary(uniqueKeysWithValues: dict.keys.map { ($0, 0) })
        for commit in dict.values {
            for parent in commit.parentSHAs where dict[parent] != nil { children[parent, default: 0] += 1 }
        }
        func sorted(_ values: [String]) -> [String] {
            values.sorted {
                let left = dict[$0]!.authoredDate, right = dict[$1]!.authoredDate
                return left == right ? $0 < $1 : left > right
            }
        }
        var ready = sorted(children.filter { $0.value == 0 }.map(\.key))
        var result: [CommitNode] = []
        while !ready.isEmpty {
            let sha = ready.removeFirst()
            guard let commit = dict[sha] else { continue }
            result.append(commit)
            for parent in commit.parentSHAs where dict[parent] != nil {
                children[parent, default: 0] -= 1
                if children[parent] == 0 { ready.append(parent) }
            }
            ready = sorted(ready)
        }
        return result
    }
}
