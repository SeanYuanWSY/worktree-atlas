import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct GitCommandError: Error, LocalizedError, Sendable {
    public var arguments: [String]
    public var exitCode: Int32
    public var message: String
    public var errorDescription: String? { message }
    public init(_ args: [String], code: Int32, message: String) {
        arguments = args; exitCode = code; self.message = message
    }
}
public protocol GitCommandRunning: Sendable {
    func run(_ arguments: [String], at directory: String) async throws -> String
}
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public struct GitCommandRunner: GitCommandRunning {
    public var timeout: TimeInterval
    public var maximumOutputBytes: Int
    public init(timeout: TimeInterval = 20, maximumOutputBytes: Int = 12_000_000) {
        self.timeout = timeout; self.maximumOutputBytes = maximumOutputBytes
    }
    public func run(_ arguments: [String], at directory: String) async throws -> String {
        let flag = CancellationFlag()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .utility) {
                try execute(arguments, directory: directory, flag: flag)
            }.value
        } onCancel: { flag.cancel() }
    }
    private func execute(_ args: [String], directory: String, flag: CancellationFlag) throws -> String {
        let permitted: Set<String> = ["rev-parse", "symbolic-ref", "for-each-ref", "worktree", "status", "log",
                                      "rev-list", "check-ref-format", "ls-files", "show"]
        guard let command = args.first, permitted.contains(command) else {
            throw GitCommandError(args, code: 64, message: "该 Git 命令不在允许列表中。")
        }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("atlas-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temp) }
        let outURL = temp.appendingPathComponent("stdout"), errURL = temp.appendingPathComponent("stderr")
        _ = fm.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        _ = fm.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let stdout = try FileHandle(forWritingTo: outURL), stderr = try FileHandle(forWritingTo: errURL)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "--no-pager", "--no-optional-locks", "-c", "core.fsmonitor=false",
                             "-c", "core.hooksPath=/dev/null"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        var env = ProcessInfo.processInfo.environment
        // Do not let a launching shell redirect us into a different repository/index.
        for key in env.keys where key.hasPrefix("GIT_") { env.removeValue(forKey: key) }
        env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_PAGER"] = "cat"; env["LC_ALL"] = "C"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        process.standardOutput = stdout; process.standardError = stderr; process.standardInput = FileHandle.nullDevice
        if flag.isCancelled { throw CancellationError() }
        do { try process.run() } catch {
            throw GitCommandError(args, code: 66, message: "无法读取路径或启动 Git：\(directory)。\(error.localizedDescription)")
        }
        let deadline = Date().addingTimeInterval(timeout)
        var failure: String?
        while process.isRunning {
            if flag.isCancelled { failure = "操作已取消"; break }
            if Date() >= deadline { failure = "Git 操作超时（\(Int(timeout)) 秒），未将未知状态视为干净。"; break }
            let outSize = (try? fm.attributesOfItem(atPath: outURL.path)[.size] as? NSNumber)?.intValue ?? 0
            let errSize = (try? fm.attributesOfItem(atPath: errURL.path)[.size] as? NSNumber)?.intValue ?? 0
            if outSize + errSize > maximumOutputBytes { failure = "Git 输出超过安全上限，请缩小读取范围。"; break }
            Thread.sleep(forTimeInterval: 0.015)
        }
        if let failure {
            process.terminate()
            let grace = Date().addingTimeInterval(0.3)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            if flag.isCancelled { throw CancellationError() }
            throw GitCommandError(args, code: 124, message: failure)
        }
        process.waitUntilExit()
        if flag.isCancelled { throw CancellationError() }
        let outputData = try Data(contentsOf: outURL), errorData = try Data(contentsOf: errURL)
        guard outputData.count + errorData.count <= maximumOutputBytes else {
            throw GitCommandError(args, code: 125, message: "Git 输出超过安全上限。")
        }
        guard process.terminationStatus == 0 else {
            let text = String(decoding: errorData.prefix(6000), as: UTF8.self)
            throw GitCommandError(args, code: process.terminationStatus, message: text.isEmpty ? "Git 操作失败" : text)
        }
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw GitCommandError(args, code: 65, message: "Git 返回非 UTF-8 数据；未尝试猜测路径编码。")
        }
        // Git writes successful prune previews to stderr, not stdout.
        if args.prefix(2).elementsEqual(["worktree", "prune"]) {
            return output + String(decoding: errorData, as: UTF8.self)
        }
        return output
    }
}
