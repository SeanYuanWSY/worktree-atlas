import Foundation
import Testing
@testable import AtlasCore

@Suite struct IntegrationTests: Sendable {
    struct Fixture {
        let root: URL
        let repo: String
        init(empty: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("atlas-test-\(UUID().uuidString)")
            repo = root.appendingPathComponent("仓库 with space").path
            try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
            _ = try git(["init", "-b", "main"], at: repo)
            _ = try git(["config", "user.name", "Atlas Tests"], at: repo)
            _ = try git(["config", "user.email", "atlas-tests@example.invalid"], at: repo)
            if !empty {
                try Data("hello".utf8).write(to: URL(fileURLWithPath: repo).appendingPathComponent("tracked.txt"))
                _ = try git(["add", "."], at: repo); _ = try git(["commit", "-m", "initial"], at: repo)
            }
        }
        func close() { try? FileManager.default.removeItem(at: root) }
        func wt(_ name: String = "feature") -> String { root.appendingPathComponent(name).path }
    }
    static func git(_ arguments: [String], at path: String) throws -> String { try AtlasCoreTests_git(arguments, at: path) }
    private func identity(repository: String, path: String) async throws -> RepositoryDirectoryIdentity {
        let canonical = try WorktreePathIdentity.canonicalPath(path)
        let snapshot = try await RepositoryScanner().scan(path: repository)
        return try #require(snapshot.worktrees.first(where: { $0.path == canonical })?.directoryIdentity)
    }
    @Test
    func testScanRealRepoAndDeduplicateIdentityFromLinkedWorktree() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt("功能\n'quoted'"), branch: "feature/test", base: "main", mode: .newBranch)
        let scanner = RepositoryScanner()
        let a = try await scanner.scan(path: f.repo), b = try await scanner.scan(path: f.wt("功能\n'quoted'"))
        #expect((a.record.commonDirectory) == (b.record.commonDirectory))
        #expect((a.record.commonDirectoryIdentity) != nil)
        #expect((a.record.commonDirectoryIdentity) == (b.record.commonDirectoryIdentity))
        #expect((a.worktrees.count) == (2))
        #expect(a.worktrees.allSatisfy { $0.statusKnown })
        #expect(a.worktrees.allSatisfy { $0.directoryIdentity != nil })
        #expect((WorktreeGraphProjector.project(a).nodes[0].worktrees.count) == (2))
    }
    @Test
    func testRealCommitBodyAndCommitTimeAreScanned() async throws {
        let f = try Fixture(); defer { f.close() }
        _ = try Self.git(["commit", "--allow-empty", "-m", "Timeline title", "-m", "Details line one\nDetails line two"], at: f.repo)
        let snapshot = try await RepositoryScanner().scan(path: f.repo)
        let head = try #require(snapshot.commits.first { $0.subject == "Timeline title" })
        #expect(head.body == "Details line one\nDetails line two")
        #expect(head.committedDate.timeIntervalSince1970 > 0)
    }
    @Test
    func testSafeRemovePreservesBranch() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt(), branch: "feature", base: "main", mode: .newBranch)
        let expected = try await identity(repository: f.repo, path: f.wt())
        try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: expected)
        #expect(!(FileManager.default.fileExists(atPath: f.wt())))
        #expect(!(try Self.git(["rev-parse", "refs/heads/feature"], at: f.repo).isEmpty))
    }
    @Test
    func testDirtyAndIgnoredFilesBlockRemoval() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt(), branch: "feature", base: "main", mode: .newBranch)
        let expected = try await identity(repository: f.repo, path: f.wt())
        let untracked = URL(fileURLWithPath: f.wt()).appendingPathComponent("valuable.txt")
        try Data("preserve me".utf8).write(to: untracked)
        do { try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: expected); Issue.record("Removed dirty tree") } catch {}
        try FileManager.default.removeItem(at: untracked)
        let exclude = URL(fileURLWithPath: f.repo).appendingPathComponent(".git/info/exclude")
        try Data(".env\n".utf8).write(to: exclude)
        try Data("SECRET=test-only".utf8).write(to: URL(fileURLWithPath: f.wt()).appendingPathComponent(".env"))
        do { try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: expected); Issue.record("Removed ignored data") } catch {}
        #expect(FileManager.default.fileExists(atPath: f.wt()))
    }
    @Test
    func testLockUnlockAndProtection() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt(), branch: "feature", base: "main", mode: .newBranch)
        let expected = try await identity(repository: f.repo, path: f.wt())
        try await op.setLocked(repository: f.repo, path: f.wt(), locked: true, expectedIdentity: expected)
        do { try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: expected); Issue.record("Removed locked tree") } catch {}
        try await op.setLocked(repository: f.repo, path: f.wt(), locked: false, expectedIdentity: expected)
        try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: expected)
    }
    @Test
    func testMainCannotBeRemoved() async throws {
        let f = try Fixture(); defer { f.close() }
        let expected = try await identity(repository: f.repo, path: f.repo)
        do { try await WorktreeOperator().remove(repository: f.repo, path: f.repo, expectedIdentity: expected); Issue.record("Removed main") } catch {}
    }
    @Test
    func testExistingBranchStaysAttached() async throws {
        let f = try Fixture(); defer { f.close() }
        _ = try Self.git(["branch", "existing"], at: f.repo)
        try await WorktreeOperator().create(repository: f.repo, path: f.wt(), branch: "existing", base: "", mode: .existingBranch)
        #expect((try Self.git(["symbolic-ref", "--short", "HEAD"], at: f.wt()).trimmingCharacters(in: .whitespacesAndNewlines)) == ("existing"))
    }
    @Test
    func testDetachedCreationAndEmptyRepo() async throws {
        let f = try Fixture(); defer { f.close() }
        try await WorktreeOperator().create(repository: f.repo, path: f.wt(), branch: "", base: "main", mode: .detached)
        let s = try await RepositoryScanner().scan(path: f.repo)
        #expect(s.worktrees.contains { $0.isDetached })
        let empty = try Fixture(empty: true); defer { empty.close() }
        let e = try await RepositoryScanner().scan(path: empty.repo)
        #expect(e.commits.isEmpty); #expect((e.worktrees.count) == (1))
    }
    @Test
    func testMissingDiskNotSilentlyDeleted() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt(), branch: "feature", base: "main", mode: .newBranch)
        let registeredPath = try WorktreePathIdentity.canonicalPath(f.wt())
        try FileManager.default.moveItem(atPath: f.wt(), toPath: f.wt("offline"))
        let s = try await RepositoryScanner().scan(path: f.repo)
        let missing = try #require(s.worktrees.first(where: { $0.path == registeredPath }))
        #expect(!(missing.statusKnown)); #expect(!(missing.canOfferRemoval))
        #expect((s.worktrees.count) == (2))
        let preview = try await op.prunePreview(repository: f.repo)
        #expect(!(preview.isEmpty))
        try await op.prune(repository: f.repo, expectedPreview: preview)
        let remaining = try await RepositoryScanner().listWorktrees(at: f.repo)
        #expect((remaining.count) == (1))
    }
    @Test
    func testInvalidBranchAndExistingDirectoryRefused() async throws {
        let f = try Fixture(); defer { f.close() }
        do { try await WorktreeOperator().create(repository: f.repo, path: f.wt(), branch: "-bad", base: "main", mode: .newBranch); Issue.record("Unexpected success") } catch {}
        do { try await WorktreeOperator().create(repository: f.repo, path: f.repo, branch: "ok", base: "main", mode: .newBranch); Issue.record("Unexpected success") } catch {}
    }
    @Test
    func testRunnerRejectsUnapprovedCommand() async throws {
        do { _ = try await GitCommandRunner().run(["reset", "--hard"], at: "/tmp"); Issue.record("Unexpected success") } catch {}
    }
    @Test
    func testBareRepositoryCanBeInspected() async throws {
        let f = try Fixture(); defer { f.close() }
        let bare = f.wt("bare.git")
        _ = try Self.git(["clone", "--bare", f.repo, bare], at: f.repo)
        let snapshot = try await RepositoryScanner().scan(path: bare)
        #expect(snapshot.worktrees[0].isBare)
        #expect(!(snapshot.commits.isEmpty))
    }
    @Test
    func testUniqueDetachedCommitIsProtected() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt(), branch: "", base: "main", mode: .detached)
        _ = try Self.git(["commit", "--allow-empty", "-m", "valuable detached work"], at: f.wt())
        let expected = try await identity(repository: f.repo, path: f.wt())
        do { try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: expected); Issue.record("Discarded detached history") } catch {}
        #expect(FileManager.default.fileExists(atPath: f.wt()))
    }
    @Test
    func testExternallyCreatedWorktreeIsDiscovered() async throws {
        let f = try Fixture(); defer { f.close() }
        let scanner = RepositoryScanner()
        let initial = try await scanner.scan(path: f.repo)
        #expect((initial.worktrees.count) == (1))
        _ = try Self.git(["worktree", "add", "-b", "external", f.wt()], at: f.repo)
        let updated = try await scanner.scan(path: f.repo)
        #expect((updated.worktrees.count) == (2))
    }
    @Test
    func testOldDetachedHeadSurvivesHistoryLimit() async throws {
        let f = try Fixture(); defer { f.close() }
        _ = try Self.git(["worktree", "add", "--detach", f.wt(), "HEAD"], at: f.repo)
        for i in 0..<45 { _ = try Self.git(["commit", "--allow-empty", "-m", "advance \(i)"], at: f.repo) }
        let snapshot = try await RepositoryScanner(historyLimit: 20).scan(path: f.repo)
        let graph = WorktreeGraphProjector.project(snapshot)
        #expect(graph.unplacedWorktrees.isEmpty)
        #expect(snapshot.historyTruncated)
    }
    @Test
    func testReadOnlyScanDoesNotTouchIndexOrHead() async throws {
        let f = try Fixture(); defer { f.close() }
        let index = URL(fileURLWithPath: f.repo).appendingPathComponent(".git/index")
        let before = try Data(contentsOf: index)
        let head = try Self.git(["rev-parse", "HEAD"], at: f.repo)
        _ = try await RepositoryScanner().scan(path: f.repo)
        #expect((before) == (try Data(contentsOf: index)))
        #expect((head) == (try Self.git(["rev-parse", "HEAD"], at: f.repo)))
    }
    @Test
    func testOutputLimitReturnsErrorNotPartialStatus() async throws {
        let f = try Fixture(); defer { f.close() }
        do { _ = try await GitCommandRunner(maximumOutputBytes: 4).run(["status", "--porcelain=v2", "--branch", "-z"], at: f.repo); Issue.record("Accepted truncated data") } catch {}
    }
    @Test
    func testOutOfRepositoryRemovalIsRejected() async throws {
        let f = try Fixture(); defer { f.close() }
        let expected = try await identity(repository: f.repo, path: f.repo)
        do { try await WorktreeOperator().remove(repository: f.repo, path: f.root.path, expectedIdentity: expected); Issue.record("Removed unrelated folder") } catch {}
        #expect(FileManager.default.fileExists(atPath: f.root.path))
    }
    @Test
    func testReplacedLinkedWorktreeCannotBeRemovedOrLocked() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt(), branch: "feature", base: "main", mode: .newBranch)
        let expected = try await identity(repository: f.repo, path: f.wt())
        let parked = f.wt("parked")
        try FileManager.default.moveItem(atPath: f.wt(), toPath: parked)
        try FileManager.default.createSymbolicLink(atPath: f.wt(), withDestinationPath: parked)
        do { try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: expected); Issue.record("Removed through symlink") } catch {}
        do { try await op.setLocked(repository: f.repo, path: f.wt(), locked: true, expectedIdentity: expected); Issue.record("Locked through symlink") } catch {}
        #expect(FileManager.default.fileExists(atPath: parked + "/tracked.txt"))
        let symlinkSnapshot = try await RepositoryScanner().scan(path: f.repo)
        #expect((symlinkSnapshot.worktrees.first(where: { !$0.isMain })?.directoryIdentity) == nil)

        try FileManager.default.removeItem(atPath: f.wt())
        try FileManager.default.copyItem(atPath: parked, toPath: f.wt())
        do { try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: expected); Issue.record("Removed replacement directory") } catch {}
        do { try await op.setLocked(repository: f.repo, path: f.wt(), locked: true, expectedIdentity: expected); Issue.record("Locked replacement directory") } catch {}
        #expect(FileManager.default.fileExists(atPath: f.wt() + "/tracked.txt"))
        #expect(!(try Self.git(["rev-parse", "refs/heads/feature"], at: f.repo).isEmpty))
    }
    @Test
    func testSymlinkedAncestorCannotBeRemoved() async throws {
        let f = try Fixture(); defer { f.close() }
        let parent = f.root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let memberPath = parent.appendingPathComponent("member").path
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: memberPath, branch: "feature", base: "main", mode: .newBranch)
        let expected = try await identity(repository: f.repo, path: memberPath)
        let parked = f.root.appendingPathComponent("parked")
        try FileManager.default.moveItem(at: parent, to: parked)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: parked)
        do { try await op.remove(repository: f.repo, path: memberPath, expectedIdentity: expected); Issue.record("Removed through ancestor symlink") } catch {}
        #expect(FileManager.default.fileExists(atPath: parked.appendingPathComponent("member/tracked.txt").path))
        #expect(!(try Self.git(["rev-parse", "refs/heads/feature"], at: f.repo).isEmpty))
    }
    @Test
    func testChangedPrunePreviewIsRejected() async throws {
        let f = try Fixture(); defer { f.close() }
        do { try await WorktreeOperator().prune(repository: f.repo, expectedPreview: "stale preview"); Issue.record("Unexpected success") } catch {}
    }
    @Test
    func testRealRenameIsCountedOnce() async throws {
        let f = try Fixture(); defer { f.close() }
        _ = try Self.git(["mv", "tracked.txt", "renamed file.txt"], at: f.repo)
        let snapshot = try await RepositoryScanner().scan(path: f.repo)
        #expect((snapshot.worktrees[0].dirtyCount) == (1))
    }
    @Test
    func testStoreRoundTripAndCorruptionIsReported() throws {
        let f = try Fixture(); defer { f.close() }
        let store = RepositoryStore(url: f.root.appendingPathComponent("registry.json"))
        let record = RepositoryRecord(displayName: "仓库", rootPath: f.repo)
        try store.save([record]); #expect((try store.load()) == ([record]))
        try Data("corrupt".utf8).write(to: store.url)
        #expect(throws: Error.self) { try store.load() }
    }
    @Test
    func testReplacedRepositoryAtSamePathIsRejected() async throws {
        let f = try Fixture(); defer { f.close() }
        let scanner = RepositoryScanner()
        let registered = try await scanner.scan(path: f.repo).record
        try await scanner.verifyRegisteredIdentity(registered)
        let refreshed = try await scanner.scanRegistered(registered)
        #expect((refreshed.record.commonDirectoryIdentity) == (registered.commonDirectoryIdentity))

        let oldPath = f.root.appendingPathComponent("old-repository")
        try FileManager.default.moveItem(atPath: f.repo, toPath: oldPath.path)
        try FileManager.default.createDirectory(atPath: f.repo, withIntermediateDirectories: true)
        _ = try Self.git(["init", "-b", "main"], at: f.repo)

        let replacement = try await scanner.scan(path: f.repo).record
        #expect((replacement.commonDirectory) == (registered.commonDirectory))
        #expect((replacement.commonDirectoryIdentity) != (registered.commonDirectoryIdentity))
        do { try await scanner.verifyRegisteredIdentity(registered); Issue.record("Accepted replacement for a registered repository") }
        catch { #expect((error as? WorktreeSafetyError)?.message.contains("身份已变化") == true) }
        do { _ = try await scanner.scanRegistered(registered); Issue.record("Refreshed old card with replacement data") }
        catch { #expect((error as? WorktreeSafetyError)?.message.contains("身份已变化") == true) }
    }
    @Test
    func testRefreshNeverRebindsReplacedMemberAcrossStoreReload() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt(), branch: "feature", base: "main", mode: .newBranch)
        let scanner = RepositoryScanner()
        let registered = try await scanner.scan(path: f.repo).record
        let memberPath = try WorktreePathIdentity.canonicalPath(f.wt())
        let original = try #require(registered.memberDirectoryIdentities?[memberPath])
        let store = RepositoryStore(url: f.root.appendingPathComponent("registry.json"))
        try store.save([registered])

        let parked = f.wt("parked")
        try FileManager.default.moveItem(atPath: f.wt(), toPath: parked)
        try FileManager.default.copyItem(atPath: parked, toPath: f.wt())
        let first = try await scanner.scanRegistered(try #require(store.load().first))
        let stale = try #require(first.worktrees.first(where: { $0.path == memberPath }))
        #expect((stale.directoryIdentity) == nil)
        #expect(!(stale.statusKnown))
        #expect(!(stale.canOfferRemoval))
        #expect((first.record.memberDirectoryIdentities?[memberPath]) == (original))
        try store.save([first.record])

        let second = try await scanner.scanRegistered(try #require(store.load().first))
        #expect((second.worktrees.first(where: { $0.path == memberPath })?.directoryIdentity) == nil)
        #expect((second.record.memberDirectoryIdentities?[memberPath]) == (original))
        do { try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: stale.directoryIdentity); Issue.record("Removed stale member") } catch {}
        #expect(FileManager.default.fileExists(atPath: f.wt() + "/tracked.txt"))
        #expect(!(try Self.git(["rev-parse", "refs/heads/feature"], at: f.repo).isEmpty))

        // The explicit add path scans anew and can establish a new binding.
        let rebound = try await scanner.scan(path: f.repo)
        #expect((rebound.record.commonDirectoryIdentity) == (registered.commonDirectoryIdentity))
        #expect((rebound.record.memberDirectoryIdentities?[memberPath]) != (original))
        #expect((rebound.worktrees.first(where: { $0.path == memberPath })?.directoryIdentity) != nil)
    }
    @Test
    func testRemovedMemberPathStaysBoundWhenReusedLater() async throws {
        let f = try Fixture(); defer { f.close() }
        let op = WorktreeOperator()
        try await op.create(repository: f.repo, path: f.wt(), branch: "feature", base: "main", mode: .newBranch)
        let scanner = RepositoryScanner()
        let registered = try await scanner.scan(path: f.repo).record
        let memberPath = try WorktreePathIdentity.canonicalPath(f.wt())
        let original = try #require(registered.memberDirectoryIdentities?[memberPath])
        try await op.remove(repository: f.repo, path: f.wt(), expectedIdentity: original)

        let withoutMember = try await scanner.scanRegistered(registered)
        #expect((withoutMember.record.memberDirectoryIdentities?[memberPath]) == (original))
        let store = RepositoryStore(url: f.root.appendingPathComponent("registry.json"))
        try store.save([withoutMember.record])
        _ = try Self.git(["worktree", "add", "-b", "reused", f.wt()], at: f.repo)
        let reused = try await scanner.scanRegistered(try #require(store.load().first))
        #expect((reused.worktrees.first(where: { $0.path == memberPath })?.directoryIdentity) == nil)
        #expect((reused.record.memberDirectoryIdentities?[memberPath]) == (original))
        #expect(FileManager.default.fileExists(atPath: f.wt() + "/tracked.txt"))
    }
    @Test
    func testLegacyRecordLoadsButRequiresExplicitReRegistration() async throws {
        let f = try Fixture(); defer { f.close() }
        let scanner = RepositoryScanner()
        let bound = try await scanner.scan(path: f.repo).record
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(bound)) as? [String: Any])
        json.removeValue(forKey: "commonDirectoryIdentity")
        let legacy = try JSONDecoder().decode(RepositoryRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect((legacy.commonDirectoryIdentity) == nil)
        do { _ = try await scanner.scanRegistered(legacy); Issue.record("Silently trusted an unbound legacy record") }
        catch { #expect((error as? WorktreeSafetyError)?.message.contains("尚未验证") == true) }

        var memberlessJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(bound)) as? [String: Any])
        memberlessJSON.removeValue(forKey: "memberDirectoryIdentities")
        let memberless = try JSONDecoder().decode(RepositoryRecord.self, from: JSONSerialization.data(withJSONObject: memberlessJSON))
        #expect((memberless.commonDirectoryIdentity) != nil)
        #expect((memberless.memberDirectoryIdentities) == nil)
        do { _ = try await scanner.scanRegistered(memberless); Issue.record("Silently rebound a record without member identities") }
        catch { #expect((error as? WorktreeSafetyError)?.message.contains("尚未验证") == true) }
        do { try await scanner.verifyRegisteredIdentity(memberless); Issue.record("Allowed mutation from a memberless legacy record") }
        catch { #expect((error as? WorktreeSafetyError)?.message.contains("尚未验证") == true) }
    }
}

private func git(_ arguments: [String], at path: String) throws -> String { try AtlasCoreTests_git(arguments, at: path) }
private func AtlasCoreTests_git(_ arguments: [String], at path: String) throws -> String {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments; process.currentDirectoryURL = URL(fileURLWithPath: path)
    process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    let output = Pipe(); process.standardOutput = output; process.standardError = output
    try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else { throw WorktreeSafetyError("fixture git failed: \(text)") }
    return text
}
