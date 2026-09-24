import SwiftUI
import AtlasCore

private struct WorktreeSelection: Equatable {
    var repositoryID: UUID
    var path: String
}
private struct CreateRequest: Identifiable { let id = UUID(); let snapshot: RepositorySnapshot }
private struct PruneRequest: Identifiable { let id = UUID(); let repositoryID: UUID; let preview: String }
private struct ConfirmationRequest: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let destructive: Bool
    let action: () -> Void
}

struct DashboardView: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("refreshInterval") private var refreshInterval = 10.0
    @State private var selectedRepository: UUID?
    @State private var selection: WorktreeSelection?
    @State private var search = ""
    @State private var createRequest: CreateRequest?
    @State private var pruneRequest: PruneRequest?
    @State private var confirmation: ConfirmationRequest?
    @State private var attentionOnly = false
    private var visibleRecords: [RepositoryRecord] {
        model.repositories.filter { record in
            let scope = selectedRepository == nil || selectedRepository == record.id
            let snapshot = model.snapshots[record.id]
            let textMatch = search.isEmpty || record.displayName.localizedCaseInsensitiveContains(search) ||
                record.rootPath.localizedCaseInsensitiveContains(search) ||
                snapshot?.worktrees.contains(where: { $0.title.localizedCaseInsensitiveContains(search) }) == true
            let attention = !attentionOnly || model.failures[record.id] != nil || snapshot?.worktrees.contains(where: \.needsAttention) == true
            return scope && textMatch && attention
        }
    }
    private var inspected: (RepositorySnapshot, GitWorktree)? {
        guard let selection, let snapshot = model.snapshots[selection.repositoryID],
              let worktree = snapshot.worktrees.first(where: { $0.path == selection.path }) else { return nil }
        return (snapshot, worktree)
    }
    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 270)
        } detail: {
            HStack(spacing: 0) {
                GeometryReader { geometry in
                    content(columnCount: selectedRepository == nil && geometry.size.width > 1050 ? 2 : 1)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let (snapshot, worktree) = inspected {
                    Divider()
                    WorktreeInspector(worktree: worktree, repository: snapshot.record,
                        canMutate: canMutate(snapshot.record.id), onClose: { selection = nil },
                        onRemove: { requestRemoval(snapshot, worktree) },
                        onToggleLock: { toggleLock(snapshot, worktree) }, onError: { model.message = $0 })
                }
            }
        }
        .navigationTitle("Worktree Atlas")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.busy || model.refreshing { ProgressView().controlSize(.small) }
                Button { model.refreshAll() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(model.isDemo || model.busy || model.refreshing).keyboardShortcut("r")
                Button { model.add(paths: DesktopActions.chooseRepositories()) } label: { Label("添加仓库", systemImage: "plus") }
                    .disabled(model.busy).keyboardShortcut("o")
            }
        }
        .sheet(item: $createRequest) { request in
            CreateWorktreeSheet(snapshot: request.snapshot) { path, branch, base, mode in
                model.perform(repository: request.snapshot.record.id) { repo in
                    try await WorktreeOperator().create(repository: repo, path: path, branch: branch, base: base, mode: mode)
                }
            }
        }
        .sheet(item: $pruneRequest) { request in
            VStack(alignment: .leading, spacing: 18) {
                Text("清理失效的工作树记录").font(.title2.bold())
                Text("外接磁盘或网络盘未挂载也可能显示为失效。请确认这些工作树确实不再需要；仍要保留的离线工作树应先锁定。")
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView { Text(request.preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: 150)
                HStack {
                    Spacer()
                    Button("取消") { pruneRequest = nil }.keyboardShortcut(.cancelAction)
                    Button("确认清理记录", role: .destructive) {
                        model.perform(repository: request.repositoryID) { repo in
                            try await WorktreeOperator().prune(repository: repo, expectedPreview: request.preview)
                        }
                        pruneRequest = nil
                    }.disabled(model.busy)
                }
            }.padding(28).frame(width: 560)
        }
        .sheet(item: $confirmation) { request in
            VStack(alignment: .leading, spacing: 18) {
                Text(request.title).font(.title2.bold())
                Text(request.detail).font(.callout).textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("取消") { confirmation = nil }.keyboardShortcut(.cancelAction)
                    Button(request.destructive ? "确认移除" : "确认") { request.action(); confirmation = nil }
                        .buttonStyle(.borderedProminent).tint(request.destructive ? .red : .teal)
                }
            }.padding(28).frame(width: 510)
        }
        .alert("Worktree Atlas", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("确定") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .task {
            model.refreshAll()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(max(3, refreshInterval))) } catch { return }
                if scenePhase == .active && !model.paused { model.refreshAll() }
            }
        }
        .onChange(of: scenePhase) { _, value in if value == .active { model.refreshAll() } }
        .onChange(of: model.isDemo) { _, _ in selectedRepository = nil; selection = nil }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedRepository) {
                Button { selectedRepository = nil } label: {
                    Label("全部仓库", systemImage: "square.grid.2x2").foregroundStyle(selectedRepository == nil ? Color.teal : Color.primary)
                }.buttonStyle(.plain).padding(.vertical, 6)
                Section("仓库") {
                    ForEach(model.repositories) { record in
                        Label(record.displayName, systemImage: "shippingbox").tag(record.id)
                            .contextMenu {
                                Button("从总览移除（不删除文件）") { model.forget(record.id); if selectedRepository == record.id { selectedRepository = nil } }
                            }
                    }
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Circle().fill(model.isDemo ? Color.indigo : .teal).frame(width: 6, height: 6)
                    Text(model.isDemo ? "演示数据 · 禁用写操作" : model.paused ? "自动刷新已暂停" : "本地优先 · 自动刷新")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if model.isDemo { Button("返回真实仓库") { model.leaveDemo() }.font(.caption) }
                else { Toggle("暂停自动刷新", isOn: $model.paused).toggleStyle(.checkbox).font(.caption) }
                HStack {
                    SettingsLink { Image(systemName: "gearshape") }
                    Spacer()
                    Text("0.1.0-dev").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }.buttonStyle(.borderless)
            }.padding(16)
        }
    }
    private func content(columnCount: Int) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    header
                    if model.repositories.isEmpty {
                        ContentUnavailableView {
                            Label("把工作树放回图里", systemImage: "point.3.connected.trianglepath.dotted")
                        } description: {
                            Text("添加已有仓库。Atlas 自动发现其工作树，并在真实提交图中标出它们的位置。")
                        } actions: {
                            Button("添加仓库") { model.add(paths: DesktopActions.chooseRepositories()) }.buttonStyle(.borderedProminent).tint(.teal)
                            Button("查看交互演示") { model.showDemo() }.buttonStyle(.borderless)
                        }.frame(minHeight: 320)
                    } else if visibleRecords.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 250), spacing: 20), count: columnCount), spacing: 20) {
                            ForEach(visibleRecords) { record in
                                if let snapshot = model.snapshots[record.id] {
                                    RepositoryCardView(snapshot: snapshot, error: model.failures[record.id], focused: selectedRepository != nil,
                                        selectedPath: selection?.repositoryID == record.id ? selection?.path : nil,
                                        canMutate: canMutate(record.id),
                                        onSelect: { selection = WorktreeSelection(repositoryID: record.id, path: $0.path) },
                                        onFocus: { selectedRepository = record.id },
                                        onCreate: { createRequest = CreateRequest(snapshot: snapshot) },
                                        onPrune: { requestPrune(record.id) })
                                } else {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(record.displayName).font(.headline)
                                        if let error = model.failures[record.id] { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                                        else { ProgressView("正在读取工作树…").controlSize(.small) }
                                    }.frame(maxWidth: .infinity, minHeight: 170, alignment: .leading).padding(20)
                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                                }
                            }
                        }
                    }
                }.padding(26)
            }
            Divider()
            HStack(spacing: 18) {
                Text("\(model.repositories.count) 个仓库")
                Text("\(model.allWorktrees.count) 个工作树")
                if model.unknownCount > 0 { Text("\(model.unknownCount) 个状态未知").foregroundStyle(.orange) }
                Spacer()
                Text("不执行 commit / push / merge / rebase").foregroundStyle(.secondary)
            }.font(.system(size: 10)).padding(.horizontal, 24).padding(.vertical, 10)
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.isDemo ? "DEMO WORKSPACE" : "YOUR WORK, IN CONTEXT")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(.teal)
                    Text(selectedRepository == nil ? "所有工作树，一眼看清。" : model.repositories.first(where: { $0.id == selectedRepository })?.displayName ?? "仓库")
                        .font(.system(size: 28, weight: .semibold))
                    Text("看见分叉、当前位置和待处理状态。不接管你的开发工具。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                if selectedRepository != nil { Button("返回全部") { selectedRepository = nil; selection = nil }.controlSize(.small) }
            }
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索仓库、路径或工作树分支", text: $search).textFieldStyle(.plain)
                }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9)).frame(maxWidth: 350)
                Toggle("仅待处理", isOn: $attentionOnly).toggleStyle(.button).controlSize(.small)
                Spacer()
                if model.isDemo { MetadataPill(text: "DEMO · 非真实仓库", color: .indigo) }
            }
        }
    }
    private func canMutate(_ id: UUID) -> Bool { !model.isDemo && !model.busy && model.failures[id] == nil }
    private func requestRemoval(_ snapshot: RepositorySnapshot, _ worktree: GitWorktree) {
        confirmation = ConfirmationRequest(title: "移除这个工作树？", detail: "将删除工作目录：\n\(worktree.path)\n\n保留分支；游离 HEAD 必须由本地分支或标签保留。请先停止在此目录写文件的程序；状态检查与删除无法做到原子化。操作前会重新检查文件状态，不使用强制删除。", destructive: true) {
            model.perform(repository: snapshot.record.id) { repo in
                try await WorktreeOperator().remove(repository: repo, path: worktree.path,
                                                    expectedIdentity: worktree.directoryIdentity)
            }
        }
    }
    private func toggleLock(_ snapshot: RepositorySnapshot, _ worktree: GitWorktree) {
        let perform = {
            model.perform(repository: snapshot.record.id) { repo in
                try await WorktreeOperator().setLocked(repository: repo, path: worktree.path,
                                                       locked: !worktree.isLocked,
                                                       expectedIdentity: worktree.directoryIdentity)
            }
        }
        if worktree.isLocked {
            confirmation = ConfirmationRequest(title: "解除工作树保护？", detail: "解锁后，此工作树可被 Git 移除或清理。\n\(worktree.path)", destructive: false, action: perform)
        } else { perform() }
    }
    private func requestPrune(_ id: UUID) {
        guard canMutate(id), let record = model.repositories.first(where: { $0.id == id }) else { return }
        Task {
            do {
                let preview = try await WorktreeOperator().prunePreview(repository: record.rootPath)
                if preview.isEmpty { model.message = "没有需要清理的失效工作树记录。" }
                else { pruneRequest = PruneRequest(repositoryID: id, preview: preview) }
            } catch { model.message = error.localizedDescription }
        }
    }
}
