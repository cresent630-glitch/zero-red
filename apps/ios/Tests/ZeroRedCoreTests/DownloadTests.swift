import XCTest
@testable import ZeroRedCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class DownloadTests: XCTestCase {
    var directory: URL!
    var base: URL!
    override func setUpWithError() throws {
        guard let address = ProcessInfo.processInfo.environment["ZERO_RED_FIXTURE_URL"], let url = URL(string: address) else {
            throw XCTSkip("Start scripts/fixture_server.py and set ZERO_RED_FIXTURE_URL to enable real HTTP download tests.")
        }
        base = url
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func testDownloadsRealMP4AndRetainsLocalBytes() async throws {
        let video = try await VideoDownloader().download(base.appendingPathComponent("sample.mp4"), to: directory)
        let local = directory.appendingPathComponent(video.filename)
        let bytes = try Data(contentsOf: local)
        XCTAssertGreaterThan(bytes.count, 1000)
        XCTAssertEqual(String(decoding: bytes[4..<8], as: UTF8.self), "ftyp")
        // Read file again without making another URLSession request.
        XCTAssertEqual(try Data(contentsOf: local), bytes)
    }
    func testFollowsSameHostRedirect() async throws {
        let video = try await VideoDownloader().download(base.appendingPathComponent("redirect"), to: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(video.filename).path))
    }
    func testSendsOnlyMatchingCookies() async throws {
        let cookie = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "session", .value: "secret"])!
        let video = try await VideoDownloader().download(base.appendingPathComponent("cookie.mp4"), to: directory, cookies: [cookie])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(video.filename).path))
    }
    func testCrossHostRedirectDropsCookiesAndReferer() async throws {
        let cookie = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "session", .value: "secret"])!
        let video = try await VideoDownloader().download(base.appendingPathComponent("redirect-other"), to: directory, cookies: [cookie], referer: URL(string: "http://127.0.0.1/private?token=secret"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(video.filename).path))
    }
    func testRefererIsOriginOnly() async throws {
        let video = try await VideoDownloader().download(base.appendingPathComponent("referer.mp4"), to: directory, referer: URL(string: "http://example.com/private?token=secret"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(video.filename).path))
    }
    func testHTTPSRefererNotLeakedToHTTP() async throws {
        do {
            _ = try await VideoDownloader().download(base.appendingPathComponent("referer.mp4"), to: directory, referer: URL(string: "https://example.com/private?token=secret"))
            XCTFail("HTTPS Referer must be omitted for HTTP")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
    }
    func testRejectedResponsesLeaveNoCachedFiles() async throws {
        for name in ["empty.mp4", "partial.mp4", "error.mp4", "fake.mp4", "missing.mp4"] {
            do {
                _ = try await VideoDownloader().download(base.appendingPathComponent(name), to: directory)
                XCTFail("Unexpected success for \(name)")
            } catch {
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), name)
            }
        }
    }
    func testWriteFailureIsReported() async throws {
        try Data("not a directory".utf8).write(to: directory)
        do {
            _ = try await VideoDownloader().download(base.appendingPathComponent("sample.mp4"), to: directory)
            XCTFail("Expected storage error")
        } catch { XCTAssertEqual(try Data(contentsOf: directory), Data("not a directory".utf8)) }
    }
}
