import SwiftUI
import AtlasCore

struct RepositoryCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: RepositorySnapshot
    let presentation: RepositoryGraphPresentation
    let error: String?
    let focused: Bool
    let selectedPath: String?
    let canMutate: Bool
    let onSelect: (GitWorktree) -> Void
    let onFocus: () -> Void
    let onCreate: () -> Void
    let onPrune: () -> Void
    private var worktrees: [GitWorktree] { snapshot.worktrees.filter { !$0.isBare } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(AtlasStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(AtlasStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(AtlasStyle.accent.opacity(0.2)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.record.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(snapshot.record.rootPath).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(snapshot.record.rootPath)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Circle().fill(error != nil ? .orange : AtlasStyle.accent).frame(width: 4, height: 4)
                    Text("\(worktrees.count) 工作树").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if !focused {
                    Button(action: onFocus) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(AtlasToolbarButtonStyle()).help("聚焦此仓库，查看完整提交信息")
                }
                Menu {
                    Button("新建工作树…", action: onCreate).disabled(!canMutate)
                    Button("预览失效记录清理…", action: onPrune).disabled(!canMutate)
                    Button("在 Finder 中显示") { DesktopActions.reveal(snapshot.record.rootPath) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 22).help("仓库操作")
            }
            .padding(.horizontal, 14).frame(height: 64)
            .background(LinearGradient(colors: [AtlasStyle.chrome(colorScheme), AtlasStyle.card(colorScheme)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1)
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(worktrees) { worktree in
                        Button { onSelect(worktree) } label: {
                            HStack(spacing: 5) {
                                Circle().fill(AtlasStyle.status(worktree)).frame(width: 4, height: 4)
                                Text(worktree.title).lineLimit(1).truncationMode(.middle)
                                if worktree.isLocked { Image(systemName: "lock.fill").font(.system(size: 8)) }
                                if worktree.dirtyCount > 0 { Text("\(worktree.dirtyCount)").foregroundStyle(.orange).monospacedDigit() }
                            }
                            .font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).frame(height: 23)
                            .background(worktree.path == selectedPath ? AtlasStyle.accent.opacity(0.13) : AtlasStyle.worktreeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(worktree.path == selectedPath ? AtlasStyle.accent.opacity(0.65) : AtlasStyle.divider(colorScheme)))
                        }.buttonStyle(.plain).help("\(worktree.title)\n\(worktree.path)")
                    }
                }.padding(.horizontal, 12)
            }.scrollIndicators(.hidden).frame(height: 39)
            if let error {
                Label("刷新失败，显示上次快照：\(error)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(3).padding(.horizontal, 12).padding(.bottom, 6)
            }
            GraphCanvasView(presentation: presentation, compact: !focused, selectedPath: selectedPath, onSelect: onSelect)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if snapshot.historyTruncated || !snapshot.warnings.isEmpty {
                Text(snapshot.warnings.first ?? "只显示已载入历史；更早提交仍可能存在。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 5)
            }
        }
        .background(AtlasStyle.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selectedPath == nil ? AtlasStyle.panelBorder(colorScheme) : AtlasStyle.accent.opacity(0.45)))
        .overlay(alignment: .top) {
            LinearGradient(colors: [AtlasStyle.accent.opacity(0.65), AtlasStyle.violet.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1).padding(.horizontal, 12).allowsHitTesting(false)
        }
    }
}
