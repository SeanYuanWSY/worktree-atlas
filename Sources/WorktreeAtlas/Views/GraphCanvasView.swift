import SwiftUI
import AtlasCore

/// Dense, GitLens-inspired table with a real child-to-parent graph in its left column.
struct GraphCanvasView: View {
    let snapshot: RepositorySnapshot
    let compact: Bool
    let selectedPath: String?
    let onSelect: (GitWorktree) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0
    @State private var detailedCommit: CommitNode?
    private let allGraph: WorktreeGraph
    private let rowHeight: CGFloat = 30
    private let refsWidth: CGFloat = 260
    private let authorWidth: CGFloat = 96
    private let dateWidth: CGFloat = 82
    private let shaWidth: CGFloat = 75
    private func tagWidth(_ title: String) -> CGFloat {
        min(refsWidth - 8, max(76, CGFloat(title.count) * 8 + 36))
    }

    init(snapshot: RepositorySnapshot, compact: Bool, selectedPath: String?, onSelect: @escaping (GitWorktree) -> Void) {
        self.snapshot = snapshot
        self.compact = compact
        self.selectedPath = selectedPath
        self.onSelect = onSelect
        self.allGraph = WorktreeGraphProjector.project(snapshot, compact: false)
    }
    private var pageSize: Int { compact ? 40 : 80 }
    private var pageCount: Int { max(1, (allGraph.nodes.count + pageSize - 1) / pageSize) }
    private var currentPage: Int { min(max(0, page), pageCount - 1) }
    private var graph: WorktreeGraph {
        let range = currentPage * pageSize..<min((currentPage + 1) * pageSize, allGraph.nodes.count)
        let nodes = Array(allGraph.nodes[range])
        let visible = Set(nodes.map(\.id))
        return WorktreeGraph(nodes: nodes,
            edges: allGraph.edges.filter { visible.contains($0.childSHA) && visible.contains($0.parentSHA) },
            unplacedWorktrees: allGraph.unplacedWorktrees, totalCommits: allGraph.totalCommits)
    }
    private var attentionWorktrees: [GitWorktree] {
        snapshot.worktrees.filter { !$0.isBare && ($0.dirtyCount > 0 || !$0.statusKnown || $0.isPrunable) }
    }
    private var visibleAttentionWorktrees: [GitWorktree] { currentPage == 0 ? attentionWorktrees : [] }
    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    var body: some View {
        let visibleGraph = graph
        let count = visibleGraph.nodes.count + visibleAttentionWorktrees.count
        let tableHeight = min(compact ? CGFloat(530) : CGFloat(710), max(160, CGFloat(count) * rowHeight + 57))
        return VStack(spacing: 0) {
            if visibleGraph.nodes.isEmpty {
                ContentUnavailableView("还没有提交图", systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("空仓库或 HEAD 无法读取。工作树仍可在下方打开。"))
                    .frame(height: 180)
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            tableHeader(graph: visibleGraph)
                            ScrollView(.vertical) {
                                tableRows(graph: visibleGraph)
                            }
                            .scrollIndicators(.visible)
                        }
                        .frame(width: max(900, geometry.size.width), height: geometry.size.height)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(height: tableHeight)
            }
            if !visibleGraph.unplacedWorktrees.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HEAD 未载入 / 尚无提交")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(visibleGraph.unplacedWorktrees) { worktree in
                        Button { onSelect(worktree) } label: {
                            Label(worktree.title, systemImage: "desktopcomputer")
                                .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain).help(worktree.path)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            footer(graph: visibleGraph)
        }
        .onChange(of: pageCount) { _, _ in page = currentPage }
        .sheet(item: $detailedCommit) { commit in
            VStack(alignment: .leading, spacing: 13) {
                Text(commit.subject.isEmpty ? "无标题提交" : commit.subject).font(.title3.bold())
                HStack(spacing: 12) {
                    Text(commit.committedDate.formatted(date: .complete, time: .standard))
                    Text(commit.authorName)
                    Text(shortSHA(commit.sha)).fontDesign(.monospaced)
                }.font(.caption).foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    Text(commit.body.isEmpty ? "此提交没有正文。" : commit.body)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("关闭") { detailedCommit = nil }.keyboardShortcut(.cancelAction) }
            }
            .padding(22).frame(minWidth: 520, minHeight: 340)
        }
    }
    private func tableHeader(graph: WorktreeGraph) -> some View {
        let graphWidth = max(116, CGFloat(allGraph.laneCount) * 21 + 28)
        return HStack(spacing: 0) {
            Text("提交图").frame(width: graphWidth, alignment: .leading).padding(.leading, 10)
            Text("分支 / 工作树").frame(width: refsWidth, alignment: .leading)
            Text("信息").frame(maxWidth: .infinity, alignment: .leading)
            Text("作者").frame(width: authorWidth, alignment: .leading)
            Text("日期").frame(width: dateWidth, alignment: .leading)
            Text("SHA").frame(width: shaWidth, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(height: 29)
        .background(AtlasStyle.card(colorScheme))
        .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
    }
    private func tableRows(graph: WorktreeGraph) -> some View {
        let nodes = graph.nodes
        let wips = visibleAttentionWorktrees
        let graphWidth = max(116, CGFloat(allGraph.laneCount) * 21 + 28)
        let positions = Dictionary(uniqueKeysWithValues: nodes.enumerated().map {
            ($0.element.id, (CGFloat($0.offset + wips.count) + 0.5) * rowHeight)
        })
        let lookup = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let visibleEdgeIDs = Set(graph.edges.map(\.id))
        let allRows = Dictionary(uniqueKeysWithValues: allGraph.nodes.enumerated().map { ($0.element.id, $0.offset) })
        let allNodes = Dictionary(uniqueKeysWithValues: allGraph.nodes.map { ($0.id, $0) })
        let firstRow = currentPage * pageSize
        let lastRow = firstRow + nodes.count - 1
        let graphHeight = CGFloat(nodes.count + wips.count) * rowHeight
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                func laneX(_ lane: Int) -> CGFloat { 22 + CGFloat(lane) * 21 }
                for edge in graph.edges {
                    guard let child = lookup[edge.childSHA], let parent = lookup[edge.parentSHA],
                          let from = positions[child.id], let to = positions[parent.id] else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: laneX(child.lane), y: from))
                    path.addCurve(to: CGPoint(x: laneX(parent.lane), y: to),
                                  control1: CGPoint(x: laneX(child.lane), y: from + (to - from) * 0.55),
                                  control2: CGPoint(x: laneX(parent.lane), y: to - (to - from) * 0.45))
                    context.stroke(path, with: .color(AtlasStyle.lane(child.lane).opacity(0.85)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    if edge.hiddenCommits > 0 {
                        context.draw(Text("+\(edge.hiddenCommits)").font(.system(size: 8)).foregroundColor(.secondary),
                                     at: CGPoint(x: laneX(child.lane) + 8, y: (from + to) / 2))
                    }
                }
                for edge in allGraph.edges where !visibleEdgeIDs.contains(edge.id) {
                    guard let childRow = allRows[edge.childSHA], let parentRow = allRows[edge.parentSHA],
                          childRow <= lastRow, parentRow >= firstRow,
                          let child = allNodes[edge.childSHA], let parent = allNodes[edge.parentSHA] else { continue }
                    let from = positions[edge.childSHA] ?? 0
                    let to = positions[edge.parentSHA] ?? graphHeight
                    var path = Path()
                    path.move(to: CGPoint(x: laneX(child.lane), y: from))
                    path.addLine(to: CGPoint(x: laneX(parent.lane), y: to))
                    context.stroke(path, with: .color(AtlasStyle.lane(child.lane).opacity(0.7)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                for (index, worktree) in wips.enumerated() {
                    let lane = allNodes[worktree.headSHA]?.lane ?? 0
                    let start = CGPoint(x: laneX(lane), y: (CGFloat(index) + 0.5) * rowHeight)
                    if let endY = positions[worktree.headSHA] ?? (allRows[worktree.headSHA] == nil ? nil : graphHeight) {
                        var line = Path(); line.move(to: start)
                        line.addLine(to: CGPoint(x: start.x, y: endY))
                        context.stroke(line, with: .color(AtlasStyle.lane(lane).opacity(0.7)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    }
                    context.stroke(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)),
                                   with: .color(AtlasStyle.lane(lane)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                }
                for node in nodes {
                    guard let y = positions[node.id] else { continue }
                    let x = laneX(node.lane)
                    let color = AtlasStyle.lane(node.lane)
                    if !node.worktrees.isEmpty {
                        context.fill(Path(CGRect(x: 6, y: y - 14, width: graphWidth - 12, height: 28)),
                                     with: .color(color.opacity(colorScheme == .dark ? 0.09 : 0.07)))
                    }
                    let radius: CGFloat = node.worktrees.isEmpty ? 4 : 6
                    let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
                    context.fill(dot, with: .color(color))
                    context.stroke(dot, with: .color(AtlasStyle.card(colorScheme)), lineWidth: 1.5)
                }
            }
            .frame(width: graphWidth, height: graphHeight)
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                ForEach(wips) { worktree in wipRow(worktree, graphWidth: graphWidth) }
                ForEach(nodes) { node in commitRow(node, graphWidth: graphWidth) }
            }
        }
        .frame(height: graphHeight, alignment: .top)
    }
    private func wipRow(_ worktree: GitWorktree, graphWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: graphWidth)
            Button { onSelect(worktree) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                    Text(worktree.title).lineLimit(1)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AtlasStyle.selectedText(colorScheme))
                .padding(.horizontal, 6).frame(width: tagWidth(worktree.title), height: 20, alignment: .leading)
                .background(AtlasStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain).frame(width: refsWidth, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: worktree.isPrunable ? "externaldrive.badge.exclamationmark" : worktree.statusKnown ? "pencil" : "questionmark.circle")
                    .foregroundStyle(.orange)
                Text(worktree.isPrunable ? "工作树不可用" : worktree.statusKnown ? "工作树变更" : "工作树状态")
                    .fontWeight(.semibold)
                Text(worktree.statusSummary).foregroundStyle(.secondary)
            }
            .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
            Text("").frame(width: authorWidth)
            Text(worktree.isPrunable ? "待检查" : worktree.statusKnown ? "未提交" : "待刷新")
                .frame(width: dateWidth, alignment: .leading)
            Text("").frame(width: shaWidth)
        }
        .frame(height: rowHeight)
        .background(AtlasStyle.accent.opacity(colorScheme == .dark ? 0.055 : 0.035))
        .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
    }
    private func commitRow(_ node: AtlasGraphNode, graphWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: graphWidth)
            refCell(node).frame(width: refsWidth, alignment: .leading)
            Button {
                detailedCommit = node.commit
            } label: {
                Text(node.commit.subject.isEmpty ? "无标题提交" : node.commit.subject)
                    .font(.system(size: 11, weight: node.worktrees.isEmpty ? .regular : .medium))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(node.commit.body.isEmpty ? node.commit.subject : "\(node.commit.subject)\n\n\(node.commit.body)")
            Text(node.commit.authorName).lineLimit(1)
                .frame(width: authorWidth, alignment: .leading).foregroundStyle(.secondary)
            Text(relativeTime(node.commit.committedDate))
                .frame(width: dateWidth, alignment: .leading).foregroundStyle(.secondary)
                .help(node.commit.committedDate.formatted(date: .complete, time: .standard))
            Text(shortSHA(node.id)).fontDesign(.monospaced).foregroundStyle(.tertiary)
                .frame(width: shaWidth, alignment: .leading)
        }
        .font(.system(size: 10))
        .frame(height: rowHeight)
        .background(node.worktrees.contains(where: { $0.path == selectedPath })
                    ? AtlasStyle.accent.opacity(colorScheme == .dark ? 0.12 : 0.07) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
    }
    private func refCell(_ node: AtlasGraphNode) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(node.worktrees) { worktree in
                    Button { onSelect(worktree) } label: {
                        refLabel(worktree.title, color: AtlasStyle.lane(node.lane), symbol: "desktopcomputer")
                    }
                    .buttonStyle(.plain).help(worktree.path)
                }
                ForEach(node.commit.refs.filter { ref in
                    (ref.kind == .localBranch || ref.kind == .remoteBranch || ref.kind == .tag)
                        && !node.worktrees.contains(where: { $0.branchName == ref.name })
                }) { ref in
                    refLabel(ref.name, color: AtlasStyle.lane(node.lane),
                             symbol: ref.kind == .remoteBranch ? "cloud" : ref.kind == .tag ? "tag" : "arrow.triangle.branch")
                }
            }
            .frame(height: rowHeight, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(width: refsWidth, height: rowHeight, alignment: .leading)
    }
    private func refLabel(_ title: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 6).frame(width: tagWidth(title), height: 20, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(0.7)))
    }
    private func footer(graph: WorktreeGraph) -> some View {
        HStack(spacing: 8) {
            Text("\(allGraph.totalCommits) 个已载入提交")
            if pageCount > 1 {
                Button { page = max(0, currentPage - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(currentPage == 0)
                Text("\(currentPage + 1) / \(pageCount)")
                Button { page = min(pageCount - 1, currentPage + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(currentPage == pageCount - 1)
                Text("· 虚线延续到相邻页")
            }
            if !graph.unplacedWorktrees.isEmpty {
                Text("· \(graph.unplacedWorktrees.count) 个 HEAD 尚未载入").foregroundStyle(.orange)
            }
            Spacer()
            Text("上子下父 · 实线为真实提交关系")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).frame(height: 27)
        .overlay(alignment: .top) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
    }
}
