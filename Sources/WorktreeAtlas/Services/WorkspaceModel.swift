import Foundation
import Combine
import AtlasCore

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var repositories: [RepositoryRecord] = []
    @Published var snapshots: [UUID: RepositorySnapshot] = [:]
    @Published var failures: [UUID: String] = [:]
    @Published var refreshing = false
    @Published var busy = false
    @Published var message: String?
    @Published var isDemo = false
    @Published var paused = false
    private let store = RepositoryStore()
    private var persistenceAvailable = true
    private var generation = 0
    private var refreshTask: Task<Void, Never>?
    private let scanner = RepositoryScanner()

    init(demo: Bool = CommandLine.arguments.contains("--demo")) {
        if demo {
            isDemo = true
            let items = DemoWorkspace.snapshots
            repositories = items.map(\.record)
            snapshots = Dictionary(uniqueKeysWithValues: items.map { ($0.record.id, $0) })
            return
        }
        do { repositories = try store.load() }
        catch {
            persistenceAvailable = false
            message = "仓库配置无法读取，已停止自动保存以防覆盖。请检查 \(store.url.path)。\n\(error.localizedDescription)"
        }
    }
    var allWorktrees: [GitWorktree] { snapshots.values.flatMap(\.worktrees).filter { !$0.isBare } }
    var dirtyCount: Int { allWorktrees.filter { $0.statusKnown && $0.dirtyCount > 0 }.count }
    var unknownCount: Int { allWorktrees.filter { !$0.statusKnown }.count }
    func showDemo() {
        guard !busy else { return }
        refreshTask?.cancel(); generation += 1; refreshing = false
        isDemo = true; failures = [:]
        let items = DemoWorkspace.snapshots
        repositories = items.map(\.record)
        snapshots = Dictionary(uniqueKeysWithValues: items.map { ($0.record.id, $0) })
    }
    func leaveDemo() {
        guard !busy else { return }
        generation += 1; isDemo = false; snapshots = [:]; failures = [:]
        do { repositories = try store.load() } catch { repositories = []; message = error.localizedDescription }
        refreshAll()
    }
    func add(paths: [String]) {
        guard !busy else { return }
        if isDemo { leaveDemo() }
        refreshTask?.cancel(); generation += 1; refreshing = false
        busy = true
        Task {
            defer { busy = false }
            for path in paths {
                do {
                    var snapshot = try await scanner.scan(path: path)
                    if let index = repositories.firstIndex(where: {
                        $0.commonDirectory == snapshot.record.commonDirectory || $0.rootPath == path
                    }) {
                        let existing = repositories[index]
                        if let prior = existing.commonDirectoryIdentity,
                           prior != snapshot.record.commonDirectoryIdentity || existing.commonDirectory != snapshot.record.commonDirectory {
                            let error = "仓库目录身份已变化；旧卡片已过期。请先移除旧记录，再添加当前仓库。"
                            failures[existing.id] = error; message = error
                            continue
                        }
                        // Re-adding explicitly rebinds member paths that changed inode;
                        // refreshing a card never grants that trust silently.
                        snapshot.record.id = existing.id; snapshot.record.displayName = existing.displayName
                        repositories[index] = snapshot.record; snapshots[existing.id] = snapshot; failures[existing.id] = nil
                    } else {
                        repositories.append(snapshot.record); snapshots[snapshot.record.id] = snapshot
                    }
                } catch { message = error.localizedDescription }
            }
            save()
        }
    }
    func forget(_ id: UUID) {
        guard !busy else { return }
        repositories.removeAll { $0.id == id }; snapshots[id] = nil; failures[id] = nil
        if !isDemo { save() }
    }
    func rename(_ id: UUID, name: String) {
        guard let i = repositories.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        repositories[i].displayName = name
        snapshots[id]?.record.displayName = name
        if !isDemo { save() }
    }
    func refreshAll() {
        guard !isDemo && !refreshing && !busy else { return }
        let epoch = generation
        let records = repositories
        let scanner = self.scanner
        refreshing = true
        refreshTask = Task {
            defer { if epoch == generation { refreshing = false } }
            // At most two simultaneous repository scans; subprocess work never blocks the main actor.
            await withTaskGroup(of: ScanResult.self) { group in
                var iterator = records.makeIterator()
                func add(_ record: RepositoryRecord) {
                    group.addTask {
                        do { return .success(record, try await scanner.scanRegistered(record)) }
                        catch { return .failure(record.id, error.localizedDescription) }
                    }
                }
                for _ in 0..<2 { if let record = iterator.next() { add(record) } }
                while let result = await group.next() {
                    if epoch != generation || Task.isCancelled { group.cancelAll(); return }
                    switch result {
                    case .success(let previous, var snapshot):
                        if let i = repositories.firstIndex(where: { $0.id == previous.id }) {
                            snapshot.record.displayName = repositories[i].displayName
                            repositories[i] = snapshot.record; snapshots[previous.id] = snapshot; failures[previous.id] = nil
                        }
                    case .failure(let id, let error):
                        if repositories.contains(where: { $0.id == id }) { failures[id] = error }
                    }
                    if let record = iterator.next() { add(record) }
                }
            }
            if epoch == generation && !Task.isCancelled { save() }
        }
    }
    /// One UI mutation at a time. Neither demo mode nor stale snapshots may start mutations.
    func perform(repository: UUID, action: @escaping @Sendable (String) async throws -> Void) {
        guard !isDemo, !busy, failures[repository] == nil,
              let record = repositories.first(where: { $0.id == repository }) else { return }
        refreshTask?.cancel(); generation += 1; refreshing = false; busy = true
        Task {
            do { try await scanner.verifyRegisteredIdentity(record) }
            catch {
                failures[repository] = error.localizedDescription
                message = error.localizedDescription
                busy = false; refreshAll()
                return
            }
            do { try await action(record.rootPath) }
            catch { message = error.localizedDescription }
            busy = false; refreshAll()
        }
    }
    private func save() {
        guard persistenceAvailable && !isDemo else { return }
        do { try store.save(repositories) } catch { message = "保存失败：\(error.localizedDescription)" }
    }
}
private enum ScanResult: Sendable {
    case success(RepositoryRecord, RepositorySnapshot)
    case failure(UUID, String)
}
