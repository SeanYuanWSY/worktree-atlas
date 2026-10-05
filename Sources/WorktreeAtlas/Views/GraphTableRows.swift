import SwiftUI
import AppKit
import AtlasCore

struct GraphColumns {
    let graph: CGFloat
    let refs: CGFloat
    let author: CGFloat
    let date: CGFloat
    let sha: CGFloat
    init(width: CGFloat, laneCount: Int, compact: Bool, authorNames: Bool, absoluteDates: Bool) {
        graph = max(88, CGFloat(laneCount) * 17 + 24)
        refs = compact ? min(176, max(116, width * 0.22)) : 236
        author = authorNames ? (compact ? min(100, max(72, width * 0.125)) : 132) : 32
        date = absoluteDates ? (compact ? 84 : 94) : (compact ? 56 : 64)
        sha = compact ? 50 : 62
    }
}

@MainActor
private enum GraphDateLabels {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    static func label(_ date: Date, absolute: Bool) -> String {
        absolute ? date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
                 : relative.localizedString(for: date, relativeTo: Date())
    }
}

/// Hover is row-local: moving the pointer does not invalidate the graph canvas or other repositories.
struct GraphCommitRow: View {
    let node: AtlasGraphNode
    let columns: GraphColumns
    let rowHeight: CGFloat
    let selectedPath: String?
    let authorNames: Bool
    let absoluteDates: Bool
    let onSelect: (GitWorktree) -> Void
    let onDetails: (CommitNode) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: columns.graph)
            GraphRefCell(node: node, width: columns.refs, rowHeight: rowHeight, onSelect: onSelect)
            Button { onDetails(node.commit) } label: {
                Text(node.commit.subject.isEmpty ? "无标题提交" : node.commit.subject)
                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.84))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 12).frame(height: rowHeight).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(node.commit.body.isEmpty ? node.commit.subject : "\(node.commit.subject)\n\n\(node.commit.body)")
            GraphAuthorCell(name: node.commit.authorName, showName: authorNames, width: columns.author)
            Text(GraphDateLabels.label(node.commit.committedDate, absolute: absoluteDates))
                .frame(width: columns.date, alignment: .leading).foregroundStyle(.secondary).lineLimit(1)
                .help(node.commit.committedDate.formatted(date: .complete, time: .standard))
            Text(shortSHA(node.id)).fontDesign(.monospaced).foregroundStyle(.tertiary)
                .frame(width: columns.sha, alignment: .leading)
        }
        .font(.system(size: 10)).frame(height: rowHeight)
        .background(node.worktrees.contains(where: { $0.path == selectedPath }) ? AtlasStyle.selection(colorScheme)
                    : hovered ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("查看提交详情") { onDetails(node.commit) }
            Button("复制完整 SHA") { DesktopActions.copy(node.id) }
            Button("复制提交标题") { DesktopActions.copy(node.commit.subject) }
        }
        .overlay(alignment: .bottom) {
            if !node.worktrees.isEmpty { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 0.5) }
        }
    }
}

struct GraphWorktreeRow: View {
    let worktree: GitWorktree
    let columns: GraphColumns
    let rowHeight: CGFloat
    let onSelect: (GitWorktree) -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: columns.graph)
            HStack {
                Spacer()
                Label(worktree.statusKnown && !worktree.isPrunable ? "\(worktree.dirtyCount)" : "?",
                      systemImage: worktree.statusKnown && !worktree.isPrunable ? "pencil" : "exclamationmark.triangle")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).frame(height: 16)
                    .background(AtlasStyle.worktreeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(AtlasStyle.divider(colorScheme)))
            }.padding(.trailing, 10).frame(width: columns.refs)
            Button { onSelect(worktree) } label: {
                Text(worktree.isPrunable ? "路径不可用" : worktree.statusKnown ? "工作树更改" : "状态未知")
                    .font(.system(size: 11, weight: .medium)).italic().foregroundStyle(.secondary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help("\(worktree.title)\n\(worktree.path)")
            Color.clear.frame(width: columns.author)
            Text(worktree.isPrunable ? "待检查" : worktree.statusKnown ? "未提交" : "待刷新")
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: columns.date, alignment: .leading)
            Color.clear.frame(width: columns.sha)
        }
        .frame(height: rowHeight).background(Color.primary.opacity(0.025))
        .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 0.5) }
    }
}

private struct GraphAuthorCell: View {
    let name: String
    let showName: Bool
    let width: CGFloat
    var body: some View {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = normalized.lowercased().utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        let color = AtlasStyle.lane(Int(identity % 8))
        let words = normalized.split(whereSeparator: { $0.isWhitespace })
        let initials = words.count > 1 ? String(words.prefix(2).compactMap(\.first)) : String(normalized.prefix(1))
        return HStack(spacing: 6) {
            Text(initials.isEmpty ? "?" : initials.uppercased()).font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color).frame(width: 18, height: 18)
                .background(color.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(color.opacity(0.3), lineWidth: 0.5)).accessibilityHidden(true)
            if showName {
                Text(normalized.isEmpty ? "未知作者" : normalized).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.trailing, 8).frame(width: width, alignment: .leading)
        .help(normalized.isEmpty ? "未知作者" : normalized).accessibilityElement(children: .ignore)
        .accessibilityLabel("作者：\(normalized.isEmpty ? "未知作者" : normalized)")
    }
}

private struct GraphRefCell: View {
    let node: AtlasGraphNode
    let width: CGFloat
    let rowHeight: CGFloat
    let onSelect: (GitWorktree) -> Void
    private var refs: [GitRef] {
        node.commit.refs.filter { ref in
            (ref.kind == .localBranch || ref.kind == .remoteBranch || ref.kind == .tag)
                && !node.worktrees.contains(where: { $0.branchName == ref.name })
        }
    }
    var body: some View {
        Group {
            if node.worktrees.isEmpty && refs.isEmpty {
                Color.clear
            } else if node.worktrees.count + refs.count == 1 {
                labels
            } else {
                ScrollView(.horizontal) { labels }.scrollIndicators(.never)
            }
        }
        .frame(width: width - 8, height: rowHeight, alignment: .leading)
        .clipped()
        .frame(width: width, height: rowHeight, alignment: .leading)
    }
    private var labels: some View {
        HStack(spacing: 5) {
            ForEach(node.worktrees) { worktree in
                Button { onSelect(worktree) } label: {
                    GraphRefLabel(title: worktree.title, color: worktree.isMain ? Color(red: 0.31, green: 0.79, blue: 0.6) : AtlasStyle.lane(node.lane),
                                  symbol: "desktopcomputer", filled: worktree.isMain, maxWidth: width - 8)
                }.buttonStyle(.plain).help(worktree.path)
            }
            ForEach(refs) { ref in
                GraphRefLabel(title: ref.name, color: AtlasStyle.lane(node.lane),
                              symbol: ref.kind == .remoteBranch ? "cloud" : ref.kind == .tag ? "tag" : "arrow.triangle.branch", maxWidth: width - 8)
            }
        }.frame(height: rowHeight, alignment: .leading)
    }
}

private struct GraphRefLabel: View {
    let title: String
    let color: Color
    let symbol: String
    var filled = false
    let maxWidth: CGFloat
    var body: some View {
        let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium)]).width
        return HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 10, weight: .medium)).foregroundStyle(filled ? Color.black.opacity(0.85) : color)
        .padding(.horizontal, 5).frame(width: min(maxWidth, max(52, ceil(textWidth) + 30)), height: 17, alignment: .leading)
        .background(color.opacity(filled ? 1 : 0.025), in: RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(color.opacity(0.7))).help(title)
    }
}
