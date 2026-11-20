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
        // 托管运行器上首次加载本地 fixture 偶尔超过 15 秒：先给足时间，
        // 失败后回首页清空地址再重试一次，避免把网络抖动记成产品缺陷。
        let input = app.textFields["addressInput"]
        input.tap(); input.typeText("http://localhost:8765/\n")
        if app.webViews.staticTexts["Zero Red Test Page"].firstMatch.waitForExistence(timeout: 25) { return }
        app.buttons["tool.house"].tap()
        let retry = app.textFields["addressInput"]
        retry.tap(); retry.typeText("http://localhost:8765/\n")
        XCTAssertTrue(app.webViews.staticTexts["Zero Red Test Page"].firstMatch.waitForExistence(timeout: 25))
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
        let surface = app.otherElements["offlinePlayer"].firstMatch
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
    func testWebpageVideoCanReopenThreeTimes() {
        openVideoControls("video-controls.html")
        for _ in 0..<3 {
            app.webViews.buttons["Play in page"].firstMatch.tap()
            assertFullscreenCacheButton()
            app.buttons["Close"].tap()
            XCTAssertTrue(app.webViews.buttons["Play in page"].firstMatch.waitForExistence(timeout: 5))
        }
    }
    func testTappingVideoPausesAndResumes() {
        openVideoControls("video-controls.html")
        app.webViews.buttons["Play in page"].firstMatch.tap()
        let surface = app.otherElements["offlinePlayer"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let notice = app.alerts["Notice"]
        XCTAssertFalse(notice.exists, notice.debugDescription)
        for _ in 0..<2 {
            if !app.buttons["Play or pause"].exists { surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            let control = app.buttons["Play or pause"]
            let old = control.value as? String
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", old ?? ""), object: control)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed, app.debugDescription)
        }
    }
    func testReaderIsFullscreenAndIncludesAllVisibleSections() {
        let input = app.textFields["addressInput"]
        input.tap(); input.typeText("http://localhost:8765/reader-complete.html\n")
        XCTAssertTrue(app.webViews.staticTexts["First article"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["pageActions"].tap()
        app.buttons["Reader / translate text"].tap()
        XCTAssertTrue(app.buttons["Save current text"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.sheets.count, 0)
        let content = app.scrollViews["readerContent"].firstMatch
        XCTAssertTrue(content.exists)
        for text in ["First article body sentinel", "Second article body sentinel", "Text outside article sentinel", "Shadow text sentinel", "Dynamic text sentinel", "Embedded text sentinel", "Visible page introduction", "Visible page conclusion"] {
            XCTAssertTrue(content.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists, text)
        }
        XCTAssertFalse(content.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Hidden text sentinel")).firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Fullscreen-reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["readerBack"].tap()
        XCTAssertTrue(app.buttons["pageActions"].waitForExistence(timeout: 5))
    }
    func testPageOverviewHasRealPreview() {
        navigateToFixture()
        app.buttons["Manage pages"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", "Page preview available")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Close page"].firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Page-preview-grid"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testWebVideoOpensFullscreenPlayer() {
        navigateToFixture()
        XCTAssertFalse(app.buttons["videoFullscreen"].exists)
        app.buttons["pageActions"].tap()
        app.buttons["Play video fullscreen"].tap()
        let surface = app.otherElements["offlinePlayer"].firstMatch
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
    /// 视觉验收用：依次走首页、网页、页面总览、资料库、阅读与设置，各留一张截图。
    /// 工作流把附件导出成 PNG，供人工核对 iOS 27 Liquid Glass 外观。
    /// 输入地址前先清空：新标签页可能沿用上一个标签的 URL，直接 typeText 会把它拼成
    /// "http://host/http://host/..." 这样的无效地址，页面自然加载不出来。
    private func enterAddress(_ value: String) {
        let input = app.textFields["addressInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        if let current = input.value as? String, !current.isEmpty, current != input.placeholderValue {
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4))
        }
        input.typeText(value + "\n")
    }
    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testDesignScreenshots() {
        capture("01-home")
        navigateToFixture()
        capture("02-browser")
        app.buttons["Manage pages"].tap()
        XCTAssertTrue(app.buttons["Close page"].firstMatch.waitForExistence(timeout: 5))
        capture("03-pages")
        app.buttons["New"].tap()
        enterAddress("http://localhost:8765/reader-complete.html")
        XCTAssertTrue(app.webViews.staticTexts["First article"].firstMatch.waitForExistence(timeout: 25))
        library()
        capture("04-library-bookmarks")
        app.buttons["History"].tap()
        capture("05-library-history")
        app.buttons["Done"].tap()
        app.buttons["pageActions"].tap()
        app.buttons["Reader / translate text"].tap()
        XCTAssertTrue(app.buttons["Save current text"].waitForExistence(timeout: 10))
        capture("06-reader")
        app.buttons["readerBack"].tap()
        XCTAssertTrue(app.buttons["pageActions"].waitForExistence(timeout: 5))
        library()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        capture("07-settings")
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
