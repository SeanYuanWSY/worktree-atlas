import SwiftUI
import AtlasCore

struct GraphCanvasView: View {
    let snapshot: RepositorySnapshot
    let compact: Bool
    let selectedPath: String?
    let onSelect: (GitWorktree) -> Void
    @State private var zoom: Double = 1
    @State private var followsFit = false
    @State private var page = 0

    private let baseGraph: WorktreeGraph
    private var pageCount: Int { max(1, (baseGraph.nodes.count + 79) / 80) }
    private var currentPage: Int { min(max(0, page), pageCount - 1) }
    private var graph: WorktreeGraph {
        if compact { return baseGraph }
        let current = currentPage
        let range = current * 80..<min((current + 1) * 80, baseGraph.nodes.count)
        var nodes = Array(baseGraph.nodes[range])
        let visible = Set(nodes.map(\.id))
        let minimumColumn = nodes.map(\.column).min() ?? 0
        for i in nodes.indices {
            nodes[i].row = i; nodes[i].column -= minimumColumn
            nodes[i].isHistoryBoundary = nodes[i].isHistoryBoundary || nodes[i].commit.parentSHAs.contains { !visible.contains($0) }
        }
        return WorktreeGraph(nodes: nodes,
            edges: baseGraph.edges.filter { visible.contains($0.childSHA) && visible.contains($0.parentSHA) },
            unplacedWorktrees: baseGraph.unplacedWorktrees, totalCommits: baseGraph.totalCommits)
    }
    init(snapshot: RepositorySnapshot, compact: Bool, selectedPath: String?, onSelect: @escaping (GitWorktree) -> Void) {
        self.snapshot = snapshot; self.compact = compact; self.selectedPath = selectedPath; self.onSelect = onSelect
        self.baseGraph = WorktreeGraphProjector.project(snapshot, compact: compact)
    }
    private var stepX: CGFloat { 170 }
    private var stepY: CGFloat { 160 + CGFloat(max(0, (graph.nodes.map { $0.worktrees.count }.max() ?? 1) - 1)) * 65 }
    private var canvasSize: CGSize {
        CGSize(width: max(480, CGFloat(graph.nodes.map(\.column).max() ?? 0) * stepX + 190),
               height: max(220, CGFloat(graph.laneCount - 1) * stepY + 220))
    }
    private func point(_ node: AtlasGraphNode) -> CGPoint {
        CGPoint(x: 95 + CGFloat(node.column) * stepX, y: 60 + CGFloat(node.lane) * stepY)
    }
    private func fittedZoom(for width: CGFloat) -> Double {
        max(0.45, min(1, Double((width - 12) / canvasSize.width)))
    }
    var body: some View {
        VStack(spacing: 0) {
            if graph.nodes.isEmpty {
                ContentUnavailableView("还没有提交图", systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("空仓库或 HEAD 无法读取时，工作树仍显示在下方。"))
                    .frame(height: 190)
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        graphContent.frame(width: canvasSize.width, height: canvasSize.height)
                            .scaleEffect(zoom, anchor: .topLeading)
                            .frame(width: canvasSize.width * zoom, height: canvasSize.height * zoom, alignment: .topLeading)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 10) {
                            Button { followsFit = false; zoom = max(0.45, zoom - 0.15) } label: { Image(systemName: "minus.magnifyingglass") }
                            Button("适应") { followsFit = true; zoom = fittedZoom(for: geometry.size.width) }
                            Button { followsFit = false; zoom = min(1.6, zoom + 0.15) } label: { Image(systemName: "plus.magnifyingglass") }
                        }.buttonStyle(.borderless).font(.caption)
                            .padding(8).background(.regularMaterial, in: Capsule()).padding(8)
                    }
                    .onAppear {
                        if compact { followsFit = true; zoom = fittedZoom(for: geometry.size.width) }
                    }
                    .onChange(of: geometry.size.width) { _, width in
                        if followsFit { zoom = fittedZoom(for: width) }
                    }
                    .onChange(of: canvasSize.width) { _, _ in
                        if followsFit { zoom = fittedZoom(for: geometry.size.width) }
                    }
                    .onChange(of: compact) { _, isCompact in
                        if isCompact { followsFit = true; zoom = fittedZoom(for: geometry.size.width) }
                    }
                }.frame(height: compact ? min(420, max(255, canvasSize.height * zoom)) : 480)
            }
            if !graph.unplacedWorktrees.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HEAD 未载入 / 尚无提交").font(.caption).foregroundStyle(.secondary)
                    ForEach(graph.unplacedWorktrees) { worktree in
                        Button { onSelect(worktree) } label: { WorktreeBadge(worktree: worktree) }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            HStack(spacing: 6) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                if compact { Text("\(graph.nodes.count) 个节点 · 折叠 \(graph.hiddenCommits) 个提交") }
                else {
                    Button { page = max(0, currentPage - 1) } label: { Image(systemName: "chevron.left") }.disabled(currentPage == 0)
                    Text("第 \(currentPage + 1) / \(pageCount) 页 · 每页最多 80 个提交")
                    Button { page = min(pageCount - 1, currentPage + 1) } label: { Image(systemName: "chevron.right") }.disabled(currentPage >= pageCount - 1)
                }
                Spacer()
                Text("左 → 右：旧 → 新").help("位置表示拓扑顺序，不代表实际时间间隔。")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .onChange(of: pageCount) { _, _ in page = currentPage }
    }
    private var graphContent: some View {
        let nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                // A quiet dotted grid provides spatial context without competing with the graph.
                for x in stride(from: CGFloat(15), through: size.width, by: 24) {
                    for y in stride(from: CGFloat(12), through: size.height, by: 24) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.secondary.opacity(0.12)))
                    }
                }
                for edge in graph.edges {
                    guard let child = nodesByID[edge.childSHA], let parent = nodesByID[edge.parentSHA] else { continue }
                    let start = point(parent), end = point(child)
                    var path = Path(); path.move(to: start)
                    let middleX = (start.x + end.x) / 2
                    path.addCurve(to: end, control1: CGPoint(x: middleX, y: start.y), control2: CGPoint(x: middleX, y: end.y))
                    let color = AtlasStyle.lane(child.lane)
                    context.stroke(path, with: .color(color.opacity(0.72)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    if edge.hiddenCommits > 0 {
                        let label = Text("+\(edge.hiddenCommits)").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                        context.draw(label, at: CGPoint(x: middleX, y: (start.y + end.y) / 2 - 12))
                    }
                }
                for node in graph.nodes {
                    let p = point(node)
                    let radius: CGFloat = node.worktrees.isEmpty ? 4 : 7
                    if node.worktrees.contains(where: { $0.path == selectedPath }) {
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)), with: .color(AtlasStyle.lane(node.lane).opacity(0.18)))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(AtlasStyle.lane(node.lane)))
                    if node.isHistoryBoundary {
                        var tail = Path(); tail.move(to: CGPoint(x: p.x - 9, y: p.y)); tail.addLine(to: CGPoint(x: p.x - 40, y: p.y))
                        context.stroke(tail, with: .color(.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    }
                }
            }
            ForEach(graph.nodes) { node in
                let p = point(node)
                VStack(spacing: 5) {
                    if node.worktrees.isEmpty {
                        Text(node.commit.refs.first(where: { $0.name == snapshot.record.defaultBranch })?.name ?? shortSHA(node.id))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    } else {
                        ForEach(node.worktrees) { worktree in
                            Button { onSelect(worktree) } label: { WorktreeBadge(worktree: worktree) }
                                .buttonStyle(.plain)
                        }
                    }
                    if node.isHistoryBoundary { Text(compact ? "更早历史未载入" : "视图边界").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                .frame(width: 160)
                .fixedSize(horizontal: false, vertical: true)
                .position(x: p.x, y: p.y + (node.worktrees.isEmpty ? 23 : 41 + CGFloat(max(0, node.worktrees.count - 1)) * 30))
                .help(node.commit.subject)
            }
        }
    }
}
