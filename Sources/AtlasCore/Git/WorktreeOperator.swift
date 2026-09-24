import Foundation

public struct WorktreeSafetyError: Error, LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
public enum WorktreeCreationMode: String, CaseIterable, Sendable { case newBranch, existingBranch, detached }

public struct WorktreeOperator: Sendable {
    public let runner: any GitCommandRunning
    public init(runner: any GitCommandRunning = GitCommandRunner(timeout: 60)) { self.runner = runner }
    private func member(_ path: String, repository: String,
                        expectedIdentity: RepositoryDirectoryIdentity?) async throws -> GitWorktree {
        guard let expectedIdentity else {
            throw WorktreeSafetyError("此工作树没有已验证的目录身份，请刷新仓库后重试。")
        }
        let all = try GitParser.worktrees(await runner.run(["worktree", "list", "--porcelain", "-z"], at: repository))
        let canonicalRequest = try WorktreePathIdentity.canonicalPath(path)
        guard let item = all.first(where: { $0.path == canonicalRequest }) else {
            throw WorktreeSafetyError("该路径已不是此仓库的工作树，请刷新后重试。")
        }
        guard try WorktreePathIdentity.at(item.path) == expectedIdentity else {
            throw WorktreeSafetyError("工作树目录身份已变化，已拒绝操作。请刷新仓库。")
        }
        let repositoryCommon = try await commonDirectory(at: repository)
        let memberCommon = try await commonDirectory(at: item.path)
        guard repositoryCommon == memberCommon else {
            throw WorktreeSafetyError("此目录已不属于原仓库，已拒绝操作。")
        }
        return item
    }
    private func commonDirectory(at path: String) async throws -> String {
        let output = try await runner.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], at: path)
        return try WorktreePathIdentity.canonicalPath(GitParser.trimLineEnding(output))
    }
    public func create(repository: String, path: String, branch: String, base: String,
                       mode: WorktreeCreationMode) async throws {
        guard path.hasPrefix("/"), !path.contains("\0"), !FileManager.default.fileExists(atPath: path) else {
            throw WorktreeSafetyError("目标必须是尚不存在的绝对路径。不会覆盖现有文件夹。")
        }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorktreeSafetyError("目标的父目录必须已存在。")
        }
        var args = ["worktree", "add"]
        if mode != .detached {
            guard !branch.isEmpty, !branch.hasPrefix("-"), !branch.contains("\0") else {
                throw WorktreeSafetyError("请输入有效的分支名。")
            }
            _ = try await runner.run(["check-ref-format", "--branch", branch], at: repository)
        }
        if mode == .newBranch { args += ["-b", branch] }
        if mode == .detached { args.append("--detach") }
        let source: String
        if mode == .existingBranch {
            source = "refs/heads/" + branch
        } else {
            guard !base.isEmpty, !base.hasPrefix("-"), !base.contains("\0") else {
                throw WorktreeSafetyError("请输入起点分支或提交。")
            }
            source = base
        }
        // Resolve user input before passing it into a mutating command; never run it through a shell.
        let sha = GitParser.trimLineEnding(try await runner.run(
            ["rev-parse", "--verify", "--end-of-options", "\(source)^{commit}"], at: repository))
        args += ["--", path, mode == .existingBranch ? branch : sha]
        _ = try await runner.run(args, at: repository)
    }
    /// Deliberately stricter than Git: refuse ignored files too (e.g. .env, datasets, node_modules).
    /// Never use --force; preserve the branch. Stop other writers first: these checks are not atomic.
    public func remove(repository: String, path: String,
                       expectedIdentity: RepositoryDirectoryIdentity?) async throws {
        let item = try await member(path, repository: repository, expectedIdentity: expectedIdentity)
        guard !item.isMain && !item.isBare else { throw WorktreeSafetyError("不能移除主工作树或裸仓库。") }
        guard !item.isLocked else { throw WorktreeSafetyError("工作树已锁定，请先明确解锁。") }
        if item.isDetached {
            let protectingRefs = try await runner.run(
                ["for-each-ref", "--contains=HEAD", "--format=%(refname)", "refs/heads", "refs/tags"], at: item.path)
            guard !protectingRefs.isEmpty else {
                throw WorktreeSafetyError("此游离 HEAD 没有本地分支或标签保留。请先用外部 Git 工具保存这些提交。")
            }
        }
        let status = try GitParser.status(await runner.run(
            ["status", "--porcelain=v2", "-z", "--untracked-files=all", "--ignore-submodules=none"], at: item.path))
        guard status.dirtyCount == 0 else { throw WorktreeSafetyError("存在未提交或未跟踪文件，已拒绝移除。") }
        let ignored = try await runner.run(["ls-files", "--others", "--ignored", "--exclude-standard", "-z"], at: item.path)
        guard ignored.isEmpty else { throw WorktreeSafetyError("存在被 Git 忽略的文件。请先备份或手动清理，避免丢失 .env、数据或构建产物。") }
        let current = try await member(path, repository: repository, expectedIdentity: expectedIdentity)
        guard !current.isMain && !current.isBare && !current.isLocked else {
            throw WorktreeSafetyError("工作树状态已变化，已拒绝移除。")
        }
        // The checked path is also the path passed to Git. Git can recursively
        // delete through a symlink, so never pass an unchecked caller alias.
        guard try WorktreePathIdentity.at(current.path) == expectedIdentity else {
            throw WorktreeSafetyError("工作树目录身份已变化，已拒绝移除。")
        }
        _ = try await runner.run(["worktree", "remove", "--", current.path], at: repository)
    }
    public func setLocked(repository: String, path: String, locked: Bool,
                          expectedIdentity: RepositoryDirectoryIdentity?) async throws {
        let item = try await member(path, repository: repository, expectedIdentity: expectedIdentity)
        guard !item.isMain && !item.isBare else { throw WorktreeSafetyError("主工作树无需锁定。") }
        guard try WorktreePathIdentity.at(item.path) == expectedIdentity else {
            throw WorktreeSafetyError("工作树目录身份已变化，已拒绝操作。")
        }
        let args = locked ? ["worktree", "lock", "--reason", "Protected in Worktree Atlas", "--", item.path]
                          : ["worktree", "unlock", "--", item.path]
        _ = try await runner.run(args, at: repository)
    }
    public func prunePreview(repository: String) async throws -> String {
        try await runner.run(["worktree", "prune", "--dry-run", "--verbose", "--expire=now"], at: repository)
    }
    public func prune(repository: String, expectedPreview: String) async throws {
        let current = try await prunePreview(repository: repository)
        guard current == expectedPreview, !current.isEmpty else {
            throw WorktreeSafetyError("待清理记录已变化或已为空，请重新预览。")
        }
        _ = try await runner.run(["worktree", "prune", "--verbose", "--expire=now"], at: repository)
    }
}
