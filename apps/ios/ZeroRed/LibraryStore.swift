import SwiftUI
import AVFoundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private var snapshot = LibrarySnapshot()
    var bookmarks: [PageEntry] {
        get { snapshot.bookmarks }
        set { update { $0.bookmarks = newValue } }
    }
    var history: [PageEntry] {
        get { snapshot.history }
        set { update { $0.history = newValue } }
    }
    var videos: [CachedVideo] { snapshot.videos }
    @Published var language: String = "system" { didSet { preferences.set(language, forKey: "language") } }
    @Published var options = BrowserOptions() { didSet { if let data = try? JSONEncoder().encode(options) { preferences.set(data, forKey: "options") } } }
    @Published var sitePolicies: [String: SitePolicy] = [:] { didSet { if let data = try? JSONEncoder().encode(sitePolicies) { preferences.set(data, forKey: "sitePolicies") } } }
    func policy(for host: String) -> SitePolicy { sitePolicies[host.lowercased()] ?? SitePolicy() }
    @Published var downloading = false
    @Published var downloadError: String?
    private var preferences: UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return UserDefaults(suiteName: "com.zerored.browser.uitests") ?? .standard
        }
        #endif
        return .standard
    }
    private var canWriteLibrary = true
    private let repository = LibraryRepository(directory: AppPaths.directory)
    var locale: Locale { language == "system" ? .current : Locale(identifier: language) }
    var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    init() {
        language = preferences.string(forKey: "language") ?? "system"
        if let data = preferences.data(forKey: "options"), let value = try? JSONDecoder().decode(BrowserOptions.self, from: data) { options = value }
        if let data = preferences.data(forKey: "sitePolicies"), let value = try? JSONDecoder().decode([String: SitePolicy].self, from: data) { sitePolicies = value }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"), ProcessInfo.processInfo.arguments.contains("-reset-library") {
            try? FileManager.default.removeItem(at: AppPaths.directory)
            preferences.removeObject(forKey: "language")
            language = "system"
        }
        #endif
        do { snapshot = try repository.load() }
        catch {
            canWriteLibrary = false
            downloadError = text("本地资料读取失败，原文件已保留：", "Could not read library; original file preserved: ") + error.localizedDescription
        }
    }
    @discardableResult
    private func update(_ change: (inout LibrarySnapshot) -> Void) -> Bool {
        guard canWriteLibrary else {
            downloadError = text("资料文件损坏，已暂停写入以保留原文件。", "Library file is damaged. Writes are paused to preserve it.")
            return false
        }
        var next = snapshot
        change(&next)
        do {
            try repository.save(next)
            snapshot = next
            return true
        } catch {
            downloadError = text("无法保存本地资料：", "Could not save library: ") + error.localizedDescription
            return false
        }
    }
    func record(_ url: URL, title: String) { update { $0.record(url, title: title) } }
    func bookmark(_ url: URL, title: String) { update { $0.bookmark(url, title: title) } }
    func removeVideo(_ video: CachedVideo) {
        let previous = snapshot
        guard update({ $0.videos.removeAll { $0.id == video.id } }) else { return }
        do {
            if FileManager.default.fileExists(atPath: video.localURL.path) { try FileManager.default.removeItem(at: video.localURL) }
        } catch {
            _ = update { $0 = previous }
            downloadError = error.localizedDescription
        }
    }
    func cacheVideo(_ url: URL, referer: URL?, cookies: [HTTPCookie]) async {
        guard !downloading else { return }
        downloading = true
        defer { downloading = false }
        do {
            let video = try await VideoDownloader().download(url, to: AppPaths.directory, cookies: cookies, referer: referer)
            do {
                let asset = AVURLAsset(url: video.localURL)
                let playable = try await asset.load(.isPlayable)
                let protected = try await asset.load(.hasProtectedContent)
                guard playable, !protected else { throw VideoPolicy.ValidationError.unsupported }
                guard update({ $0.videos.insert(video, at: 0) }) else {
                    try? FileManager.default.removeItem(at: video.localURL)
                    return
                }
            } catch {
                try? FileManager.default.removeItem(at: video.localURL)
                throw error
            }
        } catch {
            downloadError = (error is VideoPolicy.ValidationError) ? text("无法缓存此视频。仅支持可下载、未加密且设备可播放的 MP4/MOV。", "Cannot save this video. Use downloadable, unencrypted MP4/MOV supported by this device.") : error.localizedDescription
        }
    }
}
