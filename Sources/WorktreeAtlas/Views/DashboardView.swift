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
    @AppStorage("appearance") private var appearance = "system"
    @FocusState private var searchFocused: Bool
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
                snapshot?.worktrees.contains(where: {
                    $0.title.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search)
                }) == true
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
                WorkspaceSidebarView(records: model.repositories, failures: model.failures, selectedRepository: selectedRepository,
                    isDemo: model.isDemo, paused: model.paused, busy: model.busy,
                    onSelect: { selectedRepository = $0; selection = nil },
                    onAdd: { model.add(paths: DesktopActions.chooseRepositories()) },
                    onForget: { id in
                        model.forget(id)
                        if selectedRepository == id { selectedRepository = nil }
                        if selection?.repositoryID == id { selection = nil }
                    }, onPause: { model.paused.toggle() }, onLeaveDemo: { model.leaveDemo() })
                    .frame(width: 186)
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
        .onExitCommand(perform: handleExitCommand)
    }
    private var activityRail: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 20, weight: .medium)).foregroundStyle(AtlasStyle.accent)
                .frame(width: 34, height: 34)
                .background(AtlasStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AtlasStyle.accent.opacity(0.25)))
                .padding(.top, 18).padding(.bottom, 12)
            Button { sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("显示或隐藏工作区")
            Button { selectedRepository = nil; selection = nil } label: { Image(systemName: "rectangle.split.2x1") }
                .help("全部仓库并排总览")
            Button { model.add(paths: DesktopActions.chooseRepositories()) } label: { Image(systemName: "folder.badge.plus") }
                .disabled(model.busy).help("添加仓库")
            Spacer()
            Button { appearance = colorScheme == .dark ? "light" : "dark" } label: {
                Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
            }.help("切换浅色 / 深色")
            SettingsLink { Image(systemName: "slider.horizontal.3") }.help("显示与刷新设置")
                .padding(.bottom, 14)
        }
        .buttonStyle(AtlasToolbarButtonStyle()).frame(width: 52)
        .background(AtlasStyle.chrome(colorScheme))
    }
    private func content() -> some View {
        VStack(spacing: 0) {
            header
            if model.repositories.isEmpty {
                ContentUnavailableView {
                    Label("把工作树放回图里", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("添加已有仓库。Atlas 自动发现工作树，并在真实提交图中标出它们的位置。")
                } actions: {
                    Button("添加仓库") { model.add(paths: DesktopActions.chooseRepositories()) }.buttonStyle(.borderedProminent).tint(AtlasStyle.accent)
                    Button("查看交互演示") { model.showDemo() }.buttonStyle(.borderless)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleRecords.isEmpty {
                ContentUnavailableView.search(text: search).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RepositoryBoardView(records: visibleRecords, snapshots: model.snapshots, presentations: model.presentations,
                    failures: model.failures, focused: selectedRepository != nil,
                    selectedRepositoryID: selection?.repositoryID, selectedPath: selection?.path,
                    canMutate: canMutate,
                    onSelect: { id, worktree in
                        searchFocused = false
                        selection = WorktreeSelection(repositoryID: id, path: worktree.path)
                    },
                    onFocus: { id in
                        selectedRepository = id
                        if selection?.repositoryID != id { selection = nil }
                    }, onCreate: { createRequest = CreateRequest(snapshot: $0) },
                    onPrune: requestPrune)
            }
            Rectangle().fill(AtlasStyle.divider(colorScheme)).frame(height: 1)
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle().fill(model.isDemo ? AtlasStyle.violet : AtlasStyle.accent).frame(width: 4, height: 4)
                    Text(model.isDemo ? "演示 · 只读" : model.paused ? "刷新已暂停" : "本地 Git")
                }
                Text("\(model.repositories.count) 个仓库 · \(model.allWorktrees.count) 个工作树").foregroundStyle(.secondary)
                if model.unknownCount > 0 { Text("\(model.unknownCount) 个状态未知").foregroundStyle(.orange) }
                Spacer()
                Text("Worktree Atlas").fontDesign(.monospaced).foregroundStyle(.tertiary)
            }.font(.system(size: 10)).padding(.horizontal, 16).frame(height: 28)
                .background(AtlasStyle.chrome(colorScheme))
        }
    }
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedRepository == nil ? "工作树总览" : "仓库提交图").font(.system(size: 14, weight: .semibold))
                Menu {
                    Button("全部仓库") { selectedRepository = nil; selection = nil }
                    Divider()
                    ForEach(model.repositories) { record in
                        Button(record.displayName) { selectedRepository = record.id; selection = nil }
                    }
                } label: {
                    Text(selectedRepository.flatMap { id in model.repositories.first(where: { $0.id == id })?.displayName } ?? "所有仓库")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.menuStyle(.borderlessButton).fixedSize()
            }
            Spacer(minLength: 10)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索仓库、分支或路径", text: $search).textFieldStyle(.plain).focused($searchFocused)
                    .onExitCommand(perform: handleExitCommand)
                if !search.isEmpty {
                    Button { search = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("清空搜索")
                } else { Text("⌘F").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary) }
            }
            .font(.system(size: 11)).padding(.horizontal, 10).frame(minWidth: 160, idealWidth: 270, maxWidth: 340).frame(height: 32)
            .background(AtlasStyle.worktreeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(searchFocused ? AtlasStyle.accent.opacity(0.55) : AtlasStyle.divider(colorScheme)))
            Button { attentionOnly.toggle() } label: {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(attentionOnly ? AtlasStyle.accent : .secondary)
            }.help(attentionOnly ? "显示全部仓库" : "仅显示待处理仓库")
            ZStack {
                if model.refreshing || model.busy { ProgressView().controlSize(.mini) }
                else { Button { model.refreshAll() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.isDemo).help("刷新全部仓库") }
            }.frame(width: 28, height: 28)
            Button { model.add(paths: DesktopActions.chooseRepositories()) } label: { Image(systemName: "plus") }
                .disabled(model.busy).help("添加仓库")
            Button("搜索") { searchFocused = true }.keyboardShortcut("f").hidden().frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .buttonStyle(AtlasToolbarButtonStyle()).padding(.horizontal, 18).frame(height: 76)
        .background(AtlasStyle.background(colorScheme))
    }
    private func handleExitCommand() {
        if searchFocused && !search.isEmpty { search = "" }
        else { searchFocused = false; selection = nil }
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
