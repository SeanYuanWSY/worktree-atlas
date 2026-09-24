import Foundation

public struct WorkingStatus: Equatable, Sendable {
    public var dirtyCount = 0
    public var ahead = 0
    public var behind = 0
    public var hasUpstream = false
}
public enum GitParser {
    /// `git worktree list --porcelain -z`: fields are NUL-separated, records end in double NUL.
    /// No splitting on newlines, whitespace, or quoting heuristics for filesystem paths.
    public static func worktrees(_ output: String) throws -> [GitWorktree] {
        var result: [GitWorktree] = []
        for group in output.components(separatedBy: "\0\0") where !group.isEmpty {
            let fields = group.components(separatedBy: "\0").filter { !$0.isEmpty }
            guard let pathField = fields.first, pathField.hasPrefix("worktree ") else {
                throw GitCommandError(["worktree", "list"], code: 65, message: "无法解析工作树记录。")
            }
            func value(_ name: String) -> String? {
                fields.first(where: { $0.hasPrefix(name + " ") }).map { String($0.dropFirst(name.count + 1)) }
            }
            let branch = value("branch").map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst(11)) : $0 }
            result.append(GitWorktree(path: String(pathField.dropFirst(9)), headSHA: value("HEAD") ?? "",
                branchName: branch, isMain: result.isEmpty && !fields.contains("bare"), isBare: fields.contains("bare"),
                isDetached: fields.contains("detached"),
                isLocked: fields.contains("locked") || value("locked") != nil,
                isPrunable: fields.contains("prunable") || value("prunable") != nil, lockReason: value("locked")))
        }
        return result
    }
    /// `git status --porcelain=v2 --branch -z`; rename records have an extra NUL source path.
    public static func status(_ output: String) throws -> WorkingStatus {
        var status = WorkingStatus()
        let fields = output.components(separatedBy: "\0")
        var index = 0
        while index < fields.count {
            let field = fields[index]; index += 1
            if field.isEmpty { continue }
            if field.hasPrefix("# branch.upstream ") { status.hasUpstream = true }
            else if field.hasPrefix("# branch.ab ") {
                let parts = field.split(separator: " ")
                if parts.count == 4 { status.ahead = Int(parts[2].dropFirst()) ?? 0; status.behind = Int(parts[3].dropFirst()) ?? 0 }
            } else if field.hasPrefix("1 ") || field.hasPrefix("u ") || field.hasPrefix("? ") { status.dirtyCount += 1 }
            else if field.hasPrefix("2 ") { status.dirtyCount += 1; index += 1 }
            else if !field.hasPrefix("# ") && !field.hasPrefix("! ") {
                throw GitCommandError(["status"], code: 65, message: "无法识别工作树状态格式。")
            }
        }
        return status
    }
    /// `git log -z --format=%H%x00%P%x00%an%x00%at%x00%s`: exactly five fields per record.
    public static func commits(_ output: String) throws -> [CommitNode] {
        if output.isEmpty { return [] }
        var parts = output.components(separatedBy: "\0")
        if parts.last == "" { parts.removeLast() }
        guard parts.count.isMultiple(of: 5) else {
            throw GitCommandError(["log"], code: 65, message: "提交数据格式不完整。")
        }
        var commits: [CommitNode] = []
        for i in stride(from: 0, to: parts.count, by: 5) {
            let parentSHAs = parts[i + 1].split(separator: " ").map { String($0) }
            let authoredDate = Date(timeIntervalSince1970: Double(parts[i + 3]) ?? 0)
            commits.append(CommitNode(sha: parts[i], parentSHAs: parentSHAs,
                                      authorName: parts[i + 2], authoredDate: authoredDate, subject: parts[i + 4]))
        }
        return commits
    }
    public static func trimLineEnding(_ output: String) -> String {
        output.hasSuffix("\n") ? String(output.dropLast()) : output
    }
}
