import SwiftUI
import AtlasCore

struct WorktreeInspector: View {
    @Environment(\.colorScheme) private var colorScheme
    let worktree: GitWorktree
    let repository: RepositoryRecord
    let canMutate: Bool
    let onClose: () -> Void
    let onRemove: () -> Void
    let onToggleLock: () -> Void
    let onError: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("WORKTREE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(AtlasToolbarButtonStyle()).help("关闭详情")
                        .keyboardShortcut(.cancelAction)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 20)).foregroundStyle(AtlasStyle.accent)
                        .frame(width: 38, height: 38).background(AtlasStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    Text(worktree.title).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                    HStack(spacing: 5) {
                        MetadataPill(text: worktree.statusSummary, color: AtlasStyle.status(worktree))
                        if worktree.isMain { MetadataPill(text: "主工作树") }
                        if worktree.isLocked { MetadataPill(text: "锁定", symbol: "lock", color: .indigo) }
                    }
                }
                Divider()
                field("本地路径", worktree.path)
                field("HEAD", displayedHEAD)
                if hasHEAD {
                    Button { DesktopActions.copy(worktree.headSHA) } label: {
                        Label("复制完整 HEAD", systemImage: "doc.on.doc")
                    }.font(.caption).buttonStyle(.borderless)
                }
                field("同步状态", worktree.hasUpstream && worktree.statusKnown
                    ? "↑ \(worktree.aheadCount) 领先  ·  ↓ \(worktree.behindCount) 落后"
                    : "未设置上游，或状态尚未读取")
                Text("同步差异基于本地缓存的远端引用；本应用不会自动 fetch。").font(.caption).foregroundStyle(.secondary)
                if let reason = worktree.lockReason { field("锁定原因", reason) }
                if let error = worktree.statusError { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Button { DesktopActions.reveal(worktree.path) } label: { Label("在 Finder 中显示", systemImage: "folder") }
                    Button { DesktopActions.copy(worktree.path) } label: { Label("复制路径", systemImage: "doc.on.doc") }
                    Menu {
                        Button("Terminal") { open("com.apple.Terminal") }
                        Button("Visual Studio Code") { open("com.microsoft.VSCode") }
                        Button("Cursor") { open("com.todesktop.230313mzl4w4u92") }
                        Button("Xcode") { open("com.apple.dt.Xcode") }
                    } label: { Label("用外部应用打开", systemImage: "arrow.up.forward.app") }
                }.buttonStyle(.borderless)
                if !worktree.isMain && !worktree.isBare {
                    Divider()
                    Button(action: onToggleLock) {
                        Label(worktree.isLocked ? "解锁工作树…" : "锁定以防误清理", systemImage: worktree.isLocked ? "lock.open" : "lock")
                    }.disabled(!canMutate || worktree.directoryIdentity == nil)
                    Button(role: .destructive, action: onRemove) { Label("移除工作树…", systemImage: "trash") }
                        .disabled(!canMutate || !worktree.canOfferRemoval)
                    Text("只移除工作目录，保留分支。存在修改、未跟踪文件、被忽略文件或未知状态时拒绝移除。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !canMutate { Text("演示模式、操作中或数据过期时，写入操作不可用。").font(.caption).foregroundStyle(.secondary) }
            }.padding(16)
        }.font(.system(size: 11)).frame(width: 272).background(AtlasStyle.chrome(colorScheme))
    }
    private var hasHEAD: Bool {
        !worktree.headSHA.isEmpty && !worktree.headSHA.allSatisfy { $0 == "0" }
    }
    private var displayedHEAD: String {
        guard hasHEAD else { return "尚无提交" }
        let sha = worktree.headSHA
        guard sha.count > 20 else { return sha }
        let middle = sha.index(sha.startIndex, offsetBy: sha.count / 2)
        return String(sha[..<middle]) + "\n" + String(sha[middle...])
    }
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func open(_ bundle: String) {
        Task { do { try await DesktopActions.open(worktree.path, with: bundle) } catch { onError(error.localizedDescription) } }
    }
}
