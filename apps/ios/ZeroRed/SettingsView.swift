import SwiftUI
import WebKit

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reading: ReadingLibrary
    @ObservedObject var session: BrowserSession
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var confirm: String?
    @State private var websiteData = false
    @State private var blockedInput = ""
    var body: some View {
        Form {
            Section(library.text("浏览", "Browsing")) {
                Picker(library.text("搜索引擎", "Search engine"), selection: $library.options.search) { ForEach(SearchProvider.allCases) { Text($0.label).tag($0) } }
                Picker(library.text("语言", "Language"), selection: $library.language) { Text(library.text("跟随系统", "System")).tag("system"); Text("简体中文").tag("zh-Hans"); Text("English").tag("en") }
                Picker(library.text("外观", "Appearance"), selection: $library.options.theme) { Text(library.text("跟随系统", "System")).tag("system"); Text(library.text("浅色", "Light")).tag("light"); Text(library.text("深色", "Dark")).tag("dark") }
                Toggle(library.text("默认请求桌面网站", "Request desktop websites"), isOn: $library.options.desktop)
                Picker(library.text("页面缩放", "Page zoom"), selection: $library.options.zoom) { ForEach([0.75,1,1.25,1.5,2], id: \.self) { value in Text("\(Int(value*100))%").tag(value) } }
                Toggle(library.text("允许网页弹窗", "Allow website popups"), isOn: $library.options.allowPopups)
            }
            Section(library.text("隐私与内容", "Privacy and content")) {
                Toggle(library.text("基础追踪拦截", "Basic tracker blocking"), isOn: $library.options.blockTrackers)
                Toggle(library.text("基础广告拦截", "Basic ad blocking"), isOn: $library.options.blockAds)
                TextField(library.text("额外拦截域名，空格分隔", "Extra blocked domains, space-separated"), text: $blockedInput, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(library.text("拦截使用本地规则，不会覆盖所有广告。网站异常时，可在网站权限中关闭该站的拦截。", "Blocking uses local rules and does not cover every ad. Disable it for an individual site if it causes problems.")).font(.caption).foregroundStyle(.secondary)
                Button(library.text("网站数据与 Cookie", "Website data and cookies")) { websiteData = true }
                Button(library.text("清除网页缓存", "Clear website cache")) { confirm = "cache" }
                Button(library.text("清除 Cookie 和网站数据", "Clear cookies and website data"), role: .destructive) { confirm = "sites" }
                Button(library.text("清空浏览历史", "Clear browsing history"), role: .destructive) { confirm = "history" }
                Button(library.text("重置网站权限", "Reset website permissions"), role: .destructive) { confirm = "permissions" }
            }
            Section(library.text("本地存储", "Local storage")) {
                LabeledContent(library.text("阅读文档", "Reading documents"), value: ByteCountFormatter.string(fromByteCount: reading.bytes, countStyle: .file))
                LabeledContent(library.text("下载文件", "Downloaded files"), value: ByteCountFormatter.string(fromByteCount: downloads.bytes, countStyle: .file))
                Button(library.text("清理已下载文件", "Delete completed downloads"), role: .destructive) { confirm = "downloads" }
                Button(library.text("清理阅读文档", "Delete saved reading"), role: .destructive) { confirm = "reading" }
                Text(library.text("下载和阅读文档只保存在本机；卸载应用会删除。请按需导出。", "Downloads and reading documents stay on this device and are removed when the app is uninstalled. Export files you want to keep.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(library.text("系统", "System")) {
                Button(library.text("系统权限与默认浏览器设置", "System permissions and default browser settings")) { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                Text(library.text("默认浏览器选项取决于安装版本是否获得 Apple 的浏览器授权。开发工程未附带此授权。", "The default-browser option depends on the installed app having Apple's browser entitlement. This development project does not include that approval.")).font(.caption).foregroundStyle(.secondary)
                LabeledContent(library.text("版本", "Version"), value: "zero red · 0.2")
            }
        }
        .onAppear { blockedInput = library.options.extraBlockedDomains }
        .onDisappear { library.options.extraBlockedDomains = blockedInput }
        .sheet(isPresented: $websiteData) { WebsiteDataView() }
        .confirmationDialog(library.text("确认清除所选数据？", "Clear the selected data?"), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button(library.text("清除", "Clear"), role: .destructive) { let type = confirm; confirm = nil; clear(type) }
        }
    }
    private func clear(_ type: String?) {
        switch type {
        case "history": library.history.removeAll(); session.clearRecentlyClosed()
        case "permissions": library.sitePolicies = [:]
        case "downloads": downloads.jobs.filter { $0.state == .complete }.forEach(downloads.remove)
        case "reading": reading.documents.forEach(reading.delete)
        case "cache": Task { await WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache], modifiedSince: .distantPast) }
        case "sites": Task { await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast); session.endPrivateSession(); session.engine().webView.reload() }
        default: break
        }
    }
}
@MainActor
struct SiteSettings: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var engine: BrowserEngine
    private var host: String { engine.url?.host?.lowercased() ?? "" }
    private var policy: Binding<SitePolicy> { Binding(get: { library.policy(for: SiteOrigin.key(url: engine.url)) }, set: { library.sitePolicies[SiteOrigin.key(url: engine.url)] = $0; engine.apply(library.options); engine.webView.reload() }) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(library.text("域名", "Domain"), value: host)
                    Label(engine.url?.scheme == "https" ? library.text("HTTPS 加密连接", "HTTPS encrypted connection") : library.text("连接未加密", "Connection is not encrypted"), systemImage: engine.url?.scheme == "https" ? "lock" : "exclamationmark.triangle")
                    Text(library.text("HTTPS 表示连接加密，不代表网站内容可信。证书错误会由系统拒绝。", "HTTPS encrypts the connection; it does not guarantee trustworthy content. Certificate errors are rejected by the system.")).font(.caption).foregroundStyle(.secondary)
                }
                Section(library.text("网站权限", "Site permissions")) {
                    permission(library.text("相机", "Camera"), selection: policy.camera)
                    permission(library.text("麦克风", "Microphone"), selection: policy.microphone)
                    Toggle(library.text("允许弹窗", "Allow popups"), isOn: policy.allowPopups)
                    Toggle(library.text("关闭本站内容拦截", "Disable content blocking here"), isOn: policy.disableBlocking)
                    Text(library.text("定位、照片和系统权限可在系统设置中管理；网页仍需获得系统授权。", "Location, photo and system permissions are managed in Settings. Websites still require system authorization.")).font(.caption).foregroundStyle(.secondary)
                    Button(library.text("打开系统权限", "Open system permissions")) { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
                Button(library.text("清除本站数据", "Clear this site's data"), role: .destructive) {
                    Task { let types = WKWebsiteDataStore.allWebsiteDataTypes(); let store = engine.webView.configuration.websiteDataStore; let records = await store.dataRecords(ofTypes: types); let matching = records.filter { host == $0.displayName || host.hasSuffix("." + $0.displayName) }; await store.removeData(ofTypes: types, for: matching); engine.webView.reload() }
                }
            }.navigationTitle(library.text("网站设置", "Website settings")).toolbar { Button(library.text("完成", "Done")) { dismiss() } }
        }
    }
    private func permission(_ title: String, selection: Binding<PermissionChoice>) -> some View { Picker(title, selection: selection) { Text(library.text("每次询问", "Ask")).tag(PermissionChoice.ask); Text(library.text("允许", "Allow")).tag(PermissionChoice.allow); Text(library.text("拒绝", "Deny")).tag(PermissionChoice.deny) } }
}
@MainActor
struct WebsiteDataView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var records: [WKWebsiteDataRecord] = []
    var body: some View {
        NavigationStack {
            List {
                ForEach(records, id: \.displayName) { record in HStack { Text(record.displayName); Spacer(); Button { Task { await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: [record]); await reload() } } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel(library.text("删除网站数据", "Delete site data")) } }
            }.navigationTitle(library.text("网站数据", "Website data")).toolbar { Button(library.text("完成", "Done")) { dismiss() } }.task { await reload() }
        }
    }
    private func reload() async { records = await WKWebsiteDataStore.default().dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) }
}
