// Scanner architecture follows GitScope; protocol parsing and bounded history are rewritten for Atlas.
import Foundation

public struct RepositoryScanner: Sendable {
    public let runner: any GitCommandRunning
    public var historyLimit: Int
    public init(runner: any GitCommandRunning = GitCommandRunner(), historyLimit: Int = 1200) {
        self.runner = runner; self.historyLimit = max(20, min(historyLimit, 10000))
    }
    public func listWorktrees(at path: String) async throws -> [GitWorktree] {
        try GitParser.worktrees(await runner.run(["worktree", "list", "--porcelain", "-z"], at: path))
    }
    public func scan(path: String) async throws -> RepositorySnapshot {
        try await scan(path: path, existingID: nil, expected: nil)
    }
    /// Refresh only a previously bound repository. A known path keeps its old
    /// directory identity even when the on-disk directory has been replaced.
    public func scanRegistered(_ record: RepositoryRecord) async throws -> RepositorySnapshot {
        let expected = try registeredIdentity(record)
        var snapshot = try await scan(path: record.rootPath, existingID: record.id, expected: expected)
        var bindings = record.memberDirectoryIdentities ?? [:]
        for index in snapshot.worktrees.indices where !snapshot.worktrees[index].isBare {
            let path = snapshot.worktrees[index].path
            if let prior = bindings[path] {
                if snapshot.worktrees[index].directoryIdentity != prior {
                    snapshot.worktrees[index].directoryIdentity = nil
                    snapshot.worktrees[index].statusKnown = false
                    snapshot.worktrees[index].statusError = "工作树目录身份已变化；旧绑定已保留。请重新添加仓库以确认当前目录。"
                    snapshot.warnings.append("工作树目录已变化：\(path)")
                }
            } else if let current = snapshot.worktrees[index].directoryIdentity {
                bindings[path] = current
            }
        }
        snapshot.record.memberDirectoryIdentities = bindings
        return snapshot
    }
    /// A single read-only Git command and filesystem lookup before every UI mutation.
    public func verifyRegisteredIdentity(_ record: RepositoryRecord) async throws {
        let expected = try registeredIdentity(record)
        if record.rootPath != expected.path {
            guard let boundRoot = record.memberDirectoryIdentities?[record.rootPath],
                  try WorktreePathIdentity.at(record.rootPath) == boundRoot else {
                throw WorktreeSafetyError("仓库入口工作树目录身份已变化，已禁用写操作。请重新添加仓库。")
            }
        }
        let current = try await commonDirectory(at: record.rootPath)
        guard current.path == expected.path && current.identity == expected.identity else {
            throw WorktreeSafetyError("仓库目录身份已变化；旧卡片已过期。请移除旧记录后重新添加仓库。")
        }
    }
    private func registeredIdentity(_ record: RepositoryRecord) throws -> (path: String, identity: RepositoryDirectoryIdentity) {
        guard !record.commonDirectory.isEmpty, let identity = record.commonDirectoryIdentity,
              record.memberDirectoryIdentities != nil else {
            throw WorktreeSafetyError("此仓库记录尚未验证目录或工作树身份，已禁用写操作。请重新添加该仓库。")
        }
        return (record.commonDirectory, identity)
    }
    private func commonDirectory(at path: String) async throws -> (path: String, identity: RepositoryDirectoryIdentity) {
        let common = GitParser.trimLineEnding(try await runner.run(
            ["rev-parse", "--path-format=absolute", "--git-common-dir"], at: path))
        let canonical = try WorktreePathIdentity.canonicalPath(common)
        let attributes = try FileManager.default.attributesOfItem(atPath: canonical)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw WorktreeSafetyError("无法核验仓库目录的文件系统身份，已禁用写操作。")
        }
        return (canonical, RepositoryDirectoryIdentity(device: device.uint64Value, inode: inode.uint64Value))
    }
    private func scan(path: String, existingID: UUID?,
                      expected: (path: String, identity: RepositoryDirectoryIdentity)?) async throws -> RepositorySnapshot {
        try Task.checkCancellation()
        let initial = try await commonDirectory(at: path)
        if let expected, initial.path != expected.path || initial.identity != expected.identity {
            throw WorktreeSafetyError("仓库目录身份已变化；旧卡片已过期。请移除旧记录后重新添加仓库。")
        }
        var worktrees = try await listWorktrees(at: path)
        let root = worktrees.first(where: { $0.isMain })?.path ?? worktrees.first?.path ?? path
        // Keep the registered access path if the main checkout is temporarily unavailable.
        let accessPath = FileManager.default.fileExists(atPath: root) ? root : path
        var warnings: [String] = []
        for index in worktrees.indices {
            try Task.checkCancellation()
            if worktrees[index].isBare { continue }
            let memberPath = worktrees[index].path
            let memberIdentity: RepositoryDirectoryIdentity
            do {
                memberIdentity = try WorktreePathIdentity.at(memberPath)
                let memberCommon = try await commonDirectory(at: memberPath)
                guard memberCommon.path == initial.path && memberCommon.identity == initial.identity else {
                    throw WorktreeSafetyError("工作树已不属于此仓库，已禁用写操作。")
                }
            } catch {
                worktrees[index].statusError = error.localizedDescription
                continue
            }
            do {
                let status = try GitParser.status(await runner.run(
                    ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all", "--ignore-submodules=none"],
                    at: memberPath))
                guard try WorktreePathIdentity.at(memberPath) == memberIdentity else {
                    throw WorktreeSafetyError("扫描期间工作树目录身份发生变化，已禁用写操作。")
                }
                worktrees[index].dirtyCount = status.dirtyCount
                worktrees[index].aheadCount = status.ahead; worktrees[index].behindCount = status.behind
                worktrees[index].hasUpstream = status.hasUpstream; worktrees[index].statusKnown = true
                worktrees[index].directoryIdentity = memberIdentity
            } catch is CancellationError { throw CancellationError() }
            catch { worktrees[index].statusError = error.localizedDescription }
        }
        let refsOutput = try await runner.run([
            "for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads", "refs/remotes"
        ], at: accessPath)
        var branches: [BranchStatus] = []
        var refsBySHA: [String: [GitRef]] = [:]
        for line in refsOutput.split(separator: "\n") {
            let parts = line.components(separatedBy: "\0")
            guard parts.count == 3, parts[2].isEmpty else { continue }
            let remote = parts[0].hasPrefix("refs/remotes/")
            let prefix = remote ? "refs/remotes/" : "refs/heads/"
            let name = String(parts[0].dropFirst(prefix.count))
            branches.append(BranchStatus(branchName: name, headSHA: parts[1], isRemote: remote))
            refsBySHA[parts[1], default: []].append(GitRef(name: name, kind: remote ? .remoteBranch : .localBranch))
        }
        let localBranches = branches.filter { !$0.isRemote }
        var defaultName: String?
        // This reads cached symbolic refs only. Atlas never contacts a remote automatically.
        if let originHead = try? await runner.run(["symbolic-ref", "refs/remotes/origin/HEAD"], at: accessPath) {
            let name = GitParser.trimLineEnding(originHead).replacingOccurrences(of: "refs/remotes/origin/", with: "")
            if localBranches.contains(where: { $0.branchName == name }) { defaultName = name }
        }
        if defaultName == nil {
            defaultName = ["main", "master"].first { candidate in localBranches.contains { $0.branchName == candidate } }
                ?? worktrees.first(where: { $0.isMain })?.branchName
                ?? localBranches.first?.branchName
        }
        let defaultSHA = localBranches.first(where: { $0.branchName == defaultName })?.headSHA
        var tips = Set(worktrees.filter { !$0.isBare }.map(\.headSHA).filter { !$0.isEmpty && !$0.allSatisfy { $0 == "0" } })
        if let defaultSHA { tips.insert(defaultSHA) }
        var commits: [CommitNode] = []
        let logPrefix = ["log", "--topo-order", "--no-show-signature", "--no-decorate", "-z", "--format=%H%x00%P%x00%an%x00%at%x00%s"]
        if !tips.isEmpty {
            do {
                commits = try GitParser.commits(await runner.run(logPrefix + ["--max-count=\(historyLimit)"] + tips.sorted() + ["--"], at: accessPath))
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("部分提交读取失败：\(error.localizedDescription)") }
            // A recent busy branch must not hide an old or detached worktree head.
            let loaded = Set(commits.map(\.sha))
            for tip in tips.sorted() where !loaded.contains(tip) {
                do {
                    let extra = try GitParser.commits(await runner.run(logPrefix + ["--max-count=40", tip, "--"], at: accessPath))
                    commits.append(contentsOf: extra)
                } catch is CancellationError { throw CancellationError() }
                catch { warnings.append("HEAD \(shortSHA(tip)) 未能读取：\(error.localizedDescription)") }
            }
        }
        commits = WorktreeGraphProjector.topologicalOrder(commits).map { commit in
            var value = commit; value.refs = refsBySHA[commit.sha] ?? []; return value
        }
        let loaded = Set(commits.map(\.sha))
        let truncated = commits.contains { $0.parentSHAs.contains { !loaded.contains($0) } }
        let final = try await commonDirectory(at: path)
        guard final.path == initial.path && final.identity == initial.identity else {
            throw WorktreeSafetyError("扫描期间仓库目录身份发生变化；保留旧卡片并禁用写操作。")
        }
        let memberBindings = worktrees.reduce(into: [String: RepositoryDirectoryIdentity]()) { bindings, worktree in
            if let identity = worktree.directoryIdentity { bindings[worktree.path] = identity }
        }
        let record = RepositoryRecord(id: existingID ?? UUID(), displayName: URL(fileURLWithPath: root).lastPathComponent,
                                      rootPath: accessPath, commonDirectory: initial.path,
                                      commonDirectoryIdentity: initial.identity,
                                      memberDirectoryIdentities: memberBindings,
                                      defaultBranch: defaultName, lastScannedAt: Date())
        return RepositorySnapshot(record: record, worktrees: worktrees, commits: commits,
                                  branches: branches, historyTruncated: truncated, warnings: warnings)
    }
}
