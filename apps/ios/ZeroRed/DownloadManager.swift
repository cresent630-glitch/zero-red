import SwiftUI
import WebKit
import AVFoundation

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    @Published private(set) var jobs: [DownloadRecord] = []
    @Published var error: String?
    var backgroundCompletion: (() -> Void)?
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var webDownloads: [UUID: WKDownload] = [:]
    private var adapters: [UUID: WebDownloadAdapter] = [:]
    private var progressSave: Task<Void, Never>?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.zerored.browser.downloads")
        configuration.sessionSendsLaunchEvents = true; configuration.isDiscretionary = false
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var folder: URL { AppPaths.directory.appendingPathComponent("Downloads", isDirectory: true) }
    private var manifest: URL { folder.appendingPathComponent("downloads.json") }
    override init() {
        super.init()
        if let data = try? Data(contentsOf: manifest) { jobs = (try? JSONDecoder().decode([DownloadRecord].self, from: data)) ?? [] }
        Task {
            let restored = await session.allTasks
            for case let task as URLSessionDownloadTask in restored {
                if let string = task.taskDescription, let id = UUID(uuidString: string) { tasks[id] = task }
            }
            for index in jobs.indices where jobs[index].state == .running && tasks[jobs[index].id] == nil {
                jobs[index].state = .failed; jobs[index].error = "下载中断，可重试。 / Interrupted. Retry available."
            }
            persist()
        }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(jobs).write(to: manifest, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    func change(_ id: UUID, _ body: (inout DownloadRecord) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }; body(&jobs[index]); persist()
    }
    @discardableResult
    func start(_ url: URL, cookies: [HTTPCookie] = [], kind: String = "file") -> UUID? {
        guard AddressResolver.webURL(url.absoluteString) != nil else { error = "无效的下载网址 / Invalid download URL"; return nil }
        if let available = try? AppPaths.directory.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, available < 50 * 1024 * 1024 { error = "存储空间不足 / Not enough storage"; return nil }
        let job = DownloadRecord(url: url, name: FileNames.safe(url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent), kind: kind)
        var request = URLRequest(url: url)
        for (key, value) in HTTPCookie.requestHeaderFields(with: VideoPolicy.cookies(cookies, for: url)) { request.setValue(value, forHTTPHeaderField: key) }
        jobs.insert(job, at: 0)
        let task = session.downloadTask(with: request); task.taskDescription = job.id.uuidString; tasks[job.id] = task; persist(); task.resume(); return job.id
    }
    func accept(_ download: WKDownload, source: URL?, existingID: UUID? = nil) {
        let url = source ?? download.originalRequest?.url ?? URL(string: "https://localhost/")!
        let id: UUID
        if let existingID { id = existingID; change(id) { $0.state = .running; $0.error = nil } }
        else { let job = DownloadRecord(url: url, name: "download", kind: "webkit"); id = job.id; jobs.insert(job, at: 0) }
        let adapter = WebDownloadAdapter(id: id, manager: self); adapters[id] = adapter; webDownloads[id] = download; download.delegate = adapter; adapter.observe(download); persist()
    }
    func pause(_ id: UUID) {
        change(id) { $0.state = .paused }
        if let task = tasks.removeValue(forKey: id) {
            task.cancel { [weak self] data in Task { @MainActor in self?.change(id) { $0.resumeData = data } } }
        } else if let download = webDownloads[id] {
            download.cancel { [weak self] data in self?.change(id) { $0.resumeData = data }; self?.webDownloads.removeValue(forKey: id); self?.adapters.removeValue(forKey: id) }
        }
    }
    func cancel(_ id: UUID) {
        change(id) { $0.state = .cancelled; $0.resumeData = nil }
        tasks.removeValue(forKey: id)?.cancel(); webDownloads[id]?.cancel(nil); webDownloads.removeValue(forKey: id); adapters.removeValue(forKey: id)
    }
    func retry(_ job: DownloadRecord, webView: WKWebView) {
        guard job.state != .running else { return }
        if job.kind == "webkit" {
            guard let data = job.resumeData else { error = "请在原网页重新发起此下载。 / Restart this download from its original page."; return }
            webView.resumeDownload(fromResumeData: data) { [weak self] download in self?.accept(download, source: job.url, existingID: job.id) }
        } else {
            let task = job.resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: job.url)
            task.taskDescription = job.id.uuidString; tasks[job.id] = task
            change(job.id) { $0.state = .running; $0.error = nil; $0.resumeData = nil }; task.resume()
        }
    }
    func remove(_ job: DownloadRecord) {
        cancel(job.id)
        do { if let url = job.localURL, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }; jobs.removeAll { $0.id == job.id }; persist() }
        catch { self.error = error.localizedDescription }
    }
    func finish(_ id: UUID, filename: String) {
        change(id) { $0.filename = filename; $0.state = .complete; $0.resumeData = nil; $0.error = nil }
        tasks.removeValue(forKey: id); webDownloads.removeValue(forKey: id); adapters.removeValue(forKey: id)
    }
    func fail(_ id: UUID, error: Error, resume: Data?) {
        guard let job = jobs.first(where: { $0.id == id }), ![.paused, .cancelled, .complete].contains(job.state) else { return }
        change(id) { $0.state = .failed; $0.error = error.localizedDescription; $0.resumeData = resume }
        self.error = error.localizedDescription
        tasks.removeValue(forKey: id); webDownloads.removeValue(forKey: id); adapters.removeValue(forKey: id)
    }
    func progress(_ id: UUID, received: Int64, expected: Int64) {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.state == .running }) else { return }
        jobs[index].received = received; jobs[index].expected = expected
        progressSave?.cancel(); progressSave = Task { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { persist() } }
    }
    var bytes: Int64 { jobs.compactMap(\.localURL).reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } }
}
extension DownloadManager: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let value = downloadTask.taskDescription, let id = UUID(uuidString: value) else { return }
        let taskID = downloadTask.taskIdentifier
        Task { @MainActor in if self.tasks[id]?.taskIdentifier == taskID { self.progress(id, received: totalBytesWritten, expected: totalBytesExpectedToWrite) } }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let value = downloadTask.taskDescription, let id = UUID(uuidString: value) else { return }
        let taskID = downloadTask.taskIdentifier
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 else { throw URLError(.zeroByteResource) }
            let folder = AppPaths.directory.appendingPathComponent("Downloads", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = FileNames.safe(response.suggestedFilename ?? "download")
            let filename = id.uuidString + "-" + UUID().uuidString + "-" + name
            try FileManager.default.moveItem(at: location, to: folder.appendingPathComponent(filename))
            let destination = folder.appendingPathComponent(filename)
            let mime = response.mimeType?.lowercased() ?? ""
            Task { @MainActor in
                guard self.tasks[id]?.taskIdentifier == taskID, let job = self.jobs.first(where: { $0.id == id }), job.state == .running else { try? FileManager.default.removeItem(at: destination); return }
                do {
                    if job.kind == "video" {
                        guard ["video/mp4", "video/quicktime", "video/x-m4v"].contains(mime) else { throw URLError(.cannotDecodeContentData) }
                        let asset = AVURLAsset(url: destination)
                        let playable = try await asset.load(.isPlayable), protected = try await asset.load(.hasProtectedContent)
                        guard playable && !protected else { throw URLError(.cannotDecodeContentData) }
                    }
                    guard self.tasks[id]?.taskIdentifier == taskID, self.jobs.first(where: { $0.id == id })?.state == .running else { try? FileManager.default.removeItem(at: destination); return }
                    self.change(id) { $0.name = name; $0.received = Int64(size); $0.expected = Int64(size) }; self.finish(id, filename: filename)
                } catch { try? FileManager.default.removeItem(at: destination); self.fail(id, error: error, resume: nil) }
            }
        } catch { Task { @MainActor in if self.tasks[id]?.taskIdentifier == taskID { self.fail(id, error: error, resume: nil) } } }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let value = task.taskDescription, let id = UUID(uuidString: value) else { return }
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let taskID = task.taskIdentifier
        Task { @MainActor in if self.tasks[id]?.taskIdentifier == taskID { self.fail(id, error: error, resume: resume) } }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, AddressResolver.webURL(url.absoluteString) != nil, !(response.url?.scheme == "https" && url.scheme == "http") else { completionHandler(nil); return }
        var redirected = request
        redirected.setValue(nil, forHTTPHeaderField: "Cookie")
        if response.url?.host != url.host { redirected.setValue(nil, forHTTPHeaderField: "Authorization"); redirected.setValue(nil, forHTTPHeaderField: "Referer") }
        completionHandler(redirected)
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in let completion = self.backgroundCompletion; self.backgroundCompletion = nil; completion?() }
    }
}
@MainActor
private final class WebDownloadAdapter: NSObject, WKDownloadDelegate {
    let id: UUID
    weak var manager: DownloadManager?
    var observation: NSKeyValueObservation?
    var filename: String?
    init(id: UUID, manager: DownloadManager) { self.id = id; self.manager = manager }
    func observe(_ download: WKDownload) {
        observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Task { @MainActor in guard let self else { return }; self.manager?.progress(self.id, received: progress.completedUnitCount, expected: progress.totalUnitCount) }
        }
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        do {
            let folder = AppPaths.directory.appendingPathComponent("Downloads", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = FileNames.safe(suggestedFilename); let filename = id.uuidString + "-" + UUID().uuidString + "-" + name; self.filename = filename
            manager?.change(id) { $0.name = name; $0.filename = filename }; completionHandler(folder.appendingPathComponent(filename))
        } catch { completionHandler(nil); manager?.fail(id, error: error, resume: nil) }
    }
    func downloadDidFinish(_ download: WKDownload) { if let filename { manager?.finish(id, filename: filename) } }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { manager?.fail(id, error: error, resume: resumeData) }
    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        decisionHandler(response.url?.scheme == "https" && request.url?.scheme == "http" ? .cancel : .allow)
    }
    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { completionHandler(.performDefaultHandling, nil) }
}
@MainActor
final class BackgroundAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if identifier == "com.zerored.browser.downloads" { DownloadManager.shared.backgroundCompletion = completionHandler }
        else if identifier == "com.zerored.browser.streams" { StreamingDownloads.shared.backgroundCompletion = completionHandler }
        else { completionHandler() }
    }
}
