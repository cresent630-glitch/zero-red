import SwiftUI
import WebKit

@MainActor
struct BrowserView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reading: ReadingLibrary
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = BrowserSession()
    @State private var libraryVisible = false
    @State private var tabsVisible = false
    @State private var websiteVisible = false
    @State private var findVisible = false
    @State private var reader: ReadingDocument?
    @State private var player: PlayableItem?
    @State private var shared: SharedItems?
    var body: some View {
        VStack(spacing: 0) {
            BrowserPage(engine: session.engine(), session: session, findVisible: $findVisible, siteAction: { websiteVisible = true }, readAction: readCurrent, shareAction: { if let url = session.engine().url { shared = SharedItems(items: [url]) } }, videoAction: {
                Task {
                    let engine = session.engine()
                    if let url = await engine.videoLinks().first {
                        player = await engine.playerItem(url)
                    } else {
                        library.downloadError = library.text("当前网页尚未提供可播放的视频。请先在网页内开始播放；若网页要求打开客户端，请尝试桌面网站。", "No playable video is available yet. Start playback on the page first. If the site requires its app, try Desktop website.")
                    }
                }
            })
            HStack {
                control("chevron.left", library.text("后退", "Back")) { session.move(-1) }.disabled(!session.record.canBack && !session.engine().canGoBack)
                Spacer(); control("chevron.right", library.text("前进", "Forward")) { session.move(1) }.disabled(!session.record.canForward && !session.engine().canGoForward)
                Spacer(); control("house", library.text("首页", "Home")) { session.home() }
                Spacer(); Button { Task { await session.capturePreview(for: session.selected); tabsVisible = true } } label: { Text("\(session.visibleTabs.count)").font(.caption.monospacedDigit()).frame(width: 24, height: 25).overlay(RoundedRectangle(cornerRadius: 5).stroke(lineWidth: 1.4)).frame(width: 44, height: 44) }.accessibilityLabel(library.text("页面管理", "Manage pages"))
                Spacer(); control("books.vertical", library.text("资料库", "Library")) { libraryVisible = true }
            }.padding(.horizontal, 18).padding(.vertical, 7).background(.bar)
        }
        .background(Color(uiColor: .systemBackground))
        .overlay { if session.privateMode && scenePhase != .active { Color(uiColor: .systemBackground).overlay(Image(systemName: "eye.slash").font(.largeTitle)) } }
        .preferredColorScheme(library.options.theme == "dark" ? .dark : library.options.theme == "light" ? .light : nil)
        .task { session.attach(library) }
        .onReceive(session.engine().$requestedVideo) { item in
            guard let item else { return }
            session.engine().requestedVideo = nil
            guard player == nil, !libraryVisible else { item.onClose?(item.startTime); return }
            player = item
        }
        .onOpenURL { url in
            if url.isFileURL { do { reader = try reading.importFile(url) } catch { library.downloadError = error.localizedDescription } }
            else if AddressResolver.webURL(url.absoluteString) != nil { session.navigate(url) }
            else if url.scheme == "zerored", let input = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value, let target = AddressResolver.webURL(input) { session.navigate(target) }
        }
        .onChange(of: library.options) { _, _ in session.applyOptions() }
        .onChange(of: library.sitePolicies) { _, _ in session.applyOptions() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { session.background() } else if phase == .active { session.engine().resumeMedia() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in session.handleMemoryPressure() }
        .sheet(isPresented: $libraryVisible) { LibraryView(engine: session.engine(), session: session) { url in session.navigate(url); libraryVisible = false } }
        .sheet(isPresented: $tabsVisible) { TabOverview(session: session) }
        .sheet(isPresented: $websiteVisible) { SiteSettings(engine: session.engine()) }
        .fullScreenCover(item: $reader) { ReaderView(document: $0) }
        .fullScreenCover(item: $player, onDismiss: { player = nil; session.engine().finishNativePlayback() }) { NativePlayer(item: $0) }
        .sheet(item: $shared) { ShareSheet(items: $0.items) }
        .alert(library.text("提示", "Notice"), isPresented: Binding(get: { library.downloadError != nil && !libraryVisible }, set: { if !$0 { library.downloadError = nil } })) { Button(library.text("好", "OK")) { library.downloadError = nil } } message: { Text(library.downloadError ?? "") }
    }
    private func readCurrent() { Task { do { reader = try await session.engine().article() } catch { library.downloadError = error.localizedDescription } } }
    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(label).accessibilityIdentifier("tool." + symbol) }
}
@MainActor
private struct BrowserPage: View {
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var session: BrowserSession
    @Binding var findVisible: Bool
    var siteAction: () -> Void
    var readAction: () -> Void
    var shareAction: () -> Void
    var videoAction: () -> Void
    @State private var input = ""
    @State private var findText = ""
    @State private var found = true
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if engine.active {
                address.padding(.horizontal, 16).padding(.vertical, 10)
                if findVisible {
                    HStack {
                        TextField(library.text("页内查找", "Find in page"), text: $findText).textInputAutocapitalization(.never).onSubmit { find() }
                        if !found { Image(systemName: "magnifyingglass").foregroundStyle(.secondary) }
                        Button { find(backwards: true) } label: { Image(systemName: "chevron.up").frame(width: 40, height: 40) }.accessibilityLabel(library.text("上一个", "Previous match"))
                        Button { find() } label: { Image(systemName: "chevron.down").frame(width: 40, height: 40) }.accessibilityLabel(library.text("下一个", "Next match"))
                        Button { findVisible = false } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }.accessibilityLabel(library.text("关闭查找", "Close find"))
                    }.padding(.horizontal, 16)
                }
                if engine.progress < 1 { ProgressView(value: engine.progress).tint(.primary) }
                ZStack {
                    WebSurface(engine: engine)
                    if let error = engine.error { VStack(spacing: 18) { Image(systemName: "exclamationmark.shield").font(.largeTitle); Text(error).multilineTextAlignment(.center); Button(library.text("重试", "Retry")) { engine.webView.reload() } }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(uiColor: .systemBackground)) }
                }
            } else {
                Spacer()
                if session.privateMode { Label(library.text("无痕浏览", "Private browsing"), systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary).padding(.bottom, 18) }
                address.padding(.horizontal, 30).frame(maxWidth: 560)
                Spacer()
            }
        }
        .onAppear { input = engine.url?.absoluteString ?? "" }
        .onChange(of: engine.url) { _, value in input = value?.absoluteString ?? "" }
        .onChange(of: session.selected) { _, _ in input = session.engine().url?.absoluteString ?? "" }
        .onChange(of: findText) { _, _ in find() }
        .sheet(item: $engine.dialog) { dialog in WebDialogView(dialog: dialog) { engine.dialog = nil } }
        .alert(library.text("提示", "Notice"), isPresented: Binding(get: { engine.notice != nil }, set: { if !$0 { engine.notice = nil } })) { Button(library.text("好", "OK")) { engine.notice = nil } } message: { Text(engine.notice ?? "") }
    }
    private var address: some View {
        HStack(spacing: 10) {
            if engine.active {
                Button(action: siteAction) { Image(systemName: engine.url?.scheme == "https" ? "lock" : "exclamationmark.triangle").foregroundStyle(.secondary).frame(width: 28, height: 44) }.accessibilityLabel(library.text("网站安全与权限", "Website security and permissions"))
            } else { Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true) }
            TextField(library.text("输入网址或搜索", "Search or enter website"), text: $input).keyboardType(.webSearch).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go).focused($focused).accessibilityIdentifier("addressInput")
                .onSubmit { if let url = library.options.search.resolve(input) { focused = false; session.navigate(url) } }
            if engine.active {
                Menu {
                    Button(library.text("刷新", "Reload"), systemImage: "arrow.clockwise") { engine.webView.reload() }
                    Button(library.text("分享网页", "Share page"), systemImage: "square.and.arrow.up", action: shareAction)
                    Button(library.text("复制链接", "Copy link"), systemImage: "link") { UIPasteboard.general.url = engine.url }
                    Button(library.text("阅读模式 / 翻译正文", "Reader / translate text"), systemImage: "doc.text", action: readAction)
                    Button(library.text("页内查找", "Find in page"), systemImage: "magnifyingglass") { findVisible = true }
                    Button(library.text("视频全屏播放", "Play video fullscreen"), systemImage: "play.rectangle", action: videoAction)
                    Toggle(library.text("桌面网站", "Desktop website"), isOn: $library.options.desktop)
                    Picker(library.text("页面缩放", "Page zoom"), selection: $library.options.zoom) { ForEach([0.75,1,1.25,1.5,2], id: \.self) { value in Text("\(Int(value*100))%").tag(value) } }
                    Button(library.text("在系统浏览器打开", "Open in system browser"), systemImage: "safari") { if let url = engine.url { UIApplication.shared.open(url) } }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44) }.accessibilityLabel(library.text("网页操作", "Page actions")).accessibilityIdentifier("pageActions")
            }
        }.padding(.horizontal, 14).frame(minHeight: 56).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17))
    }
    private func find(backwards: Bool = false) { guard !findText.isEmpty else { return }; engine.find(findText, backwards: backwards) { found = $0 } }
}
@MainActor
private struct WebDialogView: View {
    let dialog: WebDialog
    var closed: () -> Void
    @State private var text = ""
    @State private var answered = false
    @State private var password = ""
    var body: some View {
        VStack(spacing: 20) {
            Text(dialog.message).font(.body).textSelection(.enabled)
            if dialog.kind == .input || dialog.kind == .credentials { TextField(dialog.kind == .credentials ? "用户名 / Username" : "", text: $text).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never) }
            if dialog.kind == .credentials { SecureField("密码 / Password", text: $password).textFieldStyle(.roundedBorder) }
            HStack { if dialog.kind != .alert { Button("取消 / Cancel") { respond(false) } }; Spacer(); Button("好 / OK") { respond(true) } }
        }.padding(26).presentationDetents([.medium]).onAppear { text = dialog.initial }.onDisappear { if !answered { dialog.answer(false, text) } }
    }
    private func respond(_ value: Bool) { answered = true; let response = dialog.kind == .credentials ? String(data: (try? JSONEncoder().encode([text, password])) ?? Data(), encoding: .utf8) ?? "" : text; dialog.answer(value, response); closed() }
}
@MainActor
struct TabOverview: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: BrowserSession
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Toggle(library.text("无痕浏览", "Private browsing"), isOn: Binding(get: { session.privateMode }, set: { enabled in
                        if session.privateMode != enabled { session.togglePrivate() }
                    }))
                    if session.privateMode { Text(library.text("不记录历史；无痕标签不会恢复。主动保存的文件会保留。", "History is not recorded; private tabs are not restored. Files you explicitly save are retained.")).font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(session.visibleTabs) { tab in
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack(alignment: .topTrailing) {
                                Button { session.select(tab.id); dismiss() } label: {
                                    ZStack {
                                        Color(uiColor: .secondarySystemBackground)
                                        if let image = session.previews[tab.id] { Image(uiImage: image).resizable().scaledToFill().accessibilityLabel(library.text("网页预览", "Page preview")) }
                                        else { VStack(spacing: 12) { Image(systemName: tab.url == nil ? "magnifyingglass" : "globe").font(.largeTitle); Text(tab.url?.host ?? library.text("起始页", "Start page")).font(.caption).lineLimit(2) }.padding() }
                                    }.frame(height: 210).clipped().contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel(tab.title + ", " + (tab.url?.host ?? library.text("起始页", "Start page"))).accessibilityValue(session.previews[tab.id] == nil ? library.text("暂无网页预览", "Page preview unavailable") : library.text("已载入网页预览", "Page preview available"))
                                Button { session.close(tab.id) } label: { Image(systemName: "xmark").font(.caption.bold()).frame(width: 36, height: 36).background(.regularMaterial, in: Circle()) }.buttonStyle(.plain).padding(6).accessibilityLabel(library.text("关闭页面", "Close page"))
                            }
                            HStack { Text(tab.title).font(.caption).lineLimit(1); Spacer(minLength: 2); if tab.id == session.selected { Image(systemName: "checkmark.circle.fill").font(.caption) } }.padding(10)
                        }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 15)).clipShape(RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(tab.id == session.selected ? Color.primary : Color.clear, lineWidth: 2))
                    }
                }
                if !session.privateMode && !session.recentlyClosed.isEmpty { Section(library.text("最近关闭", "Recently closed")) { ForEach(session.recentlyClosed) { tab in Button(tab.title) { session.reopen(tab.id); dismiss() } } } }
                if session.privateMode { Button(library.text("结束无痕会话", "End private session"), role: .destructive) { session.endPrivateSession() } }
                }.padding()
            }.navigationTitle(library.text("页面", "Pages"))
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(library.text("新建", "New"), systemImage: "plus") { session.create(); dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(library.text("完成", "Done")) { dismiss() } } }
        }
    }
}
