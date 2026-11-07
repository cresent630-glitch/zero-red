import XCTest
@testable import ZeroRedCore

final class BrowserFeatureTests: XCTestCase {
    func testSearchProvidersPreserveChineseQueries() {
        for provider in SearchProvider.allCases {
            let query = "中文 & zero red # +"
            let result = provider.search(query)
            let name = provider == .baidu ? "wd" : "q"
            XCTAssertEqual(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value, query)
        }
    }
    func testSearchProviderDoesNotRewriteExplicitWebsite() {
        XCTAssertEqual(SearchProvider.google.resolve("https://example.com")?.host, "example.com")
        XCTAssertEqual(SearchProvider.duckduckgo.resolve("中文 搜索")?.host, "duckduckgo.com")
        XCTAssertNil(SearchProvider.google.resolve("  "))
    }
    func testIndependentTabHistoryAndForwardTruncation() {
        var first = BrowserTabRecord(), second = BrowserTabRecord()
        let a = URL(string: "https://example.com/a")!, b = URL(string: "https://example.com/b")!, c = URL(string: "https://example.com/c")!
        first.visit(a, title: "A"); first.visit(b, title: "B"); second.visit(c, title: "C")
        XCTAssertEqual(first.move(-1), a); XCTAssertTrue(first.canForward)
        first.visit(c, title: "C"); XCTAssertFalse(first.canForward)
        XCTAssertEqual(second.history, [c]); XCTAssertEqual(first.history, [a,c])
    }
    func testSessionNeverSerializesPrivateURLsOrTitles() throws {
        var normal = BrowserTabRecord(), secret = BrowserTabRecord(isPrivate: true)
        normal.visit(URL(string: "https://example.com")!, title: "Public")
        secret.visit(URL(string: "https://secret.example/private")!, title: "Sensitive")
        let snapshot = BrowserSessionSnapshot(tabs: [normal,secret], selected: secret.id, recentlyClosed: [secret,normal])
        let data = try JSONEncoder().encode(snapshot)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("secret.example")); XCTAssertFalse(json.contains("Sensitive"))
        XCTAssertEqual(snapshot.selected, normal.id); XCTAssertEqual(snapshot.recentlyClosed.count, 1)
    }
    func testSessionReopenListIsBounded() {
        let tabs = (0..<20).map { _ in BrowserTabRecord() }
        XCTAssertEqual(BrowserSessionSnapshot(recentlyClosed: tabs).recentlyClosed.count, 10)
    }
    func testTabHistoryIsBounded() {
        var tab = BrowserTabRecord()
        for n in 0..<120 { tab.visit(URL(string: "https://example.com/\(n)")!, title: "\(n)") }
        XCTAssertEqual(tab.history.count, 100); XCTAssertEqual(tab.index, 99)
        XCTAssertEqual(tab.history.first?.lastPathComponent, "20")
    }
    func testReadingSearchIncludesFullTextAndTags() {
        let doc = ReadingDocument(title: "Notes", text: "中文正文 hello", tag: "研究")
        XCTAssertTrue(ReadingText.matches(doc, query: "正文")); XCTAssertTrue(ReadingText.matches(doc, query: "HELLO")); XCTAssertTrue(ReadingText.matches(doc, query: "研究")); XCTAssertFalse(ReadingText.matches(doc, query: "missing"))
    }
    func testReadingProgressBounds() {
        XCTAssertEqual(ReadingText.progress(offset: 50, height: 200, viewport: 100), 0.5)
        XCTAssertEqual(ReadingText.progress(offset: -1, height: 200, viewport: 100), 0)
        XCTAssertEqual(ReadingText.progress(offset: 1000, height: 200, viewport: 100), 1)
        XCTAssertEqual(ReadingText.progress(offset: 0, height: 50, viewport: 100), 1)
    }
    func testDocxXMLExtractsOnlyTextAndParagraphs() throws {
        let data = Data("<w:document xmlns:w='urn:test'><w:body><w:p><w:r><w:t>中文</w:t></w:r></w:p><w:p><w:r><w:t>Hello &amp; world</w:t></w:r></w:p></w:body></w:document>".utf8)
        XCTAssertEqual(try DocxTextParser().parse(data), "中文\n\nHello & world")
    }
    func testCorruptDocxXMLIsReported() { XCTAssertThrowsError(try DocxTextParser().parse(Data("<broken>".utf8))) }
    func testFilenameCannotEscapeDownloadDirectory() {
        for input in ["../../secret", "a\\b", "a/b", "../", "\0", "a\nb"] { let name = FileNames.safe(input); XCTAssertFalse(name.contains("/")); XCTAssertFalse(name.contains("\\")); XCTAssertFalse(name.contains("\0")); XCTAssertFalse(name.isEmpty) }
        XCTAssertLessThanOrEqual(FileNames.safe(String(repeating: "a", count: 300)).count, 150)
    }
    func testDownloadProgressHandlesUnknownLength() {
        var job = DownloadRecord(url: URL(string: "https://example.com/file")!, name: "file")
        XCTAssertNil(job.progress); job.expected = 100; job.received = 200; XCTAssertEqual(job.progress, 1)
    }
    func testContentBlockingRulesAreValidJSONAndRespectToggles() throws {
        XCTAssertTrue(ContentBlocking.rules(trackers: false, ads: false).isEmpty)
        let rules = ContentBlocking.rules(trackers: true, ads: true, extraDomains: "valid.example invalid/* https://evil.test")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: rules))
        let json = String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
        XCTAssertTrue(json.contains("valid")); XCTAssertFalse(json.contains("invalid")); XCTAssertFalse(json.contains("evil"))
    }
    func testSubtitleParserSupportsSRTAndWebVTT() {
        let srt = "1\n00:00:01,000 --> 00:00:03,500\n中文字幕\n\n2\n00:00:04,000 --> 00:00:05,000\nEnglish"
        let cues = SubtitleParser.parse(srt)
        XCTAssertEqual(cues.count, 2); XCTAssertEqual(cues[0].start, 1); XCTAssertEqual(cues[0].end, 3.5); XCTAssertEqual(cues[0].text, "中文字幕")
        XCTAssertEqual(SubtitleParser.parse("WEBVTT\n\n00:01.000 --> 00:02.000 align:center\nHello").first?.start, 1)
    }
    func testSubtitleParserRejectsInvalidRangesAndStripsMarkup() {
        XCTAssertTrue(SubtitleParser.parse("00:00:05 --> 00:00:01\nInvalid").isEmpty)
        XCTAssertEqual(SubtitleParser.parse("00:00:01 --> 00:00:02\n<b>Hello</b>").first?.text, "Hello")
    }
    func testReadingBackupRoundTrip() throws {
        let backup = ReadingBackup(documents: [ReadingDocument(title: "Read", text: "Text")], originals: ["file": Data([1,2,3])])
        let restored = try JSONDecoder().decode(ReadingBackup.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(restored.documents, backup.documents); XCTAssertEqual(restored.originals["file"], Data([1,2,3]))
    }
    func testPermissionsAreScopedToSchemeHostAndPort() {
        XCTAssertEqual(SiteOrigin.key(url: URL(string: "https://EXAMPLE.com:443/path")), "https://example.com")
        XCTAssertNotEqual(SiteOrigin.key(url: URL(string: "https://example.com")), SiteOrigin.key(url: URL(string: "http://example.com")))
        XCTAssertNotEqual(SiteOrigin.key(url: URL(string: "https://example.com:8443")), SiteOrigin.key(url: URL(string: "https://example.com:9443")))
    }
    func testBareBingURLIsNotRewrittenBySelectedSearchEngine() {
        XCTAssertEqual(SearchProvider.google.resolve("www.bing.com/search?q=keep")?.host, "www.bing.com")
    }

}
