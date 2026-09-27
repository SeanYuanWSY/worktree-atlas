// Derived from Oreo992/GitScope GitModels.swift (MIT), pinned in THIRD_PARTY_NOTICES.md.
// Atlas adds repository identity, explicit unknown status, and bounded-history metadata.
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Filesystem identity of a Git common directory or worktree directory. A path
/// alone can name different contents after its original directory is replaced.
public struct RepositoryDirectoryIdentity: Codable, Equatable, Sendable {
    public var device: UInt64
    public var inode: UInt64
    public init(device: UInt64, inode: UInt64) {
        self.device = device; self.inode = inode
    }
}

/// Read the directory itself, without following a symlink at the worktree path
/// or any of its ancestors. Git's remove command can follow such a link while
/// recursively deleting a worktree, so a normal file-existence check is unsafe.
enum WorktreePathIdentity {
    static func canonicalPath(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains("\0"),
              let resolved = path.withCString({ realpath($0, nil) }) else {
            throw WorktreeSafetyError("工作树路径不可用，已拒绝操作。")
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
    static func at(_ path: String) throws -> RepositoryDirectoryIdentity {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw WorktreeSafetyError("工作树路径不是有效的绝对路径，已拒绝操作。")
        }
        var current = ""
        var result: RepositoryDirectoryIdentity?
        for component in path.split(separator: "/") {
            guard component != ".", component != ".." else {
                throw WorktreeSafetyError("工作树路径包含未规范化的目录，已拒绝操作。")
            }
            current += "/" + component
            var metadata = stat()
            guard current.withCString({ lstat($0, &metadata) }) == 0,
                  metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                throw WorktreeSafetyError("工作树路径不可用或包含符号链接，已拒绝操作：\(current)")
            }
            result = RepositoryDirectoryIdentity(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
        }
        guard let result else { throw WorktreeSafetyError("工作树路径无效，已拒绝操作。") }
        return result
    }
}

public struct RepositoryRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var rootPath: String
    public var commonDirectory: String
    /// Missing in older saved records. Such records require explicit re-registration.
    public var commonDirectoryIdentity: RepositoryDirectoryIdentity?
    /// Persistent path bindings. Retain removed paths so a later replacement at
    /// the same path cannot become trusted just because the card was refreshed.
    /// Missing in older saved records; users must explicitly re-add that repo.
    public var memberDirectoryIdentities: [String: RepositoryDirectoryIdentity]?
    public var defaultBranch: String?
    public var lastScannedAt: Date?
    public init(id: UUID = UUID(), displayName: String, rootPath: String,
                commonDirectory: String = "", commonDirectoryIdentity: RepositoryDirectoryIdentity? = nil,
                memberDirectoryIdentities: [String: RepositoryDirectoryIdentity]? = nil,
                defaultBranch: String? = nil, lastScannedAt: Date? = nil) {
        self.id = id; self.displayName = displayName; self.rootPath = rootPath
        self.commonDirectory = commonDirectory; self.commonDirectoryIdentity = commonDirectoryIdentity
        self.memberDirectoryIdentities = memberDirectoryIdentities
        self.defaultBranch = defaultBranch; self.lastScannedAt = lastScannedAt
    }
}

public struct RepositorySnapshot: Equatable, Sendable {
    public var record: RepositoryRecord
    public var worktrees: [GitWorktree]
    public var commits: [CommitNode]
    public var branches: [BranchStatus]
    public var historyTruncated: Bool
    public var warnings: [String]
    public init(record: RepositoryRecord, worktrees: [GitWorktree], commits: [CommitNode],
                branches: [BranchStatus] = [], historyTruncated: Bool = false, warnings: [String] = []) {
        self.record = record; self.worktrees = worktrees; self.commits = commits; self.branches = branches
        self.historyTruncated = historyTruncated; self.warnings = warnings
    }
}

public struct GitWorktree: Equatable, Identifiable, Codable, Sendable {
    public var id: String { path }
    public var path: String
    /// Captured during a successful scan. Missing on demos and old records.
    public var directoryIdentity: RepositoryDirectoryIdentity?
    public var headSHA: String
    public var branchName: String?
    public var isMain: Bool
    public var isBare: Bool
    public var isDetached: Bool
    public var isLocked: Bool
    public var isPrunable: Bool
    public var lockReason: String?
    public var dirtyCount: Int
    public var aheadCount: Int
    public var behindCount: Int
    public var hasUpstream: Bool
    public var statusKnown: Bool
    public var statusError: String?
    public init(path: String, headSHA: String, directoryIdentity: RepositoryDirectoryIdentity? = nil,
                branchName: String? = nil, isMain: Bool = false,
                isBare: Bool = false, isDetached: Bool = false, isLocked: Bool = false, isPrunable: Bool = false,
                lockReason: String? = nil, dirtyCount: Int = 0, aheadCount: Int = 0, behindCount: Int = 0,
                hasUpstream: Bool = false, statusKnown: Bool = false, statusError: String? = nil) {
        self.path = path; self.headSHA = headSHA; self.directoryIdentity = directoryIdentity
        self.branchName = branchName; self.isMain = isMain
        self.isBare = isBare; self.isDetached = isDetached; self.isLocked = isLocked; self.isPrunable = isPrunable
        self.lockReason = lockReason; self.dirtyCount = dirtyCount; self.aheadCount = aheadCount
        self.behindCount = behindCount; self.hasUpstream = hasUpstream; self.statusKnown = statusKnown; self.statusError = statusError
    }
    public var title: String { branchName ?? (isBare ? "Bare repository" : "Detached · \(shortSHA(headSHA))") }
    public var needsAttention: Bool { !isBare && (!statusKnown || dirtyCount > 0 || isPrunable || isDetached || behindCount > 0) }
    public var canOfferRemoval: Bool {
        !isMain && !isBare && !isLocked && !isPrunable && directoryIdentity != nil && statusKnown && dirtyCount == 0
    }
    public var statusSummary: String {
        if isBare { return "裸仓库" }
        if isPrunable { return "路径不可用" }
        if !statusKnown { return "状态未知" }
        if dirtyCount > 0 { return "\(dirtyCount) 项变更" }
        return "干净"
    }
}

public struct CommitNode: Equatable, Identifiable, Codable, Sendable {
    public var id: String { sha }
    public var sha: String
    public var parentSHAs: [String]
    public var authorName: String
    public var authoredDate: Date
    public var committedDate: Date
    public var subject: String
    public var body: String
    public var refs: [GitRef]
    public init(sha: String, parentSHAs: [String], authorName: String = "", authoredDate: Date = .distantPast,
                subject: String = "", body: String = "", committedDate: Date? = nil, refs: [GitRef] = []) {
        self.sha = sha; self.parentSHAs = parentSHAs; self.authorName = authorName
        self.authoredDate = authoredDate; self.committedDate = committedDate ?? authoredDate
        self.subject = subject; self.body = body; self.refs = refs
    }
}

public struct GitRef: Equatable, Identifiable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case head, localBranch, remoteBranch, tag, other }
    public var id: String { "\(kind.rawValue):\(name)" }
    public var name: String
    public var kind: Kind
    public init(name: String, kind: Kind) { self.name = name; self.kind = kind }
}

public struct BranchStatus: Equatable, Identifiable, Sendable {
    public var id: String { branchName }
    public var branchName: String
    public var headSHA: String
    public var isRemote: Bool
    public init(branchName: String, headSHA: String, isRemote: Bool = false) {
        self.branchName = branchName; self.headSHA = headSHA; self.isRemote = isRemote
    }
}
public func shortSHA(_ sha: String) -> String { String(sha.prefix(7)) }
