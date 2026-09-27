import SwiftUI
import AtlasCore

/// A vertical commit graph. Lines represent real ancestor edges and badges mark HEADs.
struct GraphCanvasView: View {
    let snapshot: RepositorySnapshot
    let compact: Bool
    let selectedPath: String?
    let onSelect: (GitWorktree) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0
    @State private var detailedCommit: CommitNode?
    private let baseGraph: WorktreeGraph
    private let pageSize = 30

    init(snapshot: RepositorySnapshot, compact: Bool, selectedPath: String?, onSelect: @escaping (GitWorktree) -> Void) {
        self.snapshot = snapshot; self.compact = compact; self.selectedPath = selectedPath; self.onSelect = onSelect
        self.baseGraph = WorktreeGraphProjector.project(snapshot, compact: compact)
    }
    private var pageCount: Int { max(1, (baseGraph.nodes.count + pageSize - 1) / pageSize) }
    private var currentPage: Int { min(max(0, page), pageCount - 1) }
    private var graph: WorktreeGraph {
        if compact { return baseGraph }
        let range = currentPage * pageSize..<min((currentPage + 1) * pageSize, baseGraph.nodes.count)
        var nodes = Array(baseGraph.nodes[range])
        let visible = Set(nodes.map(\.id))
        for i in nodes.indices { nodes[i].row = i }
        return WorktreeGraph(nodes: nodes,
            edges: baseGraph.edges.filter { visible.contains($0.childSHA) && visible.contains($0.parentSHA) },
            unplacedWorktrees: baseGraph.unplacedWorktrees, totalCommits: baseGraph.totalCommits)
    }
    private func rowHeight(_ node: AtlasGraphNode) -> CGFloat {
        92 + CGFloat(node.worktrees.count) * 34 + (node.commit.body.isEmpty ? 0 : 28)
    }
    private func nodePositions(_ nodes: [AtlasGraphNode]) -> [String: CGFloat] {
        var positions: [String: CGFloat] = [:]
        var top: CGFloat = 0
        for node in nodes {
            positions[node.id] = top + 28
            top += rowHeight(node)
        }
        return positions
    }
    var body: some View {
        VStack(spacing: 0) {
            if graph.nodes.isEmpty {
                ContentUnavailableView("还没有提交图", systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("空仓库或 HEAD 无法读取时，工作树仍显示在下方。"))
                    .frame(height: 190)
            } else {
                ScrollView(.vertical) { timeline }
                    .frame(height: compact ? 530 : 620)
            }
            if !graph.unplacedWorktrees.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HEAD 未载入 / 尚无提交").font(.caption).foregroundStyle(.secondary)
                    ForEach(graph.unplacedWorktrees) { worktree in
                        Button { onSelect(worktree) } label: { WorktreeBadge(worktree: worktree) }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            HStack(spacing: 7) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                if compact { Text("\(graph.nodes.count) 个节点 · 折叠 \(graph.hiddenCommits) 个提交") }
                else {
                    Button { page = max(0, currentPage - 1) } label: { Image(systemName: "chevron.left") }.disabled(currentPage == 0)
                    Text("第 \(currentPage + 1) / \(pageCount) 页 · 每页最多 \(pageSize) 个提交")
                    Button { page = min(pageCount - 1, currentPage + 1) } label: { Image(systemName: "chevron.right") }.disabled(currentPage >= pageCount - 1)
                }
                Spacer()
                Text("上子下父 · 时间见每行").help("纵向位置是拓扑顺序，不代表实际时间间隔。")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 11)
        }
        .onChange(of: pageCount) { _, _ in page = currentPage }
        .sheet(item: $detailedCommit) { commit in
            VStack(alignment: .leading, spacing: 14) {
                Text(commit.subject.isEmpty ? "无标题提交" : commit.subject).font(.title2.bold())
                HStack(spacing: 12) {
                    Text(commit.committedDate.formatted(date: .complete, time: .shortened))
                    Text(commit.authorName)
                    Text(shortSHA(commit.sha)).fontDesign(.monospaced)
                }.font(.caption).foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    Text(commit.body).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("关闭") { detailedCommit = nil }.keyboardShortcut(.cancelAction)
                }
            }.padding(24).frame(minWidth: 520, minHeight: 340)
        }
    }
    private var timeline: some View {
        let visibleGraph = graph
        let nodes = visibleGraph.nodes
        let laneStep: CGFloat = visibleGraph.laneCount > 8 ? 14 : 20
        let railWidth = max(48, CGFloat(visibleGraph.laneCount) * laneStep + 30)
        func railX(_ lane: Int) -> CGFloat { 23 + CGFloat(lane) * laneStep }
        let positions = nodePositions(nodes)
        let lookup = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let loadedIDs = Set(baseGraph.nodes.map(\.id))
        let pageIDs = Set(nodes.map(\.id))
        let height = nodes.reduce(CGFloat(0)) { $0 + rowHeight($1) }
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in visibleGraph.edges {
                    guard let child = lookup[edge.childSHA], let parent = lookup[edge.parentSHA],
                          let fromY = positions[child.id], let toY = positions[parent.id] else { continue }
                    let start = CGPoint(x: railX(child.lane), y: fromY)
                    let end = CGPoint(x: railX(parent.lane), y: toY)
                    var path = Path(); path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: start.x, y: start.y + (end.y - start.y) * 0.55),
                                  control2: CGPoint(x: end.x, y: end.y - (end.y - start.y) * 0.45))
                    context.stroke(path, with: .color(AtlasStyle.lane(child.lane).opacity(0.8)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    if edge.hiddenCommits > 0 {
                        let label = Text("+\(edge.hiddenCommits)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                        context.draw(label, at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
                    }
                }
                for node in nodes {
                    guard let y = positions[node.id] else { continue }
                    let center = CGPoint(x: railX(node.lane), y: y)
                    let color = AtlasStyle.lane(node.lane)
                    if node.worktrees.contains(where: { $0.path == selectedPath }) {
                        context.fill(Path(ellipseIn: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)),
                                     with: .color(color.opacity(0.23)))
                    }
                    let radius: CGFloat = node.worktrees.isEmpty ? 5 : 8
                    let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    context.fill(dot, with: .color(color))
                    context.stroke(dot, with: .color(colorScheme == .dark ? .black : .white), lineWidth: 2)
                }
            }.frame(height: height)
            VStack(spacing: 0) {
                ForEach(nodes) { node in
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear.frame(width: railWidth)
                        commitDetails(node, loadedIDs: loadedIDs, pageIDs: pageIDs)
                            .padding(.trailing, 16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: rowHeight(node), alignment: .top)
                    .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1).padding(.leading, railWidth) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
    }
    private func commitDetails(_ node: AtlasGraphNode, loadedIDs: Set<String>, pageIDs: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(node.commit.subject.isEmpty ? "无标题提交" : node.commit.subject)
                    .font(.system(size: 13, weight: node.worktrees.isEmpty ? .medium : .semibold))
                    .lineLimit(2).textSelection(.enabled)
                Spacer(minLength: 4)
                Text(shortSHA(node.id)).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Text(node.commit.committedDate.formatted(date: .abbreviated, time: .shortened))
                if !node.commit.authorName.isEmpty { Text("· \(node.commit.authorName)").lineLimit(1) }
                if node.isHistoryBoundary { Text("· 更早历史未载入").foregroundStyle(.orange) }
                else if !compact && node.commit.parentSHAs.contains(where: { loadedIDs.contains($0) && !pageIDs.contains($0) }) {
                    Text("· 下页继续").foregroundStyle(.secondary)
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            if !node.commit.body.isEmpty {
                Button { detailedCommit = node.commit } label: {
                    HStack(alignment: .top, spacing: 4) {
                        Text(node.commit.body).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right.square")
                    }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("查看完整提交正文")
            }
            ForEach(node.worktrees) { worktree in
                Button { onSelect(worktree) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: worktree.isLocked ? "lock.fill" : "arrow.triangle.branch")
                        Text(worktree.isDetached ? "游离 HEAD" : worktree.title).lineLimit(1)
                        Text("HEAD").font(.system(size: 9, design: .monospaced))
                        Spacer(minLength: 2)
                        Circle().fill(AtlasStyle.status(worktree)).frame(width: 5, height: 5)
                        Text(worktree.statusSummary).lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(worktree.path == selectedPath ? AtlasStyle.selectedText(colorScheme) : .primary)
                    .padding(.horizontal, 9).frame(height: 28)
                    .background(AtlasStyle.worktreeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(AtlasStyle.status(worktree).opacity(0.35)))
                }.buttonStyle(.plain).help(worktree.path)
            }
        }
        .padding(.top, 14)
    }
}
