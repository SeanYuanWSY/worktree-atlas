import SwiftUI
import AtlasCore

struct CreateWorktreeSheet: View {
    let snapshot: RepositorySnapshot
    let onCreate: (String, String, String, WorktreeCreationMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: WorktreeCreationMode = .newBranch
    @State private var branch = ""
    @State private var base = ""
    @State private var parent = ""
    @State private var folder = ""
    @State private var trusted = false
    private var target: String { URL(fileURLWithPath: parent).appendingPathComponent(folder).path }
    private var valid: Bool {
        !parent.isEmpty && !folder.isEmpty && !folder.contains("/") && folder != "." && folder != ".." &&
        (mode == .detached || !branch.isEmpty) && (mode == .existingBranch || !base.isEmpty) && trusted
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 27)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("新建工作树").font(.title2.bold())
                    Text(snapshot.record.displayName).foregroundStyle(.secondary)
                }
            }
            Picker("模式", selection: $mode) {
                Text("新分支").tag(WorktreeCreationMode.newBranch)
                Text("已有分支").tag(WorktreeCreationMode.existingBranch)
                Text("游离 HEAD").tag(WorktreeCreationMode.detached)
            }.pickerStyle(.segmented)
            Form {
                if mode == .existingBranch {
                    Picker("分支", selection: $branch) {
                        Text("选择分支").tag("")
                        ForEach(snapshot.branches.filter { !$0.isRemote }) { Text($0.branchName).tag($0.branchName) }
                    }
                } else if mode == .newBranch {
                    TextField("分支名称", text: $branch, prompt: Text("feature/my-task"))
                }
                if mode != .existingBranch { TextField("起点分支 / 提交", text: $base) }
                HStack {
                    TextField("父目录", text: $parent)
                    Button("选择…") { if let result = DesktopActions.chooseParent() { parent = result } }
                }
                TextField("文件夹名称", text: $folder, prompt: Text("my-task"))
            }.textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("将创建于").font(.caption).foregroundStyle(.secondary)
                Text(parent.isEmpty || folder.isEmpty ? "请选择目录" : target)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("不会覆盖现有目录，不会自动安装依赖或启动终端。").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("我信任此仓库：检出文件可能运行 Git 配置中的过滤器。", isOn: $trusted).font(.caption)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("创建工作树") { onCreate(target, branch, base, mode); dismiss() }
                    .buttonStyle(.borderedProminent).tint(.teal).disabled(!valid).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 570)
        .onAppear {
            base = snapshot.record.defaultBranch ?? "HEAD"
            parent = URL(fileURLWithPath: snapshot.record.rootPath).deletingLastPathComponent().path
        }
        .onChange(of: branch) { previous, value in
            let previousSuggestion = previous.replacingOccurrences(of: "/", with: "-")
            if folder.isEmpty || folder == previousSuggestion {
                folder = value.replacingOccurrences(of: "/", with: "-")
            }
        }
    }
}
