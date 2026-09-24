import Foundation
import AtlasCore

@main
struct AtlasInspect {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.isEmpty {
            print("Usage: atlas-inspect <repository-path> | --demo\nRead-only diagnostics; no Git mutations.")
            return
        }
        do {
            let snapshots = args[0] == "--demo" ? DemoWorkspace.snapshots : [try await RepositoryScanner().scan(path: args[0])]
            let payload: [[String: Any]] = snapshots.map { snapshot in
                let graph = WorktreeGraphProjector.project(snapshot)
                return ["name": snapshot.record.displayName, "commonDirectory": snapshot.record.commonDirectory,
                        "historyTruncated": snapshot.historyTruncated, "warnings": snapshot.warnings,
                        "worktrees": snapshot.worktrees.map { ["path": $0.path, "branch": $0.branchName ?? "(detached)",
                            "head": $0.headSHA, "status": $0.statusSummary, "statusKnown": $0.statusKnown] },
                        "loadedCommits": graph.totalCommits, "visibleNodes": graph.nodes.count,
                        "nodes": graph.nodes.map { node in ["sha": node.id, "column": node.column, "lane": node.lane,
                            "row": node.row, "subject": node.commit.subject, "boundary": node.isHistoryBoundary,
                            "worktrees": node.worktrees.map { ["title": $0.title, "path": $0.path,
                                "status": $0.statusSummary, "dirty": $0.dirtyCount, "locked": $0.isLocked, "head": $0.headSHA] as [String: Any] }] as [String: Any] },
                        "edges": graph.edges.map { ["child": $0.childSHA, "parent": $0.parentSHA, "hiddenCommits": $0.hiddenCommits] as [String: Any] }]
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("atlas-inspect: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
