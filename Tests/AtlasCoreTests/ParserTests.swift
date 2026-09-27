import Testing
@testable import AtlasCore
@Suite struct ParserTests {
    @Test
    func testPathsWithSpacesUnicodeNewlineAndQuotes() throws {
        let path = "/tmp/项目 two\n\"quoted\""
        let rows = try GitParser.worktrees("worktree \(path)\0HEAD abc\0branch refs/heads/main\0\0")
        #expect((rows[0].path) == (path)); #expect(rows[0].isMain)
    }
    @Test
    func testLockedAndMissingAreIndependent() throws {
        let rows = try GitParser.worktrees("worktree /r\0HEAD a\0detached\0locked external disk\0prunable missing gitdir\0\0")
        #expect(rows[0].isLocked); #expect(rows[0].isPrunable); #expect(rows[0].isDetached)
        #expect((rows[0].lockReason) == ("external disk"))
    }
    @Test
    func testBareAndUnborn() throws {
        let bare = try GitParser.worktrees("worktree /bare\0bare\0\0")[0]
        #expect(bare.isBare); #expect(!(bare.isMain))
        let unborn = try GitParser.worktrees("worktree /r\0HEAD 0000000\0branch refs/heads/main\0\0")[0]
        #expect((unborn.branchName) == ("main"))
    }
    @Test
    func testRenameCountsOnceEvenIfOriginalPathLooksLikeStatus() throws {
        let status = try GitParser.status("2 R. N... 100644 100644 100644 a b R100 new\0? old\0? real\0")
        #expect((status.dirtyCount) == (2))
    }
    @Test
    func testAheadBehindAndUpstream() throws {
        let status = try GitParser.status("# branch.upstream origin/main\0# branch.ab +3 -4\0")
        #expect((status.ahead) == (3)); #expect((status.behind) == (4)); #expect(status.hasUpstream)
    }
    @Test
    func testUnknownFormatIsNotClean() {
        #expect(throws: Error.self) { try GitParser.status("unexpected\0") }
    }
    @Test
    func testCommitFieldsAllowTabsAndUnicode() throws {
        let commits = try GitParser.commits("abc\0parent\0王\0" + "42\0" + "50\0subject\twith spaces\0正文\n第二行\0")
        #expect((commits[0].subject) == ("subject\twith spaces"))
        #expect((commits[0].parentSHAs) == (["parent"]))
        #expect((commits[0].body) == "正文\n第二行")
        #expect((commits[0].committedDate.timeIntervalSince1970) == 50)
    }
    @Test
    func testMalformedCommitRejected() { #expect(throws: Error.self) { try GitParser.commits("a\0b\0") } }
    @Test
    func testTrimRemovesOnlyFinalLineEnding() { #expect((GitParser.trimLineEnding("/tmp/path\n\n")) == ("/tmp/path\n")) }
    @Test
    func testUnknownStateCannotOfferRemoval() { #expect(!(GitWorktree(path: "/x", headSHA: "a").canOfferRemoval)) }
}
