import SwiftUI
import AtlasCore

/// A vertical commit table backed by immutable, precomputed pages.
struct GraphCanvasView: View {
    let presentation: RepositoryGraphPresentation
    let compact: Bool
    let selectedPath: String?
    let onSelect: (GitWorktree) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0
    @State private var detailedCommit: CommitNode?
    @AppStorage("graphComfortable") private var comfortable = false
    @AppStorage("graphAuthorNames") private var authorNames = true
    @AppStorage("graphAbsoluteDates") private var absoluteDates = false
    private var rowHeight: CGFloat { comfortable ? 30 : 24 }
    private var pages: [RepositoryGraphPage] { compact ? presentation.overviewPages : presentation.focusedPages }
    private var currentPage: Int { min(max(0, page), pages.count - 1) }

    var body: some View {
        VStack(spacing: 0) {
            if presentation.graph.nodes.isEmpty {
                ContentUnavailableView("还没有提交图", systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("空仓库或 HEAD 无法读取。工作树仍可在下方打开。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    // The comparison board owns horizontal scrolling; its tables fit their panels.
                    // A focused table has its own horizontal scroll to retain full-width metadata.
                    if compact {
                        table(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        ScrollView(.horizontal) {
                            table(width: max(geometry.size.width, CGFloat(presentation.laneCount) * 17 + 794),
                                  height: geometry.size.height)
                        }
                        .scrollIndicators(.visible)
                    }
                }
            }
            if !presentation.graph.unplacedWorktrees.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HEAD 未载入 / 尚无提交").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(presentation.graph.unplacedWorktrees) { worktree in
                            Button { onSelect(worktree) } label: {
                                Label(worktree.title, systemImage: "desktopcomputer")
                                    .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).help(worktree.path)
                        }
                    }.padding(12)
                }.frame(maxHeight: 110)
            }
            footer
        }
        .onChange(of: pages.count) { _, _ in page = currentPage }
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
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("关闭") { detailedCommit = nil }.keyboardShortcut(.cancelAction) }
            }.padding(22).frame(minWidth: 520, minHeight: 340)
        }
    }

    private func table(width: CGFloat, height: CGFloat) -> some View {
        let columns = GraphColumns(width: width - 16, laneCount: presentation.laneCount,
                                   compact: compact, authorNames: authorNames, absoluteDates: absoluteDates)
        let visiblePage = pages[currentPage]
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("提交图").padding(.leading, 10).frame(width: columns.graph, alignment: .leading)
                Text("分支 / 工作树").frame(width: columns.refs, alignment: .leading)
                Text("信息").frame(maxWidth: .infinity, alignment: .leading)
                Text("作者").frame(width: columns.author, alignment: .leading)
                Text("日期").frame(width: columns.date, alignment: .leading)
                Text("SHA").frame(width: columns.sha, alignment: .leading)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary).frame(height: 26)
            .padding(.trailing, 16).background(AtlasStyle.chrome(colorScheme))
            .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    LazyVStack(spacing: 0) {
                        ForEach(visiblePage.rows) { row in
                            switch row {
                            case .commit(let node):
                                GraphCommitRow(node: node, columns: columns, rowHeight: rowHeight,
                                    selectedPath: selectedPath, authorNames: authorNames, absoluteDates: absoluteDates,
                                    onSelect: onSelect, onDetails: { detailedCommit = $0 })
                            case .worktree(let worktree):
                                GraphWorktreeRow(worktree: worktree, columns: columns, rowHeight: rowHeight, onSelect: onSelect)
                            }
                        }
                    }
                    graphRail(visiblePage, width: columns.graph)
                }
                .frame(width: width - 16, height: CGFloat(visiblePage.rows.count) * rowHeight, alignment: .topLeading)
            }
            .scrollIndicators(.visible).id(currentPage)
        }.frame(width: width, height: height)
    }

    private func graphRail(_ visiblePage: RepositoryGraphPage, width: CGFloat) -> some View {
        let rowHeight = self.rowHeight
        let graphHeight = CGFloat(visiblePage.rows.count) * rowHeight
        return Canvas { context, _ in
            func laneX(_ lane: Int) -> CGFloat { 24 + CGFloat(lane) * 17 }
            func rowY(_ row: Int) -> CGFloat { (CGFloat(row) + 0.5) * rowHeight }
            context.fill(Path(CGRect(x: laneX(0) - 8, y: 0, width: 16, height: graphHeight)),
                         with: .color(AtlasStyle.lane(0).opacity(0.065)))
            for segment in visiblePage.segments {
                let from = CGPoint(x: laneX(segment.childLane), y: segment.childRow.map(rowY) ?? 0)
                let to = CGPoint(x: laneX(segment.parentLane), y: segment.parentRow.map(rowY) ?? graphHeight)
                var path = Path(); path.move(to: from)
                if from.x == to.x { path.addLine(to: to) }
                else {
                    let bend = max(from.y, to.y - rowHeight * 0.65)
                    path.addLine(to: CGPoint(x: from.x, y: bend))
                    path.addCurve(to: to, control1: CGPoint(x: from.x, y: to.y), control2: CGPoint(x: to.x, y: bend))
                }
                context.stroke(path, with: .color(AtlasStyle.lane(segment.childLane).opacity(segment.isContinuation ? 0.7 : 0.85)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: segment.isContinuation ? [3, 3] : []))
            }
            for link in visiblePage.worktreeLinks {
                let x = laneX(link.lane), y = rowY(link.worktreeRow)
                var line = Path(); line.move(to: CGPoint(x: x, y: y)); line.addLine(to: CGPoint(x: x, y: rowY(link.commitRow)))
                context.stroke(line, with: .color(AtlasStyle.lane(link.lane)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                let dot = Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11))
                context.fill(dot, with: .color(AtlasStyle.card(colorScheme)))
                context.stroke(dot, with: .color(AtlasStyle.lane(link.lane)), style: StrokeStyle(lineWidth: 1.5, dash: [1, 2]))
            }
            for (index, row) in visiblePage.rows.enumerated() {
                guard case .commit(let node) = row else { continue }
                let x = laneX(node.lane), y = rowY(index), color = AtlasStyle.lane(node.lane)
                if !node.worktrees.isEmpty {
                    context.fill(Path(CGRect(x: 10, y: y - rowHeight / 2, width: width - 12, height: rowHeight)),
                                 with: .color(color.opacity(colorScheme == .dark ? 0.09 : 0.07)))
                }
                let dot = Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11))
                context.fill(dot, with: .color(AtlasStyle.card(colorScheme)))
                context.stroke(dot, with: .color(color), lineWidth: 1.3)
                context.draw(Text(String(node.commit.authorName.prefix(1)).uppercased()).font(.system(size: 6, weight: .medium)).foregroundColor(color),
                             at: CGPoint(x: x, y: y))
            }
        }.frame(width: width, height: graphHeight).allowsHitTesting(false)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(presentation.graph.totalCommits) 个提交")
            if pages.count > 1 {
                Button { page = max(0, currentPage - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(currentPage == 0).help("上一页提交")
                Text("\(currentPage + 1) / \(pages.count)").monospacedDigit()
                Button { page = min(pages.count - 1, currentPage + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(currentPage == pages.count - 1).help("下一页提交")
            }
            Spacer(minLength: 4)
            if pages.count > 1 { Text("虚线延续至相邻页").lineLimit(1) }
            Image(systemName: "point.3.connected.trianglepath.dotted").help("上方为子提交，下方为父提交；连线表示真实提交关系")
        }
        .buttonStyle(.borderless).font(.system(size: 10)).foregroundStyle(.secondary)
        .padding(.horizontal, 12).frame(height: 28)
        .background(AtlasStyle.chrome(colorScheme))
        .overlay(alignment: .top) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
    }
}
