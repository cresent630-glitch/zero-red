import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum AppPaths {
    static var directory: URL {
        #if DEBUG
        let folder = ProcessInfo.processInfo.arguments.contains("-ui-testing") ? "ZeroRedUITests" : "ZeroRed"
        #else
        let folder = "ZeroRed"
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folder, isDirectory: true)
    }
}

struct PageEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var date = Date()
}
struct CachedVideo: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var filename: String
    var date = Date()
    var localURL: URL { AppPaths.directory.appendingPathComponent(filename) }
}
struct LibrarySnapshot: Codable, Equatable {
    var bookmarks: [PageEntry] = []
    var history: [PageEntry] = []
    var videos: [CachedVideo] = []

    mutating func record(_ url: URL, title: String, now: Date = Date()) {
        if history.first?.url == url {
            history[0].title = title
            history[0].date = now
        } else {
            history.insert(PageEntry(title: title, url: url, date: now), at: 0)
        }
        if history.count > 1000 { history.removeLast(history.count - 1000) }
    }
    mutating func bookmark(_ url: URL, title: String) {
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.insert(PageEntry(title: title, url: url), at: 0)
    }
}
struct LibraryRepository {
    let directory: URL
    var manifest: URL { directory.appendingPathComponent("library.json") }
    func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return LibrarySnapshot() }
        return try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: manifest))
    }
    func save(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: manifest, options: .atomic)
    }
}

enum AddressResolver {
    static func resolve(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = webURL(value) { return url }
        // Explicit unsupported schemes must never be rewritten into HTTPS URLs.
        let explicitScheme = value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil
        if !explicitScheme, !value.contains(where: { $0.isWhitespace }), !value.contains("@") {
            let candidate = "https://" + value
            if let url = webURL(candidate), let host = url.host,
               host.contains(".") || host == "localhost" || host.contains(":") { return url }
        }
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: value)]
        return components.url
    }
    static func webURL(_ input: String) -> URL? {
        guard !input.contains(where: { $0.isWhitespace }),
              let parts = URLComponents(string: input),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.port == nil || (1...65535).contains(parts.port!), let url = parts.url else { return nil }
        return url
    }
}

enum VideoPolicy {
    static func supports(_ url: URL) -> Bool {
        AddressResolver.webURL(url.absoluteString) != nil && !["m3u8", "mpd"].contains(url.pathExtension.lowercased())
    }
    static func fileExtension(status: Int, mime: String?, byteCount: Int64) throws -> String {
        guard status == 200 else { throw ValidationError.http(status) }
        guard byteCount > 0 else { throw ValidationError.empty }
        switch mime?.lowercased().split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) {
        case "video/mp4", "video/x-m4v": return "mp4"
        case "video/quicktime": return "mov"
        default: throw ValidationError.unsupported
        }
    }
    static func cookies(_ cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> [HTTPCookie] {
        cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let bareDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let host = url.host?.lowercased() ?? ""
            let path = url.path.isEmpty ? "/" : url.path
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = path == cookiePath || (path.hasPrefix(cookiePath) && (cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).hasPrefix("/")))
            return (host == bareDomain || (domain.hasPrefix(".") && host.hasSuffix("." + bareDomain)))
                && pathMatches && (!cookie.isSecure || url.scheme?.lowercased() == "https")
                && (cookie.expiresDate == nil || cookie.expiresDate! > now)
        }
    }
    enum ValidationError: Error { case http(Int), empty, unsupported }
}

// A fresh cookie header is generated for every redirect destination. Never forward
// the original page's Cookie/Referer header to an unrelated redirect host.
final class VideoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let cookies: [HTTPCookie]
    init(cookies: [HTTPCookie]) { self.cookies = cookies }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, VideoPolicy.supports(url),
              !(response.url?.scheme == "https" && url.scheme == "http") else { completionHandler(nil); return }
        var redirected = request
        redirected.setValue(nil, forHTTPHeaderField: "Cookie")
        if response.url?.host?.lowercased() != url.host?.lowercased() {
            redirected.setValue(nil, forHTTPHeaderField: "Referer")
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        for (key, value) in HTTPCookie.requestHeaderFields(with: VideoPolicy.cookies(cookies, for: url)) {
            redirected.setValue(value, forHTTPHeaderField: key)
        }
        completionHandler(redirected)
    }
}

struct VideoDownloader {
    func download(_ url: URL, to directory: URL, cookies: [HTTPCookie] = [], referer: URL? = nil) async throws -> CachedVideo {
        guard VideoPolicy.supports(url) else { throw VideoPolicy.ValidationError.unsupported }
        var request = URLRequest(url: url)
        // Origin only: do not expose page paths / query tokens to video servers.
        if let referer, var origin = URLComponents(url: referer, resolvingAgainstBaseURL: false),
           !(referer.scheme == "https" && url.scheme == "http") {
            origin.path = "/"; origin.query = nil; origin.fragment = nil; origin.user = nil; origin.password = nil
            request.setValue(origin.url?.absoluteString, forHTTPHeaderField: "Referer")
        }
        for (key, value) in HTTPCookie.requestHeaderFields(with: VideoPolicy.cookies(cookies, for: url)) { request.setValue(value, forHTTPHeaderField: key) }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: config, delegate: VideoRedirectDelegate(cookies: cookies), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse else { throw VideoPolicy.ValidationError.unsupported }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let ext = try VideoPolicy.fileExtension(status: http.statusCode, mime: http.mimeType, byteCount: Int64(size))
        let id = UUID()
        let filename = "\(id.uuidString).\(ext)"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temporary, to: directory.appendingPathComponent(filename))
        return CachedVideo(id: id, title: url.lastPathComponent.isEmpty ? "Video" : url.lastPathComponent, filename: filename)
    }
}
