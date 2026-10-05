import Foundation

/// Immutable table data prepared when a repository changes, rather than during UI selection or hover.
public struct RepositoryGraphPresentation: Equatable, Sendable {
    public let graph: WorktreeGraph
    public let laneCount: Int
    public let overviewPages: [RepositoryGraphPage]
    public let focusedPages: [RepositoryGraphPage]
    private let source: RepositorySnapshot

    public init(snapshot: RepositorySnapshot) {
        source = snapshot
        var projected = WorktreeGraphProjector.project(snapshot, compact: false)
        if let main = snapshot.worktrees.first(where: { $0.isMain }) {
            let commits = Dictionary(snapshot.commits.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })
            var mainline = Set<String>()
            var cursor: String? = main.headSHA
            while let sha = cursor, mainline.insert(sha).inserted {
                cursor = commits[sha]?.parentSHAs.first
            }
            let otherLanes = Set(projected.nodes.filter { !mainline.contains($0.id) }.map(\.lane)).sorted()
            let laneMap = Dictionary(uniqueKeysWithValues: otherLanes.enumerated().map { ($0.element, $0.offset + 1) })
            for index in projected.nodes.indices {
                let node = projected.nodes[index]
                projected.nodes[index].lane = mainline.contains(node.id) ? 0 : laneMap[node.lane] ?? node.lane + 1
            }
        }
        graph = projected
        laneCount = projected.laneCount
        overviewPages = Self.pages(graph: projected, worktrees: snapshot.worktrees, size: 40)
        focusedPages = Self.pages(graph: projected, worktrees: snapshot.worktrees, size: 80)
    }

    /// Scan timestamps and registry display names do not alter the graph.
    public func matches(_ snapshot: RepositorySnapshot) -> Bool {
        source.commits == snapshot.commits && source.worktrees == snapshot.worktrees &&
            source.branches == snapshot.branches && source.record.defaultBranch == snapshot.record.defaultBranch
    }

    private static func pages(graph: WorktreeGraph, worktrees: [GitWorktree], size: Int) -> [RepositoryGraphPage] {
        guard !graph.nodes.isEmpty else { return [RepositoryGraphPage(rows: [], segments: [], worktreeLinks: [])] }
        let indices = Dictionary(uniqueKeysWithValues: graph.nodes.enumerated().map { ($0.element.id, $0.offset) })
        let bySHA = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let attention = Dictionary(grouping: worktrees.filter {
            !$0.isBare && ($0.dirtyCount > 0 || !$0.statusKnown || $0.isPrunable)
        }, by: \.headSHA)
        return stride(from: 0, to: graph.nodes.count, by: size).map { first in
            let last = min(first + size, graph.nodes.count) - 1
            let nodes = graph.nodes[first...last]
            var rows: [RepositoryGraphRow] = []
            var commitRows: [String: Int] = [:]
            var links: [RepositoryWorktreeLink] = []
            for node in nodes {
                let pending = attention[node.id] ?? []
                let commitRow = rows.count + pending.count
                for worktree in pending {
                    links.append(RepositoryWorktreeLink(path: worktree.path, lane: node.lane,
                        worktreeRow: rows.count, commitRow: commitRow))
                    rows.append(.worktree(worktree))
                }
                commitRows[node.id] = rows.count
                rows.append(.commit(node))
            }
            let segments = graph.edges.compactMap { edge -> RepositoryGraphSegment? in
                guard let childIndex = indices[edge.childSHA], let parentIndex = indices[edge.parentSHA],
                      childIndex <= last, parentIndex >= first,
                      let child = bySHA[edge.childSHA], let parent = bySHA[edge.parentSHA] else { return nil }
                let childRow = commitRows[edge.childSHA]
                let parentRow = commitRows[edge.parentSHA]
                return RepositoryGraphSegment(id: edge.id, childLane: child.lane,
                    parentLane: parentRow == nil ? child.lane : parent.lane,
                    childRow: childRow, parentRow: parentRow,
                    isContinuation: childRow == nil || parentRow == nil, hiddenCommits: edge.hiddenCommits)
            }
            return RepositoryGraphPage(rows: rows, segments: segments, worktreeLinks: links)
        }
    }
}

public enum RepositoryGraphRow: Identifiable, Equatable, Sendable {
    case commit(AtlasGraphNode)
    case worktree(GitWorktree)
    public var id: String {
        switch self {
        case .commit(let node): return "commit:" + node.id
        case .worktree(let worktree): return "worktree:" + worktree.path
        }
    }
}

public struct RepositoryGraphPage: Equatable, Sendable {
    public let rows: [RepositoryGraphRow]
    public let segments: [RepositoryGraphSegment]
    public let worktreeLinks: [RepositoryWorktreeLink]
}

/// Nil row positions are the top/bottom continuation beyond the current page.
public struct RepositoryGraphSegment: Identifiable, Equatable, Sendable {
    public let id: String
    public let childLane: Int
    public let parentLane: Int
    public let childRow: Int?
    public let parentRow: Int?
    public let isContinuation: Bool
    public let hiddenCommits: Int
}

public struct RepositoryWorktreeLink: Equatable, Sendable {
    public let path: String
    public let lane: Int
    public let worktreeRow: Int
    public let commitRow: Int
}
