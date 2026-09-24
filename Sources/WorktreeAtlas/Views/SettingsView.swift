import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var interval = 10.0
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Form {
            Section("显示") {
                Picker("外观", selection: $appearance) {
                    Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                }
            }
            Section("刷新") {
                Picker("自动刷新间隔", selection: $interval) {
                    Text("5 秒").tag(5.0); Text("10 秒").tag(10.0); Text("30 秒").tag(30.0); Text("60 秒").tag(60.0)
                }
                Text("窗口在前台时轮询本地 Git。不会访问远端、收集遥测或启动 AI 代理。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("安全边界") {
                Text("移除操作保留分支，并拒绝有修改、未跟踪文件、被忽略文件或未知状态的工作树。锁定的工作树需先明确解锁。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("来源") {
                Text("Worktree Atlas 0.1.0-dev · Based on GitScope (MIT)").font(.caption)
                Text("本地开发版；此应用包尚未经过 Apple 公证。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(10).frame(width: 490, height: 430)
    }
}
