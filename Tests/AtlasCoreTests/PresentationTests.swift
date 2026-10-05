import Foundation
import Testing
@testable import AtlasCore

@Suite struct PresentationTests {
    @Test func fullTableRetainsTopologyAndEveryHead() {
        let snapshot = DemoWorkspace.snapshots[0]
        let presentation = RepositoryGraphPresentation(snapshot: snapshot)
        let original = WorktreeGraphProjector.project(snapshot, compact: false)
        #expect(presentation.graph.edges == original.edges)
        #expect(presentation.graph.nodes.map(\.id) == original.nodes.map(\.id))
        #expect(Set(presentation.graph.nodes.flatMap(\.worktrees).map(\.path)) == Set(snapshot.worktrees.map(\.path)))
        let main = snapshot.worktrees.first(where: \.isMain)!
        #expect(presentation.graph.nodes.first(where: { $0.id == main.headSHA })?.lane == 0)
    }

    @Test func pagesKeepAllCommitsAndCrossPageContinuations() {
        let presentation = RepositoryGraphPresentation(snapshot: DemoWorkspace.snapshots[0])
        func commits(_ page: RepositoryGraphPage) -> [String] {
            page.rows.compactMap { if case .commit(let node) = $0 { return node.id }; return nil }
        }
        #expect(presentation.overviewPages.count == 2)
        #expect(presentation.focusedPages.count == 1)
        #expect(presentation.overviewPages.flatMap(commits) == presentation.graph.nodes.map(\.id))
        #expect(presentation.focusedPages.flatMap(commits) == presentation.graph.nodes.map(\.id))
        let first = presentation.overviewPages[0].segments.filter(\.isContinuation)
        let last = presentation.overviewPages[1].segments.filter(\.isContinuation)
        #expect(!first.isEmpty)
        #expect(Set(first.map(\.id)) == Set(last.map(\.id)))
        #expect(first.allSatisfy { $0.parentRow == nil })
        #expect(last.allSatisfy { $0.childRow == nil })
    }

    @Test func sharedHeadAttentionRowsKeepSeparatePathsAndCoordinates() {
        let commit = CommitNode(sha: "head", parentSHAs: [])
        let worktrees = [GitWorktree(path: "/demo/one", headSHA: "head", dirtyCount: 1, statusKnown: true),
                        GitWorktree(path: "/demo/two", headSHA: "head", statusKnown: false)]
        let snapshot = RepositorySnapshot(record: .init(displayName: "test", rootPath: "/demo"), worktrees: worktrees, commits: [commit])
        let page = RepositoryGraphPresentation(snapshot: snapshot).overviewPages[0]
        #expect(page.rows.count == 3)
        #expect(Set(page.rows.map(\.id)).count == 3)
        #expect(page.worktreeLinks.map(\.worktreeRow) == [0, 1])
        #expect(page.worktreeLinks.allSatisfy { $0.commitRow == 2 })
        #expect(Set(page.worktreeLinks.map(\.path)) == Set(worktrees.map(\.path)))
    }

    @Test func unchangedScansReusePresentationButContentChangesInvalidateIt() {
        var snapshot = DemoWorkspace.snapshots[0]
        let presentation = RepositoryGraphPresentation(snapshot: snapshot)
        snapshot.record.lastScannedAt = Date().addingTimeInterval(100)
        snapshot.record.displayName = "Renamed"
        #expect(presentation.matches(snapshot))
        snapshot.worktrees[0].dirtyCount = 2
        #expect(!presentation.matches(snapshot))
        snapshot.worktrees[0].dirtyCount = 0
        snapshot.commits[0].body = "Changed message"
        #expect(!presentation.matches(snapshot))
    }

    @Test func emptyAndUnavailableHeadsRemainVisible() {
        let worktree = GitWorktree(path: "/demo/missing", headSHA: "not-loaded")
        let snapshot = RepositorySnapshot(record: .init(displayName: "empty", rootPath: "/demo"), worktrees: [worktree], commits: [])
        let presentation = RepositoryGraphPresentation(snapshot: snapshot)
        #expect(presentation.overviewPages.count == 1)
        #expect(presentation.focusedPages.count == 1)
        #expect(presentation.overviewPages[0].rows.isEmpty)
        #expect(presentation.graph.unplacedWorktrees == [worktree])
    }
}
