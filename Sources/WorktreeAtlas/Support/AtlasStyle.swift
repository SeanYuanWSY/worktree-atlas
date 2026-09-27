import SwiftUI
import AtlasCore

enum AtlasStyle {
    static let accent = Color(red: 0.31, green: 0.91, blue: 0.94)
    static let laneColors: [Color] = [
        accent, Color(red: 0.55, green: 0.64, blue: 1),
        Color(red: 1, green: 0.68, blue: 0.38),
        Color(red: 0.94, green: 0.46, blue: 0.73),
        Color(red: 0.4, green: 0.72, blue: 1),
        Color(red: 0.74, green: 0.59, blue: 1),
        Color(red: 0.49, green: 0.87, blue: 0.6)
    ]
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.025, green: 0.038, blue: 0.057) : Color(nsColor: .windowBackgroundColor)
    }
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.055, green: 0.076, blue: 0.105) : Color(nsColor: .controlBackgroundColor)
    }
    static func worktreeSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.085, green: 0.126, blue: 0.16) : Color(nsColor: .textBackgroundColor)
    }
    static func selectedText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accent : Color(red: 0, green: 0.43, blue: 0.49)
    }
    static func divider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accent.opacity(0.1) : .primary.opacity(0.07)
    }
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
    @Environment(\.colorScheme) private var colorScheme
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
        .background(AtlasStyle.worktreeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AtlasStyle.status(worktree).opacity(0.3), lineWidth: 1))
        .help("\(worktree.title)\nHEAD \(headLabel)\n\(worktree.path)\n\(stateLabel)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(worktree.title)，HEAD \(headLabel)，\(stateLabel)")
    }
}
