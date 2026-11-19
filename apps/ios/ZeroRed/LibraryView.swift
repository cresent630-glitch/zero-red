import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reading: ReadingLibrary
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var session: BrowserSession
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var streams = StreamingDownloads.shared
    var open: (URL) -> Void
    @State private var tab = 0
    @State private var query = ""
    @State private var videoURL = ""
    @State private var title = ""
    @State private var pastedText = ""
    @State private var detected: [URL] = []
    @State private var player: PlayableItem?
    @State private var selectedDocument: ReadingDocument?
    @State private var editingDocument: ReadingDocument?
    @State private var preview: PreviewFile?
    @State private var shared: SharedItems?
    @State private var importing = false
    @State private var importingBackup = false
    @State private var confirmClear = false
    private var labels: [String] { [library.text("书签", "Bookmarks"), library.text("历史", "History"), library.text("视频", "Videos"), library.text("阅读", "Reading"), library.text("下载", "Downloads"), library.text("设置", "Settings")] }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(labels.indices, id: \.self) { index in
                            ZeroRedChip(title: labels[index], isSelected: tab == index) { tab = index; query = "" }
                        }
                    }.padding(.horizontal).padding(.vertical, 4)
                }.padding(.bottom, 4)
                switch tab { case 0: bookmarks; case 1: history; case 2: videos; case 3: documents; case 4: DownloadList(engine: engine); default: SettingsView(session: session) }
            }.navigationTitle("zero red").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { GlassProminentButton(title: library.text("完成", "Done")) { dismiss() } } }
            .task { detected = await engine.videoLinks() }
            .fullScreenCover(item: $selectedDocument) { ReaderView(document: $0) }
            .sheet(item: $editingDocument) { document in DocumentEditor(document: document) }
            .sheet(item: $preview) { FilePreview(url: $0.url) }
            .sheet(item: $shared) { ShareSheet(items: $0.items) }
            .fullScreenCover(item: $player) { NativePlayer(item: $0) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .html, .pdf, UTType(filenameExtension: "docx") ?? .data], allowsMultipleSelection: false) { result in do { if let url = try result.get().first { selectedDocument = try reading.importFile(url) } } catch { reading.error = error.localizedDescription } }
            .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in do { if let url = try result.get().first { try reading.restoreBackup(url) } } catch { reading.error = error.localizedDescription } }
            .alert(library.text("提示", "Notice"), isPresented: Binding(get: { library.downloadError != nil || reading.error != nil || downloads.error != nil }, set: { if !$0 { library.downloadError = nil; reading.error = nil; downloads.error = nil } })) { Button(library.text("好", "OK")) { library.downloadError = nil; reading.error = nil; downloads.error = nil } } message: { Text(library.downloadError ?? reading.error ?? downloads.error ?? "") }
            .confirmationDialog(library.text("清空所有历史记录？", "Clear all history?"), isPresented: $confirmClear, titleVisibility: .visible) { Button(library.text("清空", "Clear"), role: .destructive) { library.history.removeAll() } }
        }
    }
    private var bookmarks: some View {
        List {
            if let url = engine.url, engine.active { Button(library.text("收藏当前网页", "Bookmark this page"), systemImage: "bookmark") { library.bookmark(url, title: engine.title) } }
            ForEach(library.bookmarks.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.url.absoluteString.localizedStandardContains(query) }) { page($0) }
                .onDelete { indices in let visible = library.bookmarks.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.url.absoluteString.localizedStandardContains(query) }; let ids = indices.map { visible[$0].id }; library.bookmarks.removeAll { ids.contains($0.id) } }
        }.searchable(text: $query, prompt: library.text("搜索书签", "Search bookmarks"))
    }
    private var history: some View {
        List {
            if library.history.isEmpty { Text(library.text("暂无历史记录", "No browsing history")).foregroundStyle(.secondary) }
            ForEach(library.history.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.url.absoluteString.localizedStandardContains(query) }) { page($0) }
                .onDelete { indices in let visible = library.history.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.url.absoluteString.localizedStandardContains(query) }; let ids = indices.map { visible[$0].id }; library.history.removeAll { ids.contains($0.id) } }
            if !library.history.isEmpty { Button(library.text("清空历史记录", "Clear history"), role: .destructive) { confirmClear = true } }
        }.searchable(text: $query, prompt: library.text("搜索历史", "Search history"))
    }
    private var videos: some View {
        List {
            Section(library.text("视频链接", "Video URL")) {
                TextField(library.text("MP4 / MOV / HLS 链接", "MP4 / MOV / HLS URL"), text: $videoURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("videoURLInput")
                HStack {
                    Button(library.text("播放", "Play")) { if let url = parsedVideo() { Task { let cookies = await engine.cookies(); player = PlayableItem(url: url, title: url.lastPathComponent, cookies: cookies) } } }
                    Spacer()
                    Button(library.text("下载并保存", "Download and save")) { if let url = parsedVideo() { cacheVideo(url) } }.accessibilityIdentifier("downloadVideo")
                }
                Text(library.text("支持可访问、未加密的视频。缓存能力受格式、授权与网站限制影响。", "Use accessible, unencrypted videos. Saving depends on format, authorization and website restrictions.")).font(.caption).foregroundStyle(.secondary)
            }
            if !detected.isEmpty { Section(library.text("当前网页的视频", "Videos on this page")) { ForEach(detected, id: \.self) { url in HStack { Button(url.lastPathComponent) { Task { let cookies = await engine.cookies(); player = PlayableItem(url: url, title: engine.title, cookies: cookies) } }; Spacer(); Button { cacheVideo(url) } label: { Image(systemName: "arrow.down.to.line").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel(library.text("缓存视频", "Save video")) } } } }
            Section(library.text("离线视频", "Offline videos")) {
                ForEach(library.videos) { video in Button(video.title) { player = PlayableItem(url: video.localURL, title: video.title) }.contextMenu { Button(library.text("删除", "Delete"), role: .destructive) { library.removeVideo(video) }; ShareLink(item: video.localURL) } }
                ForEach(downloads.jobs.filter { $0.kind == "video" && $0.state == .complete }) { job in if let url = job.localURL { Button(job.name) { player = PlayableItem(url: url, title: job.name, source: job.url) }.accessibilityIdentifier("offlineVideo." + job.name).contextMenu { ShareLink(item: url); Button(library.text("删除", "Delete"), role: .destructive) { downloads.remove(job) } } } }
                ForEach(streams.items.filter { $0.state == "complete" }) { item in if let url = item.localURL { Button(item.title) { player = PlayableItem(url: url, title: item.title, source: item.source) }.contextMenu { Button(library.text("删除", "Delete"), role: .destructive) { streams.remove(item) } } } }
            }
            Section(library.text("下载任务", "Downloads")) {
                ForEach(downloads.jobs.filter { $0.kind == "video" && $0.state != .complete }) { job in VStack(alignment: .leading) { Text(job.name); ProgressView(value: job.progress); Text(job.error ?? job.state.rawValue).font(.caption).foregroundStyle(.secondary) } }
                ForEach(streams.items.filter { $0.state != "complete" }) { item in VStack(alignment: .leading) { Text(item.title); ProgressView(value: item.progress); Text(item.error ?? item.state).font(.caption).foregroundStyle(.secondary) } }
            }
        }
    }
    private var documents: some View {
        List {
            Section {
                HStack { Button(library.text("导入文档", "Import document")) { importing = true }; Spacer(); Button(library.text("阅读当前页", "Read this page")) { Task { do { selectedDocument = try await engine.article() } catch { reading.error = error.localizedDescription } } }.disabled(!engine.active) }
                DisclosureGroup(library.text("粘贴文字", "Paste text")) {
                    TextField(library.text("标题", "Title"), text: $title)
                    TextEditor(text: $pastedText).frame(minHeight: 160).accessibilityLabel(library.text("文本内容", "Text content"))
                    Button(library.text("缓存并阅读", "Save and read")) {
                        do { let text = ReadingText.normalized(pastedText); guard !text.isEmpty else { return }; selectedDocument = try reading.save(ReadingDocument(title: title.isEmpty ? String(text.prefix(60)) : title, text: text)); pastedText = ""; title = "" } catch { reading.error = error.localizedDescription }
                    }
                }
            }
            ForEach(reading.documents.filter { ReadingText.matches($0, query: query) }) { document in
                Button { selectedDocument = document } label: { VStack(alignment: .leading, spacing: 5) { Text(document.title).foregroundStyle(.primary); Text("\(document.format.uppercased()) · \(document.tag) · \(Int(document.progress*100))%").font(.caption).foregroundStyle(.secondary) } }
                    .contextMenu { Button(library.text("修改标题 / 标签", "Edit title / tag")) { editingDocument = document }; Button(library.text("导出文本", "Export text")) { do { shared = SharedItems(items: [try reading.exportText(document)]) } catch { reading.error = error.localizedDescription } }; if let url = document.originalURL { Button(library.text("原文件", "Original file")) { preview = PreviewFile(url: url) } }; Button(library.text("删除", "Delete"), role: .destructive) { reading.delete(document) } }
            }
            Section { Button(library.text("导出阅读备份", "Export reading backup")) { do { shared = SharedItems(items: [try reading.exportBackup()]) } catch { reading.error = error.localizedDescription } }; Button(library.text("导入阅读备份", "Import reading backup")) { importingBackup = true } }
        }.searchable(text: $query, prompt: library.text("搜索标题、正文、标签", "Search title, full text, tags"))
    }
    private func page(_ entry: PageEntry) -> some View { Button { open(entry.url) } label: { VStack(alignment: .leading, spacing: 4) { Text(entry.title).foregroundStyle(.primary).lineLimit(1); Text(entry.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }.accessibilityIdentifier("page." + entry.url.absoluteString).contextMenu { ShareLink(item: entry.url); Button(library.text("复制链接", "Copy link")) { UIPasteboard.general.url = entry.url } } }
    private func parsedVideo() -> URL? { let url = AddressResolver.webURL(videoURL.trimmingCharacters(in: .whitespacesAndNewlines)); if url == nil { library.downloadError = library.text("请输入有效的视频网址。", "Enter a valid video URL.") }; return url }
    private func cacheVideo(_ url: URL) {
        Task {
            let cookies = await engine.cookies()
            if url.pathExtension.lowercased() == "m3u8" { await streams.start(url, title: engine.title.isEmpty ? url.lastPathComponent : engine.title, cookies: cookies) }
            else { _ = downloads.start(url, cookies: cookies, kind: "video") }
        }
    }
}
@MainActor
private struct DocumentEditor: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reading: ReadingLibrary
    @Environment(\.dismiss) private var dismiss
    @State var document: ReadingDocument
    var body: some View { NavigationStack { Form { TextField(library.text("标题", "Title"), text: $document.title); TextField(library.text("标签 / 分类", "Tag / category"), text: $document.tag) }.navigationTitle(library.text("编辑", "Edit")).toolbar { Button(library.text("保存", "Save")) { reading.update(document); dismiss() } } } }
}
@MainActor
struct DownloadList: View {
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var streams = StreamingDownloads.shared
    @ObservedObject var engine: BrowserEngine
    @State private var url = ""
    @State private var preview: PreviewFile?
    var body: some View {
        List {
            Section { TextField(library.text("下载文件网址", "File URL to download"), text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled(); Button(library.text("开始下载", "Start download")) { if let value = AddressResolver.webURL(url) { Task { let cookies = await engine.cookies(); _ = downloads.start(value, cookies: cookies) } } else { downloads.error = library.text("无效网址", "Invalid URL") } } }
            ForEach(downloads.jobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.name).lineLimit(2)
                    if job.state == .running { ProgressView(value: job.progress) }
                    Text(job.error ?? "\(job.state.rawValue) · \(ByteCountFormatter.string(fromByteCount: job.received, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if job.state == .running { Button(library.text("暂停", "Pause")) { downloads.pause(job.id) }; Button(library.text("取消", "Cancel")) { downloads.cancel(job.id) } }
                        if [.paused, .failed, .cancelled].contains(job.state) { Button(library.text("继续 / 重试", "Resume / retry")) { downloads.retry(job, webView: engine.webView) } }
                        if job.state == .complete, let url = job.localURL { Button(library.text("打开", "Open")) { preview = PreviewFile(url: url) }; ShareLink(item: url) { Label(library.text("导出到文件", "Export to Files"), systemImage: "square.and.arrow.up") } }
                        Spacer(); Button(role: .destructive) { downloads.remove(job) } label: { Image(systemName: "trash") }.accessibilityLabel(library.text("删除下载", "Delete download"))
                    }.buttonStyle(.borderless).font(.caption)
                }.padding(.vertical, 6)
            }
            if !streams.items.isEmpty { Section("HLS") { ForEach(streams.items) { item in VStack(alignment: .leading) { Text(item.title); ProgressView(value: item.progress); Text(item.error ?? item.state).font(.caption).foregroundStyle(.secondary); HStack { if item.state == "running" { Button(library.text("暂停", "Pause")) { streams.pause(item) } } else if item.state != "complete" { Button(library.text("继续 / 重试", "Resume / retry")) { streams.resume(item) } }; Spacer(); Button(library.text("删除", "Delete"), role: .destructive) { streams.remove(item) } }.buttonStyle(.borderless) } } } }
            Text(library.text("URL 下载支持系统后台任务。网页触发的 WebKit 下载可能需要保持应用运行。强制退出和网站授权可能影响恢复。", "URL downloads use system background tasks. WebKit page downloads may require the app to remain open. Force quitting and website authorization can affect resuming.")).font(.caption).foregroundStyle(.secondary)
        }.sheet(item: $preview) { FilePreview(url: $0.url) }
    }
}
