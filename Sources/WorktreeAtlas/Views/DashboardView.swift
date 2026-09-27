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
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("refreshInterval") private var refreshInterval = 10.0
    @State private var selectedRepository: UUID?
    @State private var selection: WorktreeSelection?
    @State private var search = ""
    @State private var createRequest: CreateRequest?
    @State private var pruneRequest: PruneRequest?
    @State private var confirmation: ConfirmationRequest?
    @State private var attentionOnly = false
    @State private var sidebarVisible = true
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
        HStack(spacing: 0) {
            activityRail
            Divider()
            if sidebarVisible {
                sidebar.frame(width: 174)
                Divider()
            }
            HStack(spacing: 0) {
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
                if let (snapshot, worktree) = inspected {
                    Divider()
                    WorktreeInspector(worktree: worktree, repository: snapshot.record,
                        canMutate: canMutate(snapshot.record.id), onClose: { selection = nil },
                        onRemove: { requestRemoval(snapshot, worktree) },
                        onToggleLock: { toggleLock(snapshot, worktree) }, onError: { model.message = $0 })
                }
            }
            .background(AtlasStyle.background(colorScheme))
        }
        .font(.system(size: 11))
        .background(AtlasStyle.background(colorScheme))
        .navigationTitle("Worktree Atlas")
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
    private var activityRail: some View {
        VStack(spacing: 0) {
            Button { sidebarVisible.toggle() } label: {
                Image(systemName: "sidebar.left").frame(width: 38, height: 42)
            }.help("显示或隐藏工作区")
            Button { selectedRepository = nil; selection = nil } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(AtlasStyle.accent).frame(width: 38, height: 42)
                    .overlay(alignment: .leading) { Rectangle().fill(AtlasStyle.accent).frame(width: 2, height: 24) }
            }.help("全部仓库提交图")
            Button { model.add(paths: DesktopActions.chooseRepositories()) } label: {
                Image(systemName: "folder.badge.plus").frame(width: 38, height: 42)
            }.disabled(model.busy).help("添加仓库")
            Spacer()
            SettingsLink { Image(systemName: "gearshape").frame(width: 38, height: 38) }
        }
        .font(.system(size: 17, weight: .light)).foregroundStyle(.secondary)
        .buttonStyle(.plain).frame(width: 38)
        .background(AtlasStyle.background(colorScheme))
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("工作区").font(.system(size: 10, weight: .medium))
                Spacer()
                Button { model.add(paths: DesktopActions.chooseRepositories()) } label: { Image(systemName: "plus") }
                    .disabled(model.busy).help("添加仓库")
            }.padding(.horizontal, 12).frame(height: 31)
            Button { selectedRepository = nil; selection = nil } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down").font(.system(size: 8))
                    Text("仓库").fontWeight(.semibold)
                    Spacer()
                    Text("\(model.repositories.count)").foregroundStyle(.secondary)
                }.padding(.horizontal, 10).frame(height: 25)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.repositories) { record in
                        Button { selectedRepository = record.id; selection = nil } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
                                Image(systemName: "folder").foregroundStyle(selectedRepository == record.id ? AtlasStyle.accent : .secondary)
                                Text(record.displayName).lineLimit(1)
                                Spacer(minLength: 2)
                                if model.failures[record.id] != nil {
                                    Circle().fill(.orange).frame(width: 4, height: 4)
                                }
                            }
                            .padding(.leading, 15).padding(.trailing, 10).frame(height: 25)
                            .background(selectedRepository == record.id ? AtlasStyle.selection(colorScheme) : .clear)
                        }
                        .help(record.rootPath)
                        .contextMenu {
                            Button("从总览移除（不删除文件）") {
                                model.forget(record.id)
                                if selectedRepository == record.id { selectedRepository = nil }
                            }
                        }
                    }
                }
            }
            Divider()
            HStack(spacing: 5) {
                Circle().fill(model.isDemo ? Color.purple : AtlasStyle.accent).frame(width: 5, height: 5)
                Text(model.isDemo ? "演示工作区" : "本地工作区").foregroundStyle(.secondary)
                Spacer()
                if model.isDemo {
                    Button { model.leaveDemo() } label: { Image(systemName: "arrow.uturn.backward") }.help("返回真实仓库")
                } else {
                    Button { model.paused.toggle() } label: { Image(systemName: model.paused ? "play" : "pause") }
                        .help(model.paused ? "恢复自动刷新" : "暂停自动刷新")
                }
            }.font(.system(size: 10)).padding(.horizontal, 10).frame(height: 26)
        }
        .buttonStyle(.plain).background(AtlasStyle.background(colorScheme))
    }
    private func content() -> some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.repositories.isEmpty {
                        ContentUnavailableView {
                            Label("把工作树放回图里", systemImage: "point.3.connected.trianglepath.dotted")
                        } description: {
                            Text("添加已有仓库。Atlas 自动发现其工作树，并在真实提交图中标出它们的位置。")
                        } actions: {
                            Button("添加仓库") { model.add(paths: DesktopActions.chooseRepositories()) }.buttonStyle(.borderedProminent).tint(AtlasStyle.accent)
                            Button("查看交互演示") { model.showDemo() }.buttonStyle(.borderless)
                        }.frame(minHeight: 320)
                    } else if visibleRecords.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        LazyVStack(spacing: 0) {
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
                                        .background(AtlasStyle.card(colorScheme), in: RoundedRectangle(cornerRadius: 18))
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            HStack(spacing: 18) {
                Text("\(model.repositories.count) 个仓库")
                Text("\(model.allWorktrees.count) 个工作树")
                if model.unknownCount > 0 { Text("\(model.unknownCount) 个状态未知").foregroundStyle(.orange) }
                Spacer()
                Text(model.isDemo ? "演示 · 只读" : model.paused ? "刷新已暂停" : "本地 Git").foregroundStyle(.secondary)
            }.font(.system(size: 10)).padding(.horizontal, 12).frame(height: 23)
        }
    }
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                    Text("提交图")
                }
                .padding(.horizontal, 12).frame(height: 30)
                .overlay(alignment: .top) { Rectangle().fill(AtlasStyle.accent).frame(height: 1) }
                .background(AtlasStyle.card(colorScheme))
                Spacer()
                if model.refreshing || model.busy { ProgressView().controlSize(.mini).padding(.trailing, 9) }
                Button { model.refreshAll() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.isDemo || model.busy || model.refreshing).help("刷新全部仓库")
                Button { model.add(paths: DesktopActions.chooseRepositories()) } label: { Image(systemName: "plus") }
                    .disabled(model.busy).help("添加仓库").padding(.horizontal, 12)
            }
            .background(AtlasStyle.chrome(colorScheme))
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
                Menu {
                    Button("全部仓库") { selectedRepository = nil; selection = nil }
                    Divider()
                    ForEach(model.repositories) { record in
                        Button(record.displayName) { selectedRepository = record.id; selection = nil }
                    }
                } label: {
                    Text(selectedRepository.flatMap { id in model.repositories.first(where: { $0.id == id })?.displayName } ?? "全部仓库")
                }.menuStyle(.borderlessButton).fixedSize()
                Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(width: 1, height: 12)
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索仓库、路径或工作树分支", text: $search).textFieldStyle(.plain)
                Toggle(isOn: $attentionOnly) { Image(systemName: "line.3.horizontal.decrease") }
                    .toggleStyle(.button).controlSize(.mini).help("仅显示待处理仓库")
            }
            .padding(.horizontal, 10).frame(height: 30)
            Divider()
        }
        .font(.system(size: 11)).buttonStyle(.plain)
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
