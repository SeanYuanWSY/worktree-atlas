import Foundation
import Testing
@testable import AtlasCore

@Suite struct GraphTests {
    func node(_ id: String, _ parents: [String]) -> CommitNode { CommitNode(sha: id, parentSHAs: parents) }
    func snapshot(_ nodes: [CommitNode], heads: [String]) -> RepositorySnapshot {
        RepositorySnapshot(record: .init(displayName: "test", rootPath: "/tmp/test"),
                           worktrees: heads.enumerated().map { .init(path: "/wt/\($0.offset)", headSHA: $0.element) }, commits: nodes)
    }
    @Test
    func testLinearCommitsCompressWithExactCount() {
        let s = snapshot([node("a", []), node("b", ["a"]), node("c", ["b"]), node("d", ["c"])], heads: ["d"])
        let graph = WorktreeGraphProjector.project(s)
        #expect((Set(graph.nodes.map(\.id))) == (["a", "d"]))
        #expect((graph.edges.first?.hiddenCommits) == (2))
    }
    @Test
    func testMergeAndForkSurvive() {
        let s = snapshot([node("r", []), node("a", ["r"]), node("b", ["r"]), node("m", ["a", "b"])], heads: ["m", "a", "b"])
        let graph = WorktreeGraphProjector.project(s)
        #expect((graph.nodes.count) == (4))
        #expect((graph.edges.count) == (4))
    }
    @Test
    func testMergePathsRemainDistinctWithoutWorktreesOnParents() {
        let s = snapshot([node("r", []), node("a", ["r"]), node("b", ["r"]), node("m", ["a", "b"])], heads: ["m"])
        let graph = WorktreeGraphProjector.project(s)
        #expect((graph.nodes.count) == (4))
        #expect((Set(graph.edges.map(\.id)).count) == (graph.edges.count))
    }
    @Test
    func testMultipleWorktreesAtSameHeadNotLost() {
        let graph = WorktreeGraphProjector.project(snapshot([node("a", [])], heads: ["a", "a", "a"]))
        #expect((graph.nodes.count) == (1))
        #expect((graph.nodes[0].worktrees.count) == (3))
    }
    @Test
    func testDetachedUnknownHeadRemainsVisible() {
        let graph = WorktreeGraphProjector.project(snapshot([node("a", [])], heads: ["missing"]))
        #expect((graph.unplacedWorktrees.map(\.headSHA)) == (["missing"]))
    }
    @Test
    func testHistoryBoundaryIsNotInventedRoot() {
        let graph = WorktreeGraphProjector.project(snapshot([node("b", ["not-loaded"])], heads: ["b"]))
        #expect(graph.nodes[0].isHistoryBoundary)
        #expect(graph.edges.isEmpty)
    }
    @Test
    func testFullModeRetainsAllNodes() {
        let s = snapshot([node("a", []), node("b", ["a"]), node("c", ["b"])], heads: ["c"])
        #expect((WorktreeGraphProjector.project(s, compact: false).nodes.count) == (3))
    }
    @Test
    func testDefaultBranchIsAnchorWithoutWorktree() {
        var s = snapshot([node("a", []), node("b", ["a"]), node("c", ["b"])], heads: ["c"])
        s.record.defaultBranch = "main"; s.branches = [.init(branchName: "main", headSHA: "b")]
        #expect((WorktreeGraphProjector.project(s).nodes.count) == (3))
    }
    @Test
    func testTopologyWinsOverAuthorDates() {
        var a = node("a", []); a.authoredDate = Date(timeIntervalSince1970: 900)
        var b = node("b", ["a"]); b.authoredDate = Date(timeIntervalSince1970: 1)
        #expect((WorktreeGraphProjector.topologicalOrder([a, b]).map(\.sha)) == (["b", "a"]))
    }
    @Test
    func testUnrelatedHistoriesStayDisconnected() {
        let graph = WorktreeGraphProjector.project(snapshot([node("a", []), node("b", [])], heads: ["a", "b"]))
        #expect(graph.edges.isEmpty)
    }
    @Test
    func testDuplicateCommitInputDeduplicated() {
        #expect((WorktreeGraphProjector.project(snapshot([node("a", []), node("a", [])], heads: ["a"])).nodes.count) == (1))
    }
    @Test
    func testGeneratedDAGsPreserveReachabilityAndDeterminism() {
        // Deterministic pseudo-random graph corpus, including octopus merges.
        var state: UInt64 = 4281
        func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1; return state }
        for _ in 0..<80 {
            var commits = [node("0", [])]
            for i in 1..<45 {
                var parents = [String(Int(next() % UInt64(i)))]
                if next() % 4 == 0 { parents.append(String(Int(next() % UInt64(i)))) }
                commits.append(node(String(i), Array(Set(parents)).sorted()))
            }
            let s = snapshot(commits, heads: ["44", "43", "20"])
            let graph = WorktreeGraphProjector.project(s)
            #expect((graph) == (WorktreeGraphProjector.project(s)))
            let original = Dictionary(uniqueKeysWithValues: commits.map { ($0.sha, $0.parentSHAs) })
            let reduced = Dictionary(grouping: graph.edges, by: \.childSHA).mapValues { $0.map(\.parentSHA) }
            func reachable(_ start: String, _ target: String, _ edges: [String: [String]]) -> Bool {
                var queue = [start], visited = Set<String>()
                while let current = queue.popLast() {
                    if current == target { return true }
                    if visited.insert(current).inserted { queue += edges[current] ?? [] }
                }
                return false
            }
            for left in graph.nodes {
                for right in graph.nodes {
                    #expect((reachable(left.id, right.id, original)) == (reachable(left.id, right.id, reduced)))
                }
            }
        }
    }
}
