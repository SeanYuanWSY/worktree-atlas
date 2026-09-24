import SwiftUI
import AtlasCore

struct RepositoryCardView: View {
    let snapshot: RepositorySnapshot
    let error: String?
    let focused: Bool
    let selectedPath: String?
    let canMutate: Bool
    let onSelect: (GitWorktree) -> Void
    let onFocus: () -> Void
    let onCreate: () -> Void
    let onPrune: () -> Void
    @State private var fullHistory = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox").foregroundStyle(AtlasStyle.accent)
                        Text(snapshot.record.displayName).font(.system(size: 18, weight: .semibold))
                    }
                    Text(snapshot.record.rootPath).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(snapshot.record.rootPath)
                }
                Spacer()
                if !focused { Button(action: onFocus) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.buttonStyle(.borderless).help("聚焦此仓库") }
                Menu {
                    Button("新建工作树…", action: onCreate).disabled(!canMutate)
                    Button("预览失效记录清理…", action: onPrune).disabled(!canMutate)
                    Button("在 Finder 中显示") { DesktopActions.reveal(snapshot.record.rootPath) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
            }.padding(18)
            HStack(spacing: 6) {
                MetadataPill(text: "\(snapshot.worktrees.filter { !$0.isBare }.count) worktrees", symbol: "arrow.triangle.branch", color: .teal)
                let changed = snapshot.worktrees.filter { $0.statusKnown && $0.dirtyCount > 0 }.count
                if changed > 0 { MetadataPill(text: "\(changed) 有修改", color: .orange) }
                Spacer()
                if focused { Toggle("完整已载入历史", isOn: $fullHistory).toggleStyle(.switch).controlSize(.mini).font(.caption) }
            }.padding(.horizontal, 18).padding(.bottom, 14)
            if let error {
                Label("刷新失败：以下是旧快照。\(error)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal, 18).padding(.bottom, 8)
            }
            Divider().opacity(0.5)
            GraphCanvasView(snapshot: snapshot, compact: !focused || !fullHistory, selectedPath: selectedPath, onSelect: onSelect)
            if snapshot.historyTruncated || !snapshot.warnings.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                    Text(snapshot.warnings.first ?? "已限制历史读取量；虚线表示更早提交尚未载入。")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.07), lineWidth: 1))
    }
}
