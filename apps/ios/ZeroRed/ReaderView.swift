import SwiftUI
import UniformTypeIdentifiers
import QuickLook
#if canImport(Translation)
import Translation
#endif

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct SharedItems: Identifiable { let id = UUID(); var items: [Any] }
struct PreviewFile: Identifiable { let id = UUID(); var url: URL }
struct FilePreview: UIViewControllerRepresentable {
    var url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL; init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
private struct ReadingOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
@MainActor
struct ReaderView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reading: ReadingLibrary
    @Environment(\.dismiss) private var dismiss
    @State var document: ReadingDocument
    @AppStorage("readerSize") private var size = 19.0
    @AppStorage("readerSpacing") private var spacing = 10.0
    @AppStorage("readerSerif") private var serif = true
    @AppStorage("readerDark") private var dark = false
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @State private var focus = false
    @State private var query = ""
    @State private var showFind = false
    @State private var showContents = false
    @State private var shared: SharedItems?
    @State private var preview: PreviewFile?
    @State private var translation = false
    @State private var pending: Task<Void, Never>?
    @State private var viewport: CGFloat = 1
    @State private var height: CGFloat = 1
    private var saved: Bool { reading.documents.contains(where: { $0.id == document.id }) }
    private var paragraphs: [String] { document.text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var contents: [(Int, String)] { paragraphs.enumerated().filter { $0.element.hasPrefix("#") }.map { ($0.offset, $0.element.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !focus { icon("chevron.left", library.text("返回", "Back")) { dismiss() } }
                Spacer()
                icon(saved ? "checkmark" : "arrow.down.to.line", library.text(saved ? "已缓存" : "缓存当前文本", saved ? "Saved" : "Save current text")) { cache() }.disabled(saved)
                if !focus {
                    Menu {
                        Button(library.text("字号增加", "Larger text")) { size = min(32, size + 2) }
                        Button(library.text("字号减小", "Smaller text")) { size = max(14, size - 2) }
                        Toggle(library.text("衬线字体", "Serif font"), isOn: $serif)
                        Toggle(library.text("深色阅读", "Dark reading"), isOn: $dark)
                        Picker(library.text("行距", "Spacing"), selection: $spacing) { Text(library.text("紧凑", "Compact")).tag(4.0); Text(library.text("适中", "Comfortable")).tag(10.0); Text(library.text("宽松", "Spacious")).tag(18.0) }
                        Button(library.text("页内查找", "Find in text")) { showFind.toggle() }
                        Button(library.text("目录", "Contents")) { showContents = true }.disabled(contents.isEmpty)
                        Button(library.text("翻译正文", "Translate text")) { translation = true }
                        Button(library.text("复制全文", "Copy all text")) { UIPasteboard.general.string = document.text }
                        Button(library.text("导出文本", "Export text")) { do { shared = SharedItems(items: [try reading.exportText(document)]) } catch { reading.error = error.localizedDescription } }
                        if let original = document.originalURL { Button(library.text("查看原文件", "View original")) { preview = PreviewFile(url: original) } }
                    } label: { Text("Aa").frame(width: 44, height: 44) }.accessibilityLabel(library.text("阅读设置", "Reading settings"))
                }
                icon(focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", library.text(focus ? "退出专注" : "专注阅读", focus ? "Exit focus" : "Focus reading")) { focus.toggle() }
            }.padding(.horizontal, 12)
            if showFind && !focus { TextField(library.text("查找文字", "Find text"), text: $query).textFieldStyle(.roundedBorder).padding(.horizontal) }
            GeometryReader { viewportGeometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(document.title).font(.system(size: size * textScale * 1.5, weight: .medium, design: serif ? .serif : .default)).padding(.bottom, 30)
                            if document.text.isEmpty {
                                Text(library.text("未提取到文字，可能为扫描文档。请查看原文件。", "No text was found. This may be a scanned document. Open the original file.")).foregroundStyle(.secondary)
                                if let original = document.originalURL { Button(library.text("查看原文件", "Open original")) { preview = PreviewFile(url: original) } }
                            }
                            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                                Text((try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph))
                                    .font(.system(size: size * textScale, design: serif ? .serif : .default)).lineSpacing(spacing).textSelection(.enabled)
                                    .padding(.bottom, size * 1.2).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(!query.isEmpty && paragraph.localizedStandardContains(query) ? Color.primary.opacity(0.12) : .clear).id(index)
                            }
                        }.padding(.horizontal, 26).padding(.vertical, 32).frame(maxWidth: 740)
                        .background(GeometryReader { geo in Color.clear.preference(key: ReadingOffset.self, value: geo.frame(in: .named("readerScroll")).minY).onAppear { height = geo.size.height }.onChange(of: geo.size.height) { _, value in height = value } })
                    }.coordinateSpace(name: "readerScroll")
                    .onAppear { viewport = viewportGeometry.size.height; if document.progress > 0 && !paragraphs.isEmpty { proxy.scrollTo(min(paragraphs.count-1, Int(Double(paragraphs.count) * document.progress)), anchor: .top) } }
                    .onPreferenceChange(ReadingOffset.self) { y in
                        document.progress = ReadingText.progress(offset: Double(-y), height: Double(height), viewport: Double(viewport))
                        pending?.cancel(); if saved { let copy = document; pending = Task { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { reading.update(copy) } } }
                    }
                    .onChange(of: query) { _, value in if !value.isEmpty, let index = paragraphs.firstIndex(where: { $0.localizedStandardContains(value) }) { proxy.scrollTo(index, anchor: .top) } }
                    .sheet(isPresented: $showContents) { NavigationStack { List(contents, id: \.0) { index, title in Button(title) { showContents = false; proxy.scrollTo(index, anchor: .top) } }.navigationTitle(library.text("目录", "Contents")) } }
                }
            }
            if !focus { Text("\(Int(document.progress * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).padding(.bottom, 8) }
        }
        .background(dark ? Color(white: 0.07) : .white).foregroundStyle(dark ? .white : Color(white: 0.12)).preferredColorScheme(dark ? .dark : .light)
        .onDisappear { pending?.cancel(); if saved { reading.update(document) } }
        .sheet(item: $shared) { ShareSheet(items: $0.items) }
        .sheet(item: $preview) { FilePreview(url: $0.url) }
        .alert(library.text("提示", "Notice"), isPresented: Binding(get: { reading.error != nil }, set: { if !$0 { reading.error = nil } })) { Button(library.text("好", "OK")) { reading.error = nil } } message: { Text(reading.error ?? "") }
        .modifier(SystemTranslation(presented: $translation, text: document.text))
    }
    private func cache() { do { document = try reading.save(document) } catch { reading.error = error.localizedDescription } }
    private func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(label) }
}
struct SystemTranslation: ViewModifier {
    @Binding var presented: Bool
    var text: String
    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 17.4, *) { content.translationPresentation(isPresented: $presented, text: text) }
        else { content.alert("翻译需要 iOS 17.4 或以上 / Translation requires iOS 17.4+", isPresented: $presented) { Button("OK") {} } }
        #else
        content.alert("系统翻译不可用 / System translation unavailable", isPresented: $presented) { Button("OK") {} }
        #endif
    }
}
