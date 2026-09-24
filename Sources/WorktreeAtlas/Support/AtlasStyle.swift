import SwiftUI
import AtlasCore

enum AtlasStyle {
    static let accent = Color.teal
    static let laneColors: [Color] = [.teal, .indigo, .orange, .pink, .blue, .purple, .green]
    static func lane(_ value: Int) -> Color { laneColors[abs(value) % laneColors.count] }
    static func status(_ worktree: GitWorktree) -> Color {
        if worktree.isPrunable || !worktree.statusKnown { return .orange }
        if worktree.dirtyCount > 0 { return .orange }
        return .teal
    }
}
struct MetadataPill: View {
    let text: String
    var symbol: String? = nil
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.09), in: Capsule())
    }
}
struct WorktreeBadge: View {
    let worktree: GitWorktree
    private var headLabel: String {
        let sha = worktree.headSHA
        return sha.isEmpty || sha.allSatisfy({ $0 == "0" }) ? "无提交" : shortSHA(sha)
    }
    private var stateLabel: String {
        worktree.statusSummary + (worktree.isLocked ? " · 锁定" : "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: worktree.isLocked ? "lock.fill" : "arrow.triangle.branch")
                    .foregroundStyle(worktree.isLocked ? .indigo : AtlasStyle.status(worktree))
                Text(worktree.isDetached ? "游离 HEAD" : worktree.title)
                    .lineLimit(1).truncationMode(.middle)
            }
            Text("HEAD \(headLabel)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Circle().fill(AtlasStyle.status(worktree)).frame(width: 5, height: 5)
                Text(stateLabel).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(AtlasStyle.status(worktree))
            }
            .font(.system(size: 10, weight: .medium))
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 136, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AtlasStyle.status(worktree).opacity(0.3), lineWidth: 1))
        .help("\(worktree.title)\nHEAD \(headLabel)\n\(worktree.path)\n\(stateLabel)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(worktree.title)，HEAD \(headLabel)，\(stateLabel)")
    }
}
