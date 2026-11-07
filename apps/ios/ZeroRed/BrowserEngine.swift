import SwiftUI
import WebKit
import Combine
import CryptoKit

@MainActor
final class WebDialog: Identifiable {
    enum Kind { case alert, confirm, input, external, credentials }
    let id = UUID()
    var kind: Kind
    var message: String
    var initial: String
    var answer: (Bool, String) -> Void
    init(_ kind: Kind, _ message: String, initial: String = "", answer: @escaping (Bool, String) -> Void) {
        self.kind = kind; self.message = message; self.initial = initial; self.answer = answer
    }
}
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var engine: BrowserEngine?
    init(_ engine: BrowserEngine) { self.engine = engine }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak engine] in
            guard let body = message.body as? [String: Any] else { return }
            if body["type"] as? String == "scroll", let y = body["y"] as? Double, message.frameInfo.isMainFrame {
                engine?.onScroll?(y)
            } else if body["type"] as? String == "videoPlayback", let source = body["source"] as? String, let url = AddressResolver.webURL(source) {
                await engine?.requestVideoPlayback(url, position: body["position"] as? Double ?? 0, frame: message.frameInfo)
            }
        }
    }
}

@MainActor
final class BrowserEngine: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let isPrivate: Bool
    @Published var active = false
    @Published var url: URL?
    @Published var title = ""
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var notice: String?
    @Published var error: String?
    @Published var dialog: WebDialog?
    @Published var requestedVideo: PlayableItem?
    var onVisit: ((URL, String) -> Void)?
    var onScroll: ((Double) -> Void)?
    var onNewWindow: ((WKWebViewConfiguration) -> WKWebView?)?
    var onDownload: ((WKDownload, URL?) -> Void)?
    var options = BrowserOptions()
    var sitePolicy: (String) -> SitePolicy = { _ in SitePolicy() }
    var restoreScroll = 0.0
    private var observations: [NSKeyValueObservation] = []
    private var filterRevision = 0
    private var nativeVideoActive = false
    private var nativeVideoSource: URL?
    private var nativeVideoFrame: WKFrameInfo?
    init(isPrivate: Bool = false, dataStore: WKWebsiteDataStore? = nil, configuration provided: WKWebViewConfiguration? = nil) {
        self.isPrivate = isPrivate
        let configuration = provided ?? WKWebViewConfiguration()
        if let dataStore { configuration.websiteDataStore = dataStore }
        else if isPrivate { configuration.websiteDataStore = .nonPersistent() }
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        configuration.userContentController.add(WeakScriptHandler(self), name: "zeroRed")
        configuration.userContentController.addUserScript(WKUserScript(source: PageScripts.bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: PageScripts.videoPlaybackBridge, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in Task { @MainActor in self?.progress = view.estimatedProgress } },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in Task { @MainActor in self?.canGoBack = view.canGoBack } },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in Task { @MainActor in self?.canGoForward = view.canGoForward } }
        ]
    }
    func apply(_ options: BrowserOptions) {
        let reloadForDesktop = self.options.desktop != options.desktop
        self.options = options
        webView.pageZoom = min(2, max(0.5, options.zoom))
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = options.allowPopups || sitePolicy(SiteOrigin.key(url: url)).allowPopups
        updateBlocking()
        if reloadForDesktop && active { webView.reload() }
    }
    func updateBlocking() {
        filterRevision += 1; let revision = filterRevision
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        guard !sitePolicy(SiteOrigin.key(url: url)).disableBlocking else { return }
        let rules = ContentBlocking.rules(trackers: options.blockTrackers, ads: options.blockAds, extraDomains: options.extraBlockedDomains)
        guard !rules.isEmpty, let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) else { return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "zero-red-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), encodedContentRuleList: json) { [weak self] list, failure in
            Task { @MainActor in
                guard let self, self.filterRevision == revision else { return }
                if let list { controller.add(list) }
                if let failure { self.notice = failure.localizedDescription }
            }
        }
    }
    func open(_ target: URL) {
        guard AddressResolver.webURL(target.absoluteString) != nil else { return }
        error = nil; active = true; url = target; title = target.host ?? "zero red"
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = options.allowPopups || sitePolicy(SiteOrigin.key(url: target)).allowPopups
        updateBlocking(); webView.load(URLRequest(url: target))
    }
    func home() {
        active = false; error = nil; url = nil; title = ""
        webView.stopLoading(); webView.loadHTMLString("", baseURL: nil)
    }
    func suspendMedia() { webView.setAllMediaPlaybackSuspended(true, completionHandler: nil) }
    func resumeMedia() { webView.setAllMediaPlaybackSuspended(false, completionHandler: nil) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard active else { return }
        url = webView.url; title = webView.title ?? webView.url?.host ?? "zero red"
        if let url, AddressResolver.webURL(url.absoluteString) != nil { onVisit?(url, title) }
        if restoreScroll > 0 { let y = restoreScroll; restoreScroll = 0; webView.evaluateJavaScript("window.scrollTo(0,\(max(0, y)))", completionHandler: nil) }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard active else { return }; error = nil; url = webView.url; title = url?.host ?? "zero red"
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { if active { url = webView.url } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if active { webView.reload() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    private func report(_ failure: Error) {
        guard active else { return }; let nsError = failure as NSError
        if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled { error = failure.localizedDescription }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = options.desktop ? .desktop : .mobile
        guard let target = action.request.url else { decisionHandler(.cancel, preferences); return }
        let scheme = target.scheme?.lowercased() ?? ""
        if scheme == "file" { decisionHandler(.cancel, preferences); return }
        if action.shouldPerformDownload { decisionHandler(.download, preferences); return }
        if ["http", "https", "about", "blob"].contains(scheme) { decisionHandler(.allow, preferences); return }
        decisionHandler(.cancel, preferences)
        guard action.navigationType == .linkActivated, !["file", "javascript", "data"].contains(scheme), dialog == nil else { return }
        let destination = scheme == "bilibili" ? "哔哩哔哩 / Bilibili" : String(scheme.prefix(40))
        dialog = WebDialog(.external, "网页请求打开其他应用：\(destination)。\n取消可留在当前网页。\n\nThis page wants to open another app: \(destination).\nCancel to stay on this page.") { [weak self] allowed, _ in
            guard allowed else { return }
            UIApplication.shared.open(target, options: [:]) { [weak self] opened in
                guard !opened else { return }
                Task { @MainActor in
                    self?.notice = "未能打开对应应用，可能尚未安装。你可以继续浏览网页版。 / Could not open the app. It may not be installed. You can continue using the website."
                }
            }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        decisionHandler(!response.canShowMIMEType || disposition.lowercased().contains("attachment") ? .download : .allow)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { onDownload?(download, navigationAction.request.url) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { onDownload?(download, navigationResponse.response.url) }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil else { return nil }
        if action.navigationType == .linkActivated || options.allowPopups || sitePolicy(SiteOrigin.key(url: url)).allowPopups { return onNewWindow?(configuration) }
        notice = "弹窗已阻止。可在网站设置中允许。 / Popup blocked. Allow popups in site settings."
        return nil
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let policy = sitePolicy(SiteOrigin.key(scheme: origin.protocol, host: origin.host, port: origin.port))
        let values: [PermissionChoice] = type == .camera ? [policy.camera] : type == .microphone ? [policy.microphone] : [policy.camera, policy.microphone]
        decisionHandler(values.contains(.deny) ? .deny : values.allSatisfy { $0 == .allow } ? .grant : .prompt)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard dialog == nil else { completionHandler(); return }
        dialog = WebDialog(.alert, message) { _, _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard dialog == nil else { completionHandler(false); return }
        dialog = WebDialog(.confirm, message) { accepted, _ in completionHandler(accepted) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard dialog == nil else { completionHandler(nil); return }
        dialog = WebDialog(.input, prompt, initial: defaultText ?? "") { accepted, text in completionHandler(accepted ? text : nil) }
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest].contains(method), challenge.previousFailureCount < 3, dialog == nil else { completionHandler(.performDefaultHandling, nil); return }
        dialog = WebDialog(.credentials, challenge.protectionSpace.host, initial: challenge.proposedCredential?.user ?? "") { [isPrivate] accepted, value in
            guard accepted, let data = value.data(using: .utf8), let parts = try? JSONDecoder().decode([String].self, from: data), parts.count == 2 else { completionHandler(.cancelAuthenticationChallenge, nil); return }
            completionHandler(.useCredential, URLCredential(user: parts[0], password: parts[1], persistence: isPrivate ? .none : .forSession))
        }
    }
    func playerItem(_ source: URL, position: Double = 0, frame: WKFrameInfo? = nil) async -> PlayableItem {
        nativeVideoActive = true
        nativeVideoSource = source
        nativeVideoFrame = frame
        let storedCookies = await cookies()
        _ = try? await webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(v => v.pause())")
        return PlayableItem(url: source, title: title, cookies: storedCookies, startTime: position.isFinite ? max(0, position) : 0, onClose: { [weak self] time in
            self?.finishNativePlayback(position: time)
        })
    }
    func finishNativePlayback(position: Double? = nil) {
        nativeVideoActive = false
        requestedVideo = nil
        resumeMedia()
        let source = nativeVideoSource?.absoluteString ?? ""
        let frame = nativeVideoFrame
        var arguments: [String: Any] = ["source": source, "position": NSNull()]
        if let position, position.isFinite { arguments["position"] = max(0, position) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.webView.callAsyncJavaScript("window.__zeroRedReleaseVideo?.(source, position)", arguments: arguments, in: frame, contentWorld: .page)
        }
    }
    func requestVideoPlayback(_ source: URL, position: Double, frame: WKFrameInfo?) async {
        guard !nativeVideoActive, requestedVideo == nil else { return }
        requestedVideo = await playerItem(source, position: position, frame: frame)
    }
    func fullscreenVideo() async -> String {
        let result = (try? await webView.callAsyncJavaScript(PageScripts.fullscreenVideo, arguments: [:], in: nil, contentWorld: .page)) as? String ?? "unsupported"
        if webView.fullscreenState == .enteringFullscreen || webView.fullscreenState == .inFullscreen { return "opened" }
        return result
    }
    func cookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
    func videoLinks() async -> [URL] {
        guard let values = try? await webView.evaluateJavaScript(PageScripts.videoLinks) as? [String] else { return [] }
        return values.compactMap(URL.init(string:))
    }
    func article() async throws -> ReadingDocument {
        guard let value = try await webView.callAsyncJavaScript(PageScripts.reader, arguments: [:], in: nil, contentWorld: .page) as? [String: String], let text = value["text"], !text.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return ReadingDocument(title: value["title"] ?? title, text: text, source: value["source"] ?? url?.absoluteString ?? "", format: "html")
    }
    func find(_ text: String, backwards: Bool = false, completion: @escaping (Bool) -> Void) {
        let config = WKFindConfiguration(); config.backwards = backwards; config.wraps = true
        webView.find(text, configuration: config) { completion($0.matchFound) }
    }
}
struct WebSurface: UIViewRepresentable {
    let engine: BrowserEngine
    func makeUIView(context: Context) -> WKWebView { engine.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
