import SwiftUI
import AtlasCore

struct WorkspaceSidebarView: View {
    let records: [RepositoryRecord]
    let failures: [UUID: String]
    let selectedRepository: UUID?
    let isDemo: Bool
    let paused: Bool
    let busy: Bool
    let onSelect: (UUID?) -> Void
    let onAdd: () -> Void
    let onForget: (UUID) -> Void
    let onPause: () -> Void
    let onLeaveDemo: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ATLAS").font(.system(size: 14, weight: .semibold, design: .monospaced)).tracking(2.5)
                Text("Git worktree workspace").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).frame(height: 76, alignment: .leading)
            HStack {
                Text("仓库").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text("\(records.count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                Spacer()
                Button(action: onAdd) { Image(systemName: "plus") }.disabled(busy).help("添加仓库")
            }.buttonStyle(AtlasToolbarButtonStyle()).padding(.horizontal, 14).frame(height: 30)
            ScrollView {
                LazyVStack(spacing: 4) {
                    WorkspaceNavigationRow(title: "全部仓库", symbol: "rectangle.split.2x1", selected: selectedRepository == nil, warning: false) { onSelect(nil) }
                    ForEach(records) { record in
                        WorkspaceNavigationRow(title: record.displayName, symbol: "folder", selected: selectedRepository == record.id,
                            warning: failures[record.id] != nil) { onSelect(record.id) }
                            .help(record.rootPath)
                            .contextMenu {
                                Button("从总览移除（不删除文件）") { onForget(record.id) }.disabled(busy)
                            }
                    }
                }.padding(.horizontal, 10).padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1)
                HStack(spacing: 7) {
                    Circle().fill(isDemo ? AtlasStyle.violet : AtlasStyle.accent).frame(width: 5, height: 5)
                    Text(isDemo ? "演示工作区" : "本地工作区").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    if isDemo {
                        Button(action: onLeaveDemo) { Image(systemName: "arrow.uturn.backward") }.help("返回真实仓库")
                    } else {
                        Button(action: onPause) { Image(systemName: paused ? "play" : "pause") }
                            .help(paused ? "恢复自动刷新" : "暂停自动刷新")
                    }
                }.buttonStyle(AtlasToolbarButtonStyle())
            }.padding(.horizontal, 14).padding(.bottom, 12)
        }.background(AtlasStyle.chrome(colorScheme))
    }
}

private struct WorkspaceNavigationRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let warning: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 16)
                    .foregroundStyle(selected ? AtlasStyle.selectedText(colorScheme) : .secondary)
                Text(title).font(.system(size: 11, weight: selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                if warning { Circle().fill(.orange).frame(width: 4, height: 4) }
            }
            .padding(.horizontal, 11).frame(height: 34)
            .background(selected ? AtlasStyle.selection(colorScheme) : hovered ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) {
                if selected { RoundedRectangle(cornerRadius: 1).fill(AtlasStyle.accent).frame(width: 2, height: 14).padding(.leading, 1) }
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
    }
}
