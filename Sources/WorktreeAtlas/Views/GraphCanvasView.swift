import SwiftUI
import AppKit
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
    @State private var hoveredCommit: String?
    private let allGraph: WorktreeGraph
    private let rowHeight: CGFloat = 22
    private let refsWidth: CGFloat = 236
    private let authorWidth: CGFloat = 32
    private let dateWidth: CGFloat = 64
    private let shaWidth: CGFloat = 62
    private func tagWidth(_ title: String) -> CGFloat {
        let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium)]).width
        return min(refsWidth - 8, max(52, ceil(textWidth) + 30))
    }

    init(snapshot: RepositorySnapshot, compact: Bool, selectedPath: String?, onSelect: @escaping (GitWorktree) -> Void) {
        self.snapshot = snapshot
        self.compact = compact
        self.selectedPath = selectedPath
        self.onSelect = onSelect
        var projected = WorktreeGraphProjector.project(snapshot, compact: false)
        if let main = snapshot.worktrees.first(where: { $0.isMain }) {
            let commits = Dictionary(snapshot.commits.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })
            var mainline: Set<String> = []
            var cursor: String? = main.headSHA
            while let sha = cursor, mainline.insert(sha).inserted {
                cursor = commits[sha]?.parentSHAs.first
            }
            let otherLanes = Set(projected.nodes.filter { !mainline.contains($0.id) }.map(\.lane)).sorted()
            let laneMap = Dictionary(uniqueKeysWithValues: otherLanes.enumerated().map { ($0.element, $0.offset + 1) })
            // Reserve the left rail for the checkout's first-parent history; ancestry and row order stay intact.
            for index in projected.nodes.indices {
                let node = projected.nodes[index]
                projected.nodes[index].lane = mainline.contains(node.id) ? 0 : laneMap[node.lane] ?? node.lane + 1
            }
        }
        self.allGraph = projected
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
    private enum DisplayRow: Identifiable {
        case commit(AtlasGraphNode)
        case worktree(GitWorktree)
        var id: String {
            switch self {
            case .commit(let node): return "commit:" + node.id
            case .worktree(let worktree): return "worktree:" + worktree.path
            }
        }
    }
    private func displayRows(_ graph: WorktreeGraph) -> [DisplayRow] {
        graph.nodes.flatMap { node in
            attentionWorktrees.filter { $0.headSHA == node.id }.map(DisplayRow.worktree) + [.commit(node)]
        }
    }
    private func edgePath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        if from.x == to.x {
            path.addLine(to: to)
        } else {
            let bend = max(from.y, to.y - rowHeight * 0.65)
            path.addLine(to: CGPoint(x: from.x, y: bend))
            path.addCurve(to: to, control1: CGPoint(x: from.x, y: to.y),
                          control2: CGPoint(x: to.x, y: bend))
        }
        return path
    }
    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    var body: some View {
        let visibleGraph = graph
        let count = displayRows(visibleGraph).count
        let minimumWidth = max(780, max(88, CGFloat(allGraph.laneCount) * 17 + 24) + refsWidth + authorWidth + dateWidth + shaWidth + 260)
        let tableHeight = min(compact ? CGFloat(392) : CGFloat(760), max(100, CGFloat(count) * rowHeight + 22))
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
                        .frame(width: max(minimumWidth, geometry.size.width), height: geometry.size.height)
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
        let graphWidth = max(88, CGFloat(allGraph.laneCount) * 17 + 24)
        return HStack(spacing: 0) {
            Text("提交图").padding(.leading, 10).frame(width: graphWidth, alignment: .leading)
            Text("分支 / 工作树").frame(width: refsWidth, alignment: .leading)
            Text("信息").frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "person.crop.circle").frame(width: authorWidth, alignment: .leading)
            Text("日期").frame(width: dateWidth, alignment: .leading)
            Text("SHA").frame(width: shaWidth, alignment: .leading)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(height: 22)
        .background(AtlasStyle.chrome(colorScheme))
        .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
    }
    private func tableRows(graph: WorktreeGraph) -> some View {
        let nodes = graph.nodes
        let rows = displayRows(graph)
        let graphWidth = max(88, CGFloat(allGraph.laneCount) * 17 + 24)
        var positions: [String: CGFloat] = [:]
        var worktreePositions: [String: CGFloat] = [:]
        for (index, row) in rows.enumerated() {
            let y = (CGFloat(index) + 0.5) * rowHeight
            switch row {
            case .commit(let node): positions[node.id] = y
            case .worktree(let worktree): worktreePositions[worktree.path] = y
            }
        }
        let lookup = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let visibleEdgeIDs = Set(graph.edges.map(\.id))
        let allRows = Dictionary(uniqueKeysWithValues: allGraph.nodes.enumerated().map { ($0.element.id, $0.offset) })
        let allNodes = Dictionary(uniqueKeysWithValues: allGraph.nodes.map { ($0.id, $0) })
        let firstRow = currentPage * pageSize
        let lastRow = firstRow + nodes.count - 1
        let graphHeight = CGFloat(rows.count) * rowHeight
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    switch row {
                    case .worktree(let worktree): wipRow(worktree, graphWidth: graphWidth)
                    case .commit(let node): commitRow(node, graphWidth: graphWidth)
                    }
                }
            }
            Canvas { context, _ in
                func laneX(_ lane: Int) -> CGFloat { 24 + CGFloat(lane) * 17 }
                context.fill(Path(CGRect(x: laneX(0) - 8, y: 0, width: 16, height: graphHeight)),
                             with: .color(AtlasStyle.lane(0).opacity(0.065)))
                for edge in graph.edges {
                    guard let child = lookup[edge.childSHA], let parent = lookup[edge.parentSHA],
                          let from = positions[child.id], let to = positions[parent.id] else { continue }
                    let path = edgePath(from: CGPoint(x: laneX(child.lane), y: from),
                                        to: CGPoint(x: laneX(parent.lane), y: to))
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
                    let endLane = positions[edge.parentSHA] == nil ? child.lane : parent.lane
                    let path = edgePath(from: CGPoint(x: laneX(child.lane), y: from),
                                        to: CGPoint(x: laneX(endLane), y: to))
                    context.stroke(path, with: .color(AtlasStyle.lane(child.lane).opacity(0.7)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                for worktree in attentionWorktrees {
                    guard let y = worktreePositions[worktree.path], let node = allNodes[worktree.headSHA],
                          let endY = positions[worktree.headSHA] else { continue }
                    let x = laneX(node.lane)
                    var line = Path(); line.move(to: CGPoint(x: x, y: y))
                    line.addLine(to: CGPoint(x: x, y: endY))
                    context.stroke(line, with: .color(AtlasStyle.lane(node.lane)),
                                   style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    let circle = Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11))
                    context.fill(circle, with: .color(AtlasStyle.card(colorScheme)))
                    context.stroke(circle, with: .color(AtlasStyle.lane(node.lane)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [1, 2]))
                }
                for node in nodes {
                    guard let y = positions[node.id] else { continue }
                    let x = laneX(node.lane)
                    let color = AtlasStyle.lane(node.lane)
                    if !node.worktrees.isEmpty {
                        context.fill(Path(CGRect(x: 10, y: y - rowHeight / 2, width: graphWidth - 12, height: rowHeight)),
                                     with: .color(color.opacity(colorScheme == .dark ? 0.09 : 0.07)))
                    }
                    let radius: CGFloat = 5.5
                    let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    context.fill(dot, with: .color(AtlasStyle.card(colorScheme)))
                    context.stroke(dot, with: .color(color), lineWidth: 1.3)
                    let initial = String(node.commit.authorName.prefix(1)).uppercased()
                    context.draw(Text(initial).font(.system(size: 6, weight: .medium)).foregroundColor(color),
                                 at: CGPoint(x: x, y: y))

                }
            }
            .frame(width: graphWidth, height: graphHeight)
            .allowsHitTesting(false)
        }
        .frame(height: graphHeight, alignment: .top)
    }
    private func wipRow(_ worktree: GitWorktree, graphWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: graphWidth)
            HStack {
                Spacer()
                Label(worktree.statusKnown && !worktree.isPrunable ? "\(worktree.dirtyCount)" : "?",
                      systemImage: worktree.statusKnown && !worktree.isPrunable ? "pencil" : "exclamationmark.triangle")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).frame(height: 16)
                    .background(AtlasStyle.worktreeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(AtlasStyle.divider(colorScheme)))
            }.padding(.trailing, 10).frame(width: refsWidth)
            HStack(spacing: 6) {
                Text(worktree.isPrunable ? "路径不可用" : worktree.statusKnown ? "工作树更改" : "状态未知")
                    .font(.system(size: 11, weight: .semibold)).italic().foregroundStyle(.secondary)
                Button { onSelect(worktree) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "desktopcomputer")
                        Text(worktree.title).lineLimit(1)
                    }
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).frame(height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(AtlasStyle.divider(colorScheme)))
                }.buttonStyle(.plain).help(worktree.path)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: authorWidth)
            Text(worktree.isPrunable ? "待检查" : worktree.statusKnown ? "未提交" : "待刷新")
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: dateWidth, alignment: .leading)
            Color.clear.frame(width: shaWidth)
        }
        .frame(height: rowHeight)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 0.5) }
    }
    private func commitRow(_ node: AtlasGraphNode, graphWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: graphWidth)
            refCell(node).frame(width: refsWidth, alignment: .leading)
            Button {
                detailedCommit = node.commit
            } label: {
                Text(node.commit.subject.isEmpty ? "无标题提交" : node.commit.subject)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(node.commit.body.isEmpty ? node.commit.subject : "\(node.commit.subject)\n\n\(node.commit.body)")
            Text(String(node.commit.authorName.prefix(1)).uppercased())
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(AtlasStyle.lane(node.lane))
                .frame(width: 12, height: 12)
                .background(AtlasStyle.lane(node.lane).opacity(0.13), in: Circle())
                .frame(width: authorWidth, alignment: .leading).help(node.commit.authorName)
            Text(relativeTime(node.commit.committedDate))
                .frame(width: dateWidth, alignment: .leading).foregroundStyle(.secondary)
                .help(node.commit.committedDate.formatted(date: .complete, time: .standard))
            Text(shortSHA(node.id)).fontDesign(.monospaced).foregroundStyle(.tertiary)
                .frame(width: shaWidth, alignment: .leading)
        }
        .font(.system(size: 10))
        .frame(height: rowHeight)
        .background(node.worktrees.contains(where: { $0.path == selectedPath })
                    ? AtlasStyle.selection(colorScheme)
                    : hoveredCommit == node.id ? Color.primary.opacity(0.035) : .clear)
        .onHover { hovering in hoveredCommit = hovering ? node.id : nil }
        .overlay(alignment: .bottom) {
            if !node.worktrees.isEmpty { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 0.5) }
        }
    }
    private func refCell(_ node: AtlasGraphNode) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(node.worktrees) { worktree in
                    Button { onSelect(worktree) } label: {
                        refLabel(worktree.title, color: worktree.isMain ? Color(red: 0.31, green: 0.79, blue: 0.6) : AtlasStyle.lane(node.lane), symbol: "desktopcomputer", filled: worktree.isMain)
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
    private func refLabel(_ title: String, color: Color, symbol: String, filled: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(filled ? Color.black.opacity(0.85) : color)
        .padding(.horizontal, 5).frame(width: tagWidth(title), height: 17, alignment: .leading)
        .background(color.opacity(filled ? 1 : 0.025), in: RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(color.opacity(0.7)))
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
            Image(systemName: "point.3.connected.trianglepath.dotted").help("上方为子提交，下方为父提交；连线表示真实提交关系")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).frame(height: 21)
        .overlay(alignment: .top) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
    }
}
