import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum SearchProvider: String, Codable, CaseIterable, Identifiable {
    case bing, google, duckduckgo, baidu
    var id: String { rawValue }
    var label: String { ["bing":"Bing","google":"Google","duckduckgo":"DuckDuckGo","baidu":"百度"][rawValue]! }
    func search(_ query: String) -> URL {
        let base = ["bing":"https://www.bing.com/search", "google":"https://www.google.com/search", "duckduckgo":"https://duckduckgo.com/", "baidu":"https://www.baidu.com/s"][rawValue]!
        var url = URLComponents(string: base)!
        url.queryItems = [URLQueryItem(name: self == .baidu ? "wd" : "q", value: query)]
        return url.url!
    }
    func resolve(_ input: String) -> URL? {
        guard let result = AddressResolver.resolve(input) else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let domainURL = AddressResolver.webURL("https://" + trimmed), let host = domainURL.host, host.contains(".") || host == "localhost" || host.contains(":") { return result }
        if result.host == "www.bing.com", result.path == "/search", AddressResolver.webURL(input.trimmingCharacters(in: .whitespacesAndNewlines)) == nil,
           let query = URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value { return search(query) }
        return result
    }
}
struct BrowserOptions: Codable, Equatable {
    var search: SearchProvider = .bing
    var theme = "system"
    var desktop = false
    var zoom = 1.0
    var allowPopups = false
    var blockTrackers = true
    var blockAds = false
    var extraBlockedDomains = ""
}
enum PermissionChoice: String, Codable, CaseIterable, Identifiable {
    case ask, allow, deny
    var id: String { rawValue }
}
struct SitePolicy: Codable, Equatable {
    var camera: PermissionChoice = .ask
    var microphone: PermissionChoice = .ask
    var allowPopups = false
    var disableBlocking = false
}
struct BrowserTabRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "zero red"
    var history: [URL] = []
    var index = -1
    var scrollY = 0.0
    var isPrivate = false
    var url: URL? { history.indices.contains(index) ? history[index] : nil }
    var canBack: Bool { index > 0 }
    var canForward: Bool { index >= 0 && index < history.count - 1 }
    mutating func visit(_ url: URL, title: String) {
        self.title = title
        if self.url == url { return }
        history = Array(history.prefix(max(0, index + 1)))
        history.append(url)
        if history.count > 100 { history.removeFirst(history.count - 100) }
        index = history.count - 1; scrollY = 0
    }
    mutating func move(_ offset: Int) -> URL? {
        let next = index + offset
        guard history.indices.contains(next) else { return nil }
        index = next; scrollY = 0
        return url
    }
}
struct BrowserSessionSnapshot: Codable, Equatable {
    var tabs: [BrowserTabRecord] = []
    var selected: UUID?
    var recentlyClosed: [BrowserTabRecord] = []
    init(tabs: [BrowserTabRecord] = [], selected: UUID? = nil, recentlyClosed: [BrowserTabRecord] = []) {
        self.tabs = tabs.filter { !$0.isPrivate }
        self.selected = self.tabs.contains(where: { $0.id == selected }) ? selected : self.tabs.first?.id
        self.recentlyClosed = Array(recentlyClosed.filter { !$0.isPrivate }.prefix(10))
    }
}
struct ReadingDocument: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var source: String = ""
    var format: String = "txt"
    var originalFilename: String?
    var tag = ""
    var progress = 0.0
    var date = Date()
    var originalURL: URL? { originalFilename.map { AppPaths.directory.appendingPathComponent("Reading").appendingPathComponent($0) } }
}
struct ReadingBackup: Codable {
    var version = 1
    var documents: [ReadingDocument]
    var originals: [String: Data]
}
enum ReadingText {
    static let limit = 1_000_000
    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xff, 0xfe]) { return String(data: data, encoding: .utf16LittleEndian).map(normalized) }
        if data.starts(with: [0xfe, 0xff]) { return String(data: data, encoding: .utf16BigEndian).map(normalized) }
        return String(data: data, encoding: .utf8).map(normalized) ?? String(data: data, encoding: .utf16).map(normalized)
    }
    static func matches(_ document: ReadingDocument, query: String) -> Bool {
        query.isEmpty || [document.title, document.text, document.tag, document.source].contains { $0.localizedStandardContains(query) }
    }
    static func progress(offset: Double, height: Double, viewport: Double) -> Double {
        guard height > viewport else { return 1 }
        return min(1, max(0, offset / (height - viewport)))
    }
}
final class DocxTextParser: NSObject, XMLParserDelegate {
    private var text = ""
    private var inText = false
    private var sawDocument = false
    private var endedDocument = false
    func parse(_ data: Data) throws -> String {
        text = ""; inText = false; sawDocument = false; endedDocument = false
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = self
        guard parser.parse(), sawDocument, endedDocument else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        return ReadingText.normalized(text)
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "w:document" || elementName == "document" { sawDocument = true }
        if elementName == "w:t" || elementName == "t" { inText = true }
        if ["w:tab", "tab"].contains(elementName) { text += "\t" }
        if ["w:br", "br"].contains(elementName) { text += "\n" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { text += string }
        if text.count > ReadingText.limit { parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "w:document" || elementName == "document" { endedDocument = true }
        if elementName == "w:t" || elementName == "t" { inText = false }
        if elementName == "w:p" || elementName == "p" { text += "\n\n" }
    }
}
enum DownloadState: String, Codable { case running, paused, failed, complete, cancelled }
struct DownloadRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL
    var name: String
    var state: DownloadState = .running
    var received: Int64 = 0
    var expected: Int64 = 0
    var filename: String?
    var resumeData: Data?
    var error: String?
    var kind = "file"
    var date = Date()
    var progress: Double? { expected > 0 ? min(1, max(0, Double(received) / Double(expected))) : nil }
    var localURL: URL? { filename.map { AppPaths.directory.appendingPathComponent("Downloads").appendingPathComponent($0) } }
}
enum FileNames {
    static func safe(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:\0\n\r")).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "download" : cleaned).prefix(150))
    }
}
enum ContentBlocking {
    static func rules(trackers: Bool, ads: Bool, extraDomains: String = "") -> [[String: Any]] {
        var domains = trackers ? ["google-analytics.com", "doubleclick.net", "googletagmanager.com", "facebook.net"] : []
        if ads { domains += ["googlesyndication.com", "adservice.google.com", "adsrvr.org"] }
        domains += extraDomains.components(separatedBy: .whitespacesAndNewlines).map { $0.lowercased() }.filter { $0.range(of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)*\.[a-z]{2,}$"#, options: .regularExpression) != nil }
        var result: [[String: Any]] = Array(Set(domains)).sorted().map { domain in
            ["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]", "load-type": ["third-party"]], "action": ["type": "block"]]
        }
        if ads { result.append(["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": ".advertisement,[data-ad-slot],iframe[src*='doubleclick.net']"]]) }
        return result
    }
}

struct SubtitleCue: Equatable {
    var start: Double
    var end: Double
    var text: String
}
enum SubtitleParser {
    static func parse(_ input: String) -> [SubtitleCue] {
        let blocks = input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        func seconds(_ value: String) -> Double? {
            let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":")
            guard (2...3).contains(parts.count), let last = Double(parts.last!), let minutes = Double(parts[parts.count-2]) else { return nil }
            let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
            return hours * 3600 + minutes * 60 + last
        }
        return blocks.compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let times = lines[index].components(separatedBy: "-->")
            guard times.count == 2, let start = seconds(times[0].trimmingCharacters(in: .whitespaces)),
                  let end = seconds(String(times[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "")), end > start else { return nil }
            return SubtitleCue(start: start, end: end, text: lines.dropFirst(index+1).joined(separator: "\n").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        }.sorted { $0.start < $1.start }
    }
}

enum SiteOrigin {
    static func key(url: URL?) -> String { guard let url, let scheme = url.scheme, let host = url.host else { return "" }; return key(scheme: scheme, host: host, port: url.port ?? 0) }
    static func key(scheme: String, host: String, port: Int) -> String {
        let scheme = scheme.lowercased(), host = host.lowercased()
        let name = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let defaultPort = port == 0 || (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        return scheme + "://" + name + (defaultPort ? "" : ":\(port)")
    }
}
