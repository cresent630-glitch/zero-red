import SwiftUI
import AVFoundation

struct StreamDownload: Identifiable, Codable {
    var id = UUID()
    var source: URL
    var title: String
    var progress = 0.0
    var localURL: URL?
    var state = "running"
    var error: String?
}
@MainActor
final class StreamingDownloads: NSObject, ObservableObject, AVAssetDownloadDelegate {
    static let shared = StreamingDownloads()
    @Published var items: [StreamDownload] = []
    var backgroundCompletion: (() -> Void)?
    private var tasks: [UUID: AVAssetDownloadTask] = [:]
    private var manifest: URL { AppPaths.directory.appendingPathComponent("streams.json") }
    private lazy var session = AVAssetDownloadURLSession(configuration: .background(withIdentifier: "com.zerored.browser.streams"), assetDownloadDelegate: self, delegateQueue: .main)
    override init() {
        super.init()
        if let data = try? Data(contentsOf: manifest) { items = (try? JSONDecoder().decode([StreamDownload].self, from: data)) ?? [] }
        Task {
            let restored = await session.allTasks
            for case let task as AVAssetDownloadTask in restored { if let raw = task.taskDescription, let id = UUID(uuidString: raw) { tasks[id] = task } }
            for index in items.indices where items[index].state == "running" && tasks[items[index].id] == nil { items[index].state = "failed"; items[index].error = "下载中断 / Interrupted" }
            save()
        }
    }
    private func save() {
        do { try FileManager.default.createDirectory(at: AppPaths.directory, withIntermediateDirectories: true); try JSONEncoder().encode(items).write(to: manifest, options: .atomic) }
        catch { if !items.isEmpty { items[0].error = error.localizedDescription } }
    }
    func start(_ source: URL, title: String, cookies: [HTTPCookie] = []) async {
        guard !items.contains(where: { $0.source == source && ["running", "complete"].contains($0.state) }) else { return }
        let asset = AVURLAsset(url: source, options: [AVURLAssetHTTPCookiesKey: VideoPolicy.cookies(cookies, for: source)])
        do {
            let protected = try await asset.load(.hasProtectedContent)
            guard !protected else { throw CocoaError(.fileReadNoPermission) }
            let item = StreamDownload(source: source, title: title)
            guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: title, assetArtworkData: nil, options: nil) else { throw URLError(.unsupportedURL) }
            task.taskDescription = item.id.uuidString; items.insert(item, at: 0); tasks[item.id] = task; save(); task.resume()
        } catch { items.insert(StreamDownload(source: source, title: title, state: "failed", error: error.localizedDescription), at: 0); save() }
    }
    func pause(_ item: StreamDownload) { tasks[item.id]?.suspend(); update(item.id) { $0.state = "paused" } }
    func resume(_ item: StreamDownload) {
        if let task = tasks[item.id] { task.resume(); update(item.id) { $0.state = "running" } }
        else { remove(item); Task { await start(item.source, title: item.title) } }
    }
    func remove(_ item: StreamDownload) {
        tasks.removeValue(forKey: item.id)?.cancel()
        if let url = item.localURL { try? FileManager.default.removeItem(at: url) }
        items.removeAll { $0.id == item.id }; save()
    }
    private func update(_ id: UUID, _ body: (inout StreamDownload) -> Void) { if let i = items.firstIndex(where: { $0.id == id }) { body(&items[i]); save() } }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let raw = assetDownloadTask.taskDescription, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.update(id) { $0.localURL = location; $0.state = "complete"; $0.progress = 1 }; self.tasks.removeValue(forKey: id) }
    }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let raw = assetDownloadTask.taskDescription, let id = UUID(uuidString: raw) else { return }
        let total = CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + CMTimeGetSeconds($1.timeRangeValue.duration) }
        Task { @MainActor in self.update(id) { $0.progress = total > 0 ? min(1, loaded / total) : 0 } }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let raw = task.taskDescription, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.update(id) { $0.state = "failed"; $0.error = error.localizedDescription }; self.tasks.removeValue(forKey: id) }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in let completion = self.backgroundCompletion; self.backgroundCompletion = nil; completion?() }
    }
}
