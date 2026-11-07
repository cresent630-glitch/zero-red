import SwiftUI
import WebKit

@MainActor
final class BrowserSession: ObservableObject {
    @Published var tabs: [BrowserTabRecord] = []
    @Published var selected = UUID()
    @Published var privateMode = false
    @Published var recentlyClosed: [BrowserTabRecord] = []
    private var engines: [UUID: BrowserEngine] = [:]
    private var privateStore = WKWebsiteDataStore.nonPersistent()
    private weak var library: LibraryStore?
    private var pendingNavigations: Set<UUID> = []
    private var saving: Task<Void, Never>?
    private var file: URL { AppPaths.directory.appendingPathComponent("session.json") }
    var visibleTabs: [BrowserTabRecord] { tabs.filter { $0.isPrivate == privateMode } }
    var record: BrowserTabRecord { tabs.first(where: { $0.id == selected }) ?? BrowserTabRecord() }
    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(BrowserSessionSnapshot.self, from: data) {
            let clean = BrowserSessionSnapshot(tabs: saved.tabs, selected: saved.selected, recentlyClosed: saved.recentlyClosed)
            tabs = clean.tabs; recentlyClosed = clean.recentlyClosed; selected = clean.selected ?? UUID()
        }
        if tabs.isEmpty { let tab = BrowserTabRecord(); tabs = [tab]; selected = tab.id }
        if !tabs.contains(where: { $0.id == selected }) { selected = tabs[0].id }
    }
    func attach(_ library: LibraryStore) { self.library = library; applyOptions() }
    func engine(for id: UUID? = nil) -> BrowserEngine {
        let id = id ?? selected
        if let engine = engines[id] { return engine }
        let tab = tabs.first(where: { $0.id == id }) ?? BrowserTabRecord()
        let engine = makeEngine(id: id, isPrivate: tab.isPrivate)
        engines[id] = engine
        if let url = tab.url { engine.restoreScroll = tab.scrollY; engine.open(url) }
        trimEngines(); return engine
    }
    private func makeEngine(id: UUID, isPrivate: Bool, configuration: WKWebViewConfiguration? = nil) -> BrowserEngine {
        let engine = BrowserEngine(isPrivate: isPrivate, dataStore: isPrivate ? privateStore : .default(), configuration: configuration)
        engine.sitePolicy = { [weak self] host in self?.library?.policy(for: host) ?? SitePolicy() }
        engine.apply(library?.options ?? BrowserOptions())
        engine.onVisit = { [weak self] url, title in
            guard let self, let index = self.tabs.firstIndex(where: { $0.id == id }) else { return }
            if self.pendingNavigations.remove(id) != nil, self.tabs[index].history.indices.contains(self.tabs[index].index) {
                self.tabs[index].history[self.tabs[index].index] = url; self.tabs[index].title = title
            } else { self.tabs[index].visit(url, title: title) }
            if !self.tabs[index].isPrivate { self.library?.record(url, title: title) }
            self.scheduleSave()
        }
        engine.onScroll = { [weak self] y in
            guard let self, let index = self.tabs.firstIndex(where: { $0.id == id }) else { return }
            self.tabs[index].scrollY = max(0, y); self.scheduleSave()
        }
        engine.onNewWindow = { [weak self] configuration in self?.createPopup(configuration: configuration, isPrivate: isPrivate) }
        engine.onDownload = { download, url in DownloadManager.shared.accept(download, source: url) }
        return engine
    }
    func navigate(_ url: URL) {
        guard let index = tabs.firstIndex(where: { $0.id == selected }) else { return }
        tabs[index].visit(url, title: url.host ?? "zero red"); pendingNavigations.insert(selected); engine().open(url); scheduleSave()
    }
    func home() { engine().home(); if let i = tabs.firstIndex(where: { $0.id == selected }) { tabs[i].history = []; tabs[i].index = -1; tabs[i].title = "zero red"; tabs[i].scrollY = 0 }; scheduleSave() }
    func move(_ offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selected }) else { return }
        let active = engine()
        if offset < 0, active.canGoBack { active.webView.goBack(); _ = tabs[index].move(-1) }
        else if offset > 0, active.canGoForward { active.webView.goForward(); _ = tabs[index].move(1) }
        else if let url = tabs[index].move(offset) { pendingNavigations.insert(selected); active.open(url) }
        scheduleSave()
    }
    @discardableResult
    func create() -> UUID {
        guard tabs.count < 50 else { library?.downloadError = "最多 50 个页面 / Maximum 50 pages"; return selected }
        engine().suspendMedia()
        let tab = BrowserTabRecord(isPrivate: privateMode); tabs.append(tab); selected = tab.id
        scheduleSave(); return tab.id
    }
    private func createPopup(configuration: WKWebViewConfiguration, isPrivate: Bool) -> WKWebView? {
        guard tabs.count < 50 else { return nil }
        engines[selected]?.suspendMedia()
        let tab = BrowserTabRecord(isPrivate: isPrivate); tabs.append(tab); selected = tab.id; privateMode = isPrivate
        let engine = makeEngine(id: tab.id, isPrivate: isPrivate, configuration: configuration)
        engine.active = true; engines[tab.id] = engine; scheduleSave(); trimEngines(); return engine.webView
    }
    func select(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        engines[selected]?.suspendMedia(); selected = id; privateMode = tab.isPrivate; engine().resumeMedia(); scheduleSave()
    }
    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        if !tab.isPrivate { recentlyClosed.insert(tab, at: 0); recentlyClosed = Array(recentlyClosed.prefix(10)) }
        engines[id]?.suspendMedia(); engines[id]?.webView.stopLoading(); engines.removeValue(forKey: id)
        if visibleTabs.isEmpty { let fresh = BrowserTabRecord(isPrivate: privateMode); tabs.append(fresh) }
        if selected == id { selected = visibleTabs.first!.id }
        if !tabs.contains(where: \.isPrivate) { privateStore = .nonPersistent() }
        scheduleSave()
    }
    func reopen(_ id: UUID) {
        guard let index = recentlyClosed.firstIndex(where: { $0.id == id }) else { return }
        let tab = recentlyClosed.remove(at: index); tabs.append(tab); select(tab.id)
    }
    func togglePrivate() {
        engines[selected]?.suspendMedia(); privateMode.toggle()
        if let existing = visibleTabs.first { selected = existing.id }
        else { let tab = BrowserTabRecord(isPrivate: privateMode); tabs.append(tab); selected = tab.id }
        engine().resumeMedia(); scheduleSave()
    }
    func endPrivateSession() {
        let ids = tabs.filter(\.isPrivate).map(\.id)
        for id in ids { engines[id]?.suspendMedia(); engines[id]?.webView.stopLoading(); engines.removeValue(forKey: id) }
        tabs.removeAll(where: \.isPrivate); privateStore = .nonPersistent(); privateMode = false
        if tabs.isEmpty { tabs = [BrowserTabRecord()] }; selected = tabs[0].id; saveNow()
    }
    func applyOptions() { for engine in engines.values { engine.apply(library?.options ?? BrowserOptions()) } }
    func handleMemoryPressure() {
        for id in Array(engines.keys) where id != selected { engines[id]?.suspendMedia(); engines[id]?.webView.stopLoading(); engines.removeValue(forKey: id) }
        saveNow()
    }
    func clearRecentlyClosed() { recentlyClosed = []; saveNow() }
    func background() { engines.values.forEach { $0.suspendMedia() }; saveNow() }
    private func trimEngines() {
        while engines.count > 6, let id = engines.keys.first(where: { $0 != selected }) {
            engines[id]?.suspendMedia(); engines[id]?.webView.stopLoading(); engines.removeValue(forKey: id)
        }
    }
    private func scheduleSave() {
        saving?.cancel(); saving = Task { [weak self] in try? await Task.sleep(for: .milliseconds(400)); guard !Task.isCancelled else { return }; self?.saveNow() }
    }
    func saveNow() {
        do {
            try FileManager.default.createDirectory(at: AppPaths.directory, withIntermediateDirectories: true)
            let snapshot = BrowserSessionSnapshot(tabs: tabs, selected: selected, recentlyClosed: recentlyClosed)
            try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        } catch { library?.downloadError = error.localizedDescription }
    }
}
