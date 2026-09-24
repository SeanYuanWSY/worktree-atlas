import SwiftUI
import AppKit

@main
struct WorktreeAtlasApp: App {
    @NSApplicationDelegateAdaptor(AtlasAppDelegate.self) private var delegate
    @StateObject private var model = WorkspaceModel()
    @AppStorage("appearance") private var appearance = "system"
    private var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    var body: some Scene {
        WindowGroup("Worktree Atlas", id: "main") {
            DashboardView(model: model)
                .frame(minWidth: 980, minHeight: 660)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1380, height: 880)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加仓库…") { model.add(paths: DesktopActions.chooseRepositories()) }.keyboardShortcut("o")
            }
            CommandMenu("工作树") {
                Button("刷新全部仓库") { model.refreshAll() }.keyboardShortcut("r")
                Toggle("暂停自动刷新", isOn: $model.paused)
                Divider()
                Button(model.isDemo ? "离开演示" : "打开交互演示") {
                    if model.isDemo { model.leaveDemo() } else { model.showDemo() }
                }
            }
        }
        Settings { SettingsView().preferredColorScheme(colorScheme) }
    }
}
@MainActor
final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
