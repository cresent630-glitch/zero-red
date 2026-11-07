import XCTest
@testable import ZeroRedCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class AddressTests: XCTestCase {
    func testEmptyInput() { for s in ["", " ", "\n\t"] { XCTAssertNil(AddressResolver.resolve(s)) } }
    func testHTTPSAndTrim() { XCTAssertEqual(AddressResolver.resolve("  https://example.com/a?q=中文  ")?.host, "example.com") }
    func testBareDomain() { XCTAssertEqual(AddressResolver.resolve("example.com/a")?.absoluteString, "https://example.com/a") }
    func testHostWithPort() { XCTAssertEqual(AddressResolver.resolve("localhost:8765/video")?.absoluteString, "https://localhost:8765/video") }
    func testIPv6() { XCTAssertEqual(AddressResolver.resolve("[::1]:8765")?.port, 8765) }
    func testSearchPreservesChineseAndQueryCharacters() {
        let term = "中文 & zero red # + ?"
        let url = AddressResolver.resolve(term)!
        XCTAssertEqual(url.host, "www.bing.com")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, term)
    }
    func testUnsupportedSchemeIsSearched() {
        for value in ["ftp://example.com/file", "file:///tmp/a.mp4", "javascript:alert(1)"] {
            XCTAssertEqual(AddressResolver.resolve(value)?.host, "www.bing.com", value)
        }
    }
    func testEmailIsSearched() { XCTAssertEqual(AddressResolver.resolve("hello@example.com")?.host, "www.bing.com") }
    func testURLWithCredentialsRejected() { XCTAssertNil(AddressResolver.webURL("https://user:password@example.com/video")) }
    func testInvalidPortRejected() { XCTAssertNil(AddressResolver.webURL("https://example.com:99999")) }
    func testURLWithSpacesRejected() { XCTAssertNil(AddressResolver.webURL("https://example.com/a b")) }
    func testExplicitHTTP() { XCTAssertEqual(AddressResolver.resolve("http://localhost:8765/")?.scheme, "http") }
}

final class LibraryTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDownWithError() throws { if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) } }
    func testBookmarkDeduplication() {
        var state = LibrarySnapshot()
        let url = URL(string: "https://example.com")!
        state.bookmark(url, title: "A"); state.bookmark(url, title: "B")
        XCTAssertEqual(state.bookmarks.count, 1)
    }
    func testHistoryUpdatesConsecutiveVisitTimeAndTitle() {
        var state = LibrarySnapshot()
        let url = URL(string: "https://example.com")!
        state.record(url, title: "A", now: Date(timeIntervalSince1970: 1))
        let id = state.history[0].id
        state.record(url, title: "B", now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.history[0].title, "B")
        XCTAssertEqual(state.history[0].date.timeIntervalSince1970, 2)
        XCTAssertEqual(state.history[0].id, id)
    }
    func testHistoryLimitAndOrdering() {
        var state = LibrarySnapshot()
        for n in 0..<1005 { state.record(URL(string: "https://example.com/\(n)")!, title: "\(n)") }
        XCTAssertEqual(state.history.count, 1000)
        XCTAssertEqual(state.history.first?.title, "1004")
        XCTAssertEqual(state.history.last?.title, "5")
    }
    func testHistoryNonconsecutiveRevisit() {
        var state = LibrarySnapshot()
        let a = URL(string: "https://example.com/a")!, b = URL(string: "https://example.com/b")!
        state.record(a, title: "A"); state.record(b, title: "B"); state.record(a, title: "A")
        XCTAssertEqual(state.history.map(\.url), [a, b, a])
    }
    func testLibraryRoundTripAndDeletion() throws {
        let repo = LibraryRepository(directory: directory)
        var state = LibrarySnapshot()
        state.bookmark(URL(string: "https://例子.中国")!, title: "中文")
        state.record(URL(string: "https://example.com")!, title: "English")
        state.videos = [CachedVideo(id: UUID(), title: "video", filename: "test.mp4")]
        try repo.save(state)
        XCTAssertEqual(try repo.load(), state)
        state.bookmarks.removeAll(); state.history.removeAll(); state.videos.removeAll()
        try repo.save(state)
        XCTAssertEqual(try repo.load(), LibrarySnapshot())
    }
    func testMissingManifestIsEmptyLibrary() throws { XCTAssertEqual(try LibraryRepository(directory: directory).load(), LibrarySnapshot()) }
    func testCorruptManifestIsReportedAndPreserved() throws {
        let repo = LibraryRepository(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let broken = Data("broken json".utf8)
        try broken.write(to: repo.manifest)
        XCTAssertThrowsError(try repo.load())
        XCTAssertEqual(try Data(contentsOf: repo.manifest), broken)
    }
    func testWriteFailureIsReported() throws {
        try Data("not a directory".utf8).write(to: directory)
        XCTAssertThrowsError(try LibraryRepository(directory: directory).save(LibrarySnapshot()))
    }
}

final class VideoPolicyTests: XCTestCase {
    func cookie(domain: String = ".example.com", path: String = "/", secure: Bool = false, expires: Date? = nil) -> HTTPCookie {
        var props: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: path, .name: "session", .value: "secret"]
        if secure { props[.secure] = "TRUE" }
        if let expires { props[.expires] = expires }
        return HTTPCookie(properties: props)!
    }
    func testRejectStreamingAndLocalSchemes() {
        for value in ["https://example.com/a.M3U8", "https://example.com/a.mpd", "blob:https://example.com/abc", "file:///tmp/a.mp4"] {
            XCTAssertFalse(VideoPolicy.supports(URL(string: value)!))
        }
    }
    func testAcceptDirectURLWithSignedQuery() { XCTAssertTrue(VideoPolicy.supports(URL(string: "https://cdn.example.com/video?id=1&token=secret")!)) }
    func testSupportedMIMETypes() throws {
        for mime in ["video/mp4", "VIDEO/MP4", "video/mp4; charset=binary", "video/x-m4v"] {
            XCTAssertEqual(try VideoPolicy.fileExtension(status: 200, mime: mime, byteCount: 12), "mp4")
        }
        XCTAssertEqual(try VideoPolicy.fileExtension(status: 200, mime: "video/quicktime", byteCount: 12), "mov")
    }
    func testRejectHTTPErrorAndPartialResponses() {
        for status in [204, 206, 301, 403, 404, 500] { XCTAssertThrowsError(try VideoPolicy.fileExtension(status: status, mime: "video/mp4", byteCount: 50)) }
    }
    func testRejectEmptyOrNonvideoResponses() {
        XCTAssertThrowsError(try VideoPolicy.fileExtension(status: 200, mime: "video/mp4", byteCount: 0))
        for mime in [nil, "text/html", "application/vnd.apple.mpegurl", "application/octet-stream"] {
            XCTAssertThrowsError(try VideoPolicy.fileExtension(status: 200, mime: mime, byteCount: 100))
        }
    }
    func testCookieDomainBoundary() {
        let c = cookie()
        XCTAssertEqual(VideoPolicy.cookies([c], for: URL(string: "https://cdn.example.com/v")!).count, 1)
        XCTAssertEqual(VideoPolicy.cookies([c], for: URL(string: "https://example.com/v")!).count, 1)
        for host in ["evilexample.com", "example.com.evil.test", "other.test"] {
            XCTAssertTrue(VideoPolicy.cookies([c], for: URL(string: "https://\(host)/")!).isEmpty)
        }
    }
    func testCookiePathBoundary() {
        let c = cookie(path: "/video")
        for path in ["/video", "/video/a.mp4"] { XCTAssertEqual(VideoPolicy.cookies([c], for: URL(string: "https://example.com\(path)")!).count, 1) }
        for path in ["/videos", "/videosecret", "/"] { XCTAssertTrue(VideoPolicy.cookies([c], for: URL(string: "https://example.com\(path)")!).isEmpty) }
    }
    func testSecureAndExpiredCookiesExcluded() {
        XCTAssertTrue(VideoPolicy.cookies([cookie(secure: true)], for: URL(string: "http://example.com/video")!).isEmpty)
        XCTAssertTrue(VideoPolicy.cookies([cookie(expires: Date(timeIntervalSince1970: 1))], for: URL(string: "https://example.com/")!).isEmpty)
    }
}
