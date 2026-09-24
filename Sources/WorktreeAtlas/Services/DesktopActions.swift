import AppKit
import UniformTypeIdentifiers

@MainActor
enum DesktopActions {
    static func chooseRepositories() -> [String] {
        let panel = NSOpenPanel()
        panel.title = "添加本地 Git 仓库或任意工作树"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map(\.path)
    }
    static func chooseParent() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择新工作树的父目录"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
    static func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    static func openFolder(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    static func open(_ path: String, with bundleID: String) async throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw NSError(domain: "WorktreeAtlas", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到对应应用，请先安装后重试。"])
        }
        let config = NSWorkspace.OpenConfiguration()
        _ = try await NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: config)
    }
}
