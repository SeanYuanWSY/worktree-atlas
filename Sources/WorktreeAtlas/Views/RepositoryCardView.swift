import SwiftUI
import AtlasCore

struct RepositoryCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: RepositorySnapshot
    let error: String?
    let focused: Bool
    let selectedPath: String?
    let canMutate: Bool
    let onSelect: (GitWorktree) -> Void
    let onFocus: () -> Void
    let onCreate: () -> Void
    let onPrune: () -> Void
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Button { collapsed.toggle() } label: {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold)).frame(width: 14)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
                Text(snapshot.record.displayName).font(.system(size: 11, weight: .medium))
                Text(snapshot.record.rootPath).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(snapshot.record.rootPath)
                Spacer(minLength: 8)
                Text("\(snapshot.worktrees.filter { !$0.isBare }.count) 工作树")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if !focused {
                    Button(action: onFocus) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.buttonStyle(.plain).help("聚焦此仓库")
                }
                Menu {
                    Button("新建工作树…", action: onCreate).disabled(!canMutate)
                    Button("预览失效记录清理…", action: onPrune).disabled(!canMutate)
                    Button("在 Finder 中显示") { DesktopActions.reveal(snapshot.record.rootPath) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 24)
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(AtlasStyle.card(colorScheme))

            if !collapsed {
                Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1)
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(snapshot.worktrees.filter { !$0.isBare }) { worktree in
                            Button { onSelect(worktree) } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(Color(red: 0.95, green: 0.38, blue: 0.7))
                                        .frame(width: 5, height: 5)
                                    Text(worktree.title).lineLimit(1)
                                    if worktree.isLocked { Image(systemName: "lock.fill") }
                                    if worktree.dirtyCount > 0 { Text("\(worktree.dirtyCount)").foregroundStyle(.orange) }
                                }
                                .font(.system(size: 10))
                                .padding(.horizontal, 6).frame(height: 18)
                                .background(worktree.path == selectedPath ? AtlasStyle.accent.opacity(0.14) : AtlasStyle.worktreeSurface(colorScheme),
                                            in: RoundedRectangle(cornerRadius: 2))
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(
                                    worktree.path == selectedPath ? AtlasStyle.accent.opacity(0.7) : AtlasStyle.divider(colorScheme)))
                            }.buttonStyle(.plain).help(worktree.path)
                        }
                    }.padding(.horizontal, 12)
                }.scrollIndicators(.hidden).frame(height: 27)
                if let error {
                    Label("刷新失败，显示上次快照：\(error)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).padding(.horizontal, 12).padding(.vertical, 5)
                }
                GraphCanvasView(snapshot: snapshot, compact: !focused, selectedPath: selectedPath, onSelect: onSelect)
                if snapshot.historyTruncated || !snapshot.warnings.isEmpty {
                    Text(snapshot.warnings.first ?? "只显示已载入历史；更早提交仍可能存在。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                }
            }
        }
        .background(AtlasStyle.card(colorScheme))
        .overlay(alignment: .bottom) { Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1) }
    }
}
