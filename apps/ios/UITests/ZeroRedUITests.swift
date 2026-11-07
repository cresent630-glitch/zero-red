import XCTest

@MainActor
final class ZeroRedUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-library", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }
    private func library() {
        let button = app.buttons["tool.books.vertical"]
        button.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }
    private func navigateToFixture() {
        let input = app.textFields["addressInput"]
        input.tap(); input.typeText("http://localhost:8765/\n")
        XCTAssertTrue(app.webViews.staticTexts["Zero Red Test Page"].firstMatch.waitForExistence(timeout: 15))
    }
    func testEnglishMinimalHome() {
        XCTAssertEqual(app.textFields.count, 1)
        XCTAssertEqual(app.textFields["addressInput"].placeholderValue, "Search or enter website")
        XCTAssertTrue(app.buttons["tool.house"].exists)
        XCTAssertEqual(app.webViews.count, 0)
    }
    private func openVideoControls(_ path: String) {
        let input = app.textFields["addressInput"]
        input.tap(); input.typeText("http://localhost:8765/\(path)\n")
        XCTAssertTrue(app.webViews.buttons["Play in page"].firstMatch.waitForExistence(timeout: 15))
    }
    private func assertFullscreenCacheButton() {
        let surface = app.otherElements["offlinePlayer"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10), app.debugDescription)
        if !app.buttons["Save current video"].exists { surface.tap() }
        XCTAssertTrue(app.buttons["Save current video"].exists, app.debugDescription)
    }
    func testWebpagePlayKeepsFullscreenCacheButton() {
        openVideoControls("video-controls.html")
        app.webViews.buttons["Play in page"].firstMatch.tap()
        assertFullscreenCacheButton()
        app.buttons["Save current video"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 20), app.debugDescription)
    }
    func testWebpageFullscreenKeepsCacheButton() {
        openVideoControls("video-controls.html")
        app.webViews.buttons["Fullscreen in page"].firstMatch.tap()
        assertFullscreenCacheButton()
    }
    func testEmbeddedWebpagePlayKeepsCacheButton() {
        openVideoControls("video-frame.html")
        app.webViews.buttons["Play in page"].firstMatch.tap()
        assertFullscreenCacheButton()
    }
    func testWebVideoOpensFullscreenPlayer() {
        navigateToFixture()
        app.buttons["videoFullscreen"].tap()
        let surface = app.otherElements["offlinePlayer"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10), app.debugDescription)
        if !app.buttons["Save current video"].exists { surface.tap() }
        XCTAssertTrue(app.buttons["Save current video"].exists, app.debugDescription)
        app.buttons["Save current video"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.textFields["addressInput"].waitForExistence(timeout: 5))
        library()
        app.buttons["Videos"].tap()
        XCTAssertTrue(app.buttons["offlineVideo.sample.mp4"].waitForExistence(timeout: 5))
    }
    func testChineseMinimalHome() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-reset-library", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertEqual(app.textFields["addressInput"].placeholderValue, "输入网址或搜索")
        libraryChinese()
    }
    private func libraryChinese() {
        app.buttons["tool.books.vertical"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["历史"].exists)
        XCTAssertTrue(app.buttons["视频"].exists)
    }
    func testBookmarkAndHistorySurviveRelaunch() {
        navigateToFixture()
        library()
        app.buttons["Bookmark this page"].tap()
        let row = app.buttons["page.http://localhost:8765/"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.buttons["History"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-library" }
        app.launch()
        library()
        XCTAssertTrue(app.buttons["page.http://localhost:8765/"].waitForExistence(timeout: 5))
    }
    func testVideoDownloadPersistsAndPlayerOpens() async throws {
        var enable = URLRequest(url: URL(string: "http://localhost:8765/test/offline-media/enable")!)
        enable.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: enable)
        library()
        app.buttons["Videos"].tap()
        app.textFields["videoURLInput"].tap()
        app.textFields["videoURLInput"].typeText("http://localhost:8765/offline-sample.mp4")
        app.buttons["downloadVideo"].tap()
        XCTAssertTrue(app.buttons["offlineVideo.offline-sample.mp4"].waitForExistence(timeout: 20))
        var disable = URLRequest(url: URL(string: "http://localhost:8765/test/offline-media/disable")!)
        disable.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: disable)
        let (_, unavailable) = try await URLSession.shared.data(from: URL(string: "http://localhost:8765/offline-sample.mp4")!)
        XCTAssertEqual((unavailable as? HTTPURLResponse)?.statusCode, 503)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset-library" }
        app.launch()
        library(); app.buttons["Videos"].tap()
        let video = app.buttons["offlineVideo.offline-sample.mp4"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.tap()
        XCTAssertTrue(app.otherElements["offlinePlayer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "(?!0:00 /)[0-9]+:[0-9]{2} / [0-9]+:[0-9]{2}")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }
    func testDownloadErrorVisibleInLibrary() {
        library(); app.buttons["Videos"].tap()
        app.textFields["videoURLInput"].tap()
        app.textFields["videoURLInput"].typeText("http://localhost:8765/fake.mp4")
        app.buttons["downloadVideo"].tap()
        XCTAssertTrue(app.alerts["Notice"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["fake.mp4"].exists)
    }
}

@MainActor
final class SessionUITests: XCTestCase {
    func testNewTabsAndRecentlyClosed() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-reset-library", "-AppleLanguages", "(en)"]; app.launch()
        app.buttons["Manage pages"].tap(); app.buttons["New"].tap()
        app.buttons["Manage pages"].tap()
        XCTAssertTrue(app.buttons["Close page"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close page"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Recently closed"].waitForExistence(timeout: 5))
    }
    func testPrivateTabsAreNotRestored() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-reset-library", "-AppleLanguages", "(en)"]; app.launch()
        app.buttons["Manage pages"].tap()
        let privateSwitch = app.switches["Private browsing"]
        privateSwitch.switches.firstMatch.tap()
        XCTAssertEqual(privateSwitch.value as? String, "1", app.debugDescription)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Private browsing"].waitForExistence(timeout: 5), app.debugDescription)
        app.terminate(); app.launchArguments.removeAll { $0 == "-reset-library" }; app.launch()
        XCTAssertFalse(app.staticTexts["Private browsing"].exists)
    }
}
