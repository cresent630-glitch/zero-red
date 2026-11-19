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
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
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
    /// 悬浮玻璃底栏：后退 / 前进 / 首页 / 页面 / 资料库。内容滚动到它下方，胶囊本身浮在底部安全区。
    private var dock: some View {
        GlassDock {
            GlassDockButton(symbol: "chevron.backward", label: library.text("后退", "Back"), identifier: "tool.chevron.left", isEnabled: session.record.canBack || session.engine().canGoBack) { session.move(-1) }
            GlassDockButton(symbol: "chevron.forward", label: library.text("前进", "Forward"), identifier: "tool.chevron.right", isEnabled: session.record.canForward || session.engine().canGoForward) { session.move(1) }
            GlassDockButton(symbol: "house", label: library.text("首页", "Home"), identifier: "tool.house") { session.home() }
            Button { Task { await session.capturePreview(for: session.selected); tabsVisible = true } } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "square.on.square").font(.system(size: 17, weight: .medium)).frame(width: ZeroRedTheme.control, height: ZeroRedTheme.control)
                    Text("\(session.visibleTabs.count)")
                        .font(.system(size: 9, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .padding(.horizontal, 3.5).padding(.vertical, 0.5)
                        .background(Color(uiColor: .label), in: Capsule())
                        .offset(x: -4, y: 5)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(library.text("页面管理", "Manage pages")).accessibilityIdentifier("tool.tabs")
            GlassDockButton(symbol: "books.vertical", label: library.text("资料库", "Library"), identifier: "tool.books.vertical") { libraryVisible = true }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
    }
    private func readCurrent() { Task { do { reader = try await session.engine().article() } catch { library.downloadError = error.localizedDescription } } }
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
                VStack(spacing: 8) {
                    address
                    if findVisible { findBar }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
                if engine.progress < 1 { ThinProgressBar(value: engine.progress).padding(.horizontal, 24).padding(.bottom, 4) }
                ZStack {
                    WebSurface(engine: engine).simultaneousGesture(TapGesture().onEnded { focused = false })
                    if let error = engine.error { errorCard(error) }
                }
            } else {
                startPage
            }
        }
        .onAppear { input = engine.url?.absoluteString ?? "" }
        .onChange(of: engine.url) { _, value in input = value?.absoluteString ?? "" }
        .onChange(of: session.selected) { _, _ in input = session.engine().url?.absoluteString ?? "" }
        .onChange(of: findText) { _, _ in find() }
        .sheet(item: $engine.dialog) { dialog in WebDialogView(dialog: dialog) { engine.dialog = nil } }
        .alert(library.text("提示", "Notice"), isPresented: Binding(get: { engine.notice != nil }, set: { if !$0 { engine.notice = nil } })) { Button(library.text("好", "OK")) { engine.notice = nil } } message: { Text(engine.notice ?? "") }
    }
    /// 起始页：字标 + 唯一的地址输入框 + 最近访问胶囊。保持极简，不加第二个输入框。
    private var startPage: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 24)
            ZeroRedWordmark(subtitle: session.privateMode ? library.text("无痕浏览", "Private browsing") : library.text("浏览 · 阅读 · 视频", "Browse · Read · Watch"))
            address.frame(maxWidth: ZeroRedTheme.maxContentWidth)
            recentChips
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .contentShape(Rectangle())
        .onTapGesture { focused = false }
    }
    private var recentChips: some View {
        let entries = Array(library.history.prefix(4))
        return Group {
            if entries.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 10) {
                    Text(library.text("最近访问", "Recent"))
                        .font(.caption2.weight(.semibold)).textCase(.uppercase).tracking(0.9)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 8) {
                        ForEach(entries) { entry in
                            Button { session.navigate(entry.url) } label: {
                                Label(entry.url.host ?? entry.title, systemImage: "globe")
                                    .font(.footnote.weight(.medium)).lineLimit(1)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .zeroRedGlass(Capsule(), interactive: true)
                        }
                    }
                }
                .frame(maxWidth: ZeroRedTheme.maxContentWidth)
                .padding(.top, 2)
            }
        }
    }
    private func errorCard(_ error: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.shield").font(.largeTitle).foregroundStyle(.secondary)
            Text(error).multilineTextAlignment(.center).font(.callout)
            Button(library.text("重试", "Retry")) { engine.webView.reload() }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        .padding(28)
        .frame(maxWidth: 320)
        .zeroRedGlass(RoundedRectangle(cornerRadius: ZeroRedTheme.contentRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).opacity(0.65))
    }
    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.footnote).foregroundStyle(.secondary)
            TextField(library.text("页内查找", "Find in page"), text: $findText).textInputAutocapitalization(.never).submitLabel(.search).onSubmit { find() }
            if !found { Image(systemName: "questionmark.circle").font(.footnote).foregroundStyle(.secondary) }
            Button { find(backwards: true) } label: { Image(systemName: "chevron.up").frame(width: 36, height: 36).contentShape(Rectangle()) }.accessibilityLabel(library.text("上一个", "Previous match"))
            Button { find() } label: { Image(systemName: "chevron.down").frame(width: 36, height: 36).contentShape(Rectangle()) }.accessibilityLabel(library.text("下一个", "Next match"))
            Button { findVisible = false } label: { Image(systemName: "xmark").frame(width: 36, height: 36).contentShape(Rectangle()) }.accessibilityLabel(library.text("关闭查找", "Close find"))
        }
        .buttonStyle(.plain).font(.callout)
        .padding(.horizontal, 14).frame(minHeight: 46)
        .zeroRedGlass(Capsule(), interactive: true)
    }
    private var address: some View {
        HStack(spacing: 8) {
            if engine.active {
                Button(action: siteAction) {
                    Image(systemName: engine.url?.scheme == "https" ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.secondary).frame(width: 28, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(library.text("网站安全与权限", "Website security and permissions"))
            } else {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            TextField(library.text("输入网址或搜索", "Search or enter website"), text: $input).keyboardType(.webSearch).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go).focused($focused).accessibilityIdentifier("addressInput")
                .onSubmit { submitAddress() }
            Button(action: submitAddress) { Image(systemName: "arrow.right.circle.fill").font(.title3).symbolRenderingMode(.hierarchical).frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(library.text("确认前往", "Go to address")).accessibilityIdentifier("addressGo").disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                } label: { Image(systemName: "ellipsis").frame(width: 34, height: 44).contentShape(Rectangle()) }.accessibilityLabel(library.text("网页操作", "Page actions")).accessibilityIdentifier("pageActions")
            }
        }
        .padding(.leading, engine.active ? 12 : 16).padding(.trailing, 6)
        .frame(minHeight: 52)
        .zeroRedGlass(Capsule(), interactive: true)
    }
    private func submitAddress() { guard let url = library.options.search.resolve(input) else { return }; focused = false; session.navigate(url) }
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
            Text(dialog.message).font(.body).textSelection(.enabled).multilineTextAlignment(.center)
            if dialog.kind == .input || dialog.kind == .credentials { TextField(dialog.kind == .credentials ? "用户名 / Username" : "", text: $text).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never) }
            if dialog.kind == .credentials { SecureField("密码 / Password", text: $password).textFieldStyle(.roundedBorder) }
            HStack { if dialog.kind != .alert { Button("取消 / Cancel") { respond(false) } }; Spacer(); GlassProminentButton(title: "好 / OK") { respond(true) } }
        }.padding(26).presentationDetents([.medium]).presentationBackground(.ultraThinMaterial).onAppear { text = dialog.initial }.onDisappear { if !answered { dialog.answer(false, text) } }
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
                VStack(spacing: 16) {
                    privateCard
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(session.visibleTabs) { tab in card(tab) }
                    }
                    if !session.privateMode && !session.recentlyClosed.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(library.text("最近关闭", "Recently closed")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                            ForEach(session.recentlyClosed) { tab in
                                Button { session.reopen(tab.id); dismiss() } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.uturn.backward").font(.footnote).foregroundStyle(.secondary)
                                        Text(tab.title).lineLimit(1)
                                        Spacer()
                                    }.padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
                                }.buttonStyle(.plain).zeroRedGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    if session.privateMode {
                        Button(library.text("结束无痕会话", "End private session"), role: .destructive) { session.endPrivateSession() }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule).padding(.top, 4)
                    }
                }.padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(library.text("页面", "Pages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { GlassToolbarButton(symbol: "plus", label: library.text("新建", "New")) { session.create(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { GlassProminentButton(title: library.text("完成", "Done")) { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    private var privateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(library.text("无痕浏览", "Private browsing"), isOn: Binding(get: { session.privateMode }, set: { enabled in
                if session.privateMode != enabled { session.togglePrivate() }
            }))
            if session.privateMode {
                Text(library.text("不记录历史；无痕标签不会恢复。主动保存的文件会保留。", "History is not recorded; private tabs are not restored. Files you explicitly save are retained."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zeroRedGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    private func card(_ tab: BrowserTabRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Button { session.select(tab.id); dismiss() } label: {
                    ZStack {
                        Color(uiColor: .secondarySystemBackground)
                        if let image = session.previews[tab.id] {
                            Image(uiImage: image).resizable().scaledToFill().accessibilityLabel(library.text("网页预览", "Page preview"))
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: tab.url == nil ? "magnifyingglass" : "globe").font(.title2).foregroundStyle(.secondary)
                                Text(tab.url?.host ?? library.text("起始页", "Start page")).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal, 8)
                            }
                        }
                    }.frame(height: 200).clipped().contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(tab.title + ", " + (tab.url?.host ?? library.text("起始页", "Start page"))).accessibilityValue(session.previews[tab.id] == nil ? library.text("暂无网页预览", "Page preview unavailable") : library.text("已载入网页预览", "Page preview available"))
                GlassCircleButton(symbol: "xmark", label: library.text("关闭页面", "Close page"), size: 30) { session.close(tab.id) }.padding(7)
            }
            HStack(spacing: 6) {
                Text(tab.title).font(.caption.weight(.medium)).lineLimit(1)
                Spacer(minLength: 2)
                if tab.id == session.selected { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.primary) }
            }.padding(.horizontal, 11).padding(.vertical, 10)
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tab.id == session.selected ? Color.primary : Color.clear, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}