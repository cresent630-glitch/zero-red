import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct PlayableItem: Identifiable {
    var id = UUID()
    var url: URL
    var title: String
    var source: URL?
    var cookies: [HTTPCookie] = []
    var startTime: Double = 0
}
@MainActor
final class NativePlayerModel: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    let player: AVPlayer
    @Published var interacting = false
    @Published var playing = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var controlsVisible = true
    @Published var rate: Float = 1
    @Published var notice: String?
    @Published var captions: [AVMediaSelectionOption] = []
    @Published var cueText = ""
    @Published var pictureInPicturePossible = false
    var pip: AVPictureInPictureController?
    private var group: AVMediaSelectionGroup?
    private var observer: Any?
    private var status: NSKeyValueObservation?
    private var pipObservation: NSKeyValueObservation?
    private var hiding: Task<Void, Never>?
    private var cues: [SubtitleCue] = []
    init(url: URL, cookies: [HTTPCookie] = [], startTime: Double = 0) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: VideoPolicy.cookies(cookies, for: url)])
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset)); super.init(); player.allowsExternalPlayback = true
        if startTime.isFinite && startTime > 0 { player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600)) }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.3, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }; self.position = max(0, time.seconds.isFinite ? time.seconds : 0)
                let seconds = self.player.currentItem?.duration.seconds ?? 0; self.duration = seconds.isFinite ? max(0, seconds) : 0
                self.playing = self.player.rate > 0; self.cueText = self.cues.first(where: { $0.start <= self.position && self.position < $0.end })?.text ?? ""
                if !self.playing { self.controlsVisible = true }
            }
        }
        status = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in if item.status == .failed { self?.notice = item.error?.localizedDescription ?? "无法播放 / Playback failed" } }
        }
        Task {
            if let asset = player.currentItem?.asset, let group = try? await asset.loadMediaSelectionGroup(for: .legible) { self.group = group; captions = group.options }
        }
    }
    func attach(_ layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        pip = AVPictureInPictureController(playerLayer: layer); pip?.delegate = self
        pipObservation = pip?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in Task { @MainActor in self?.pictureInPicturePossible = pip.isPictureInPicturePossible } }
    }
    func start() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try AVAudioSession.sharedInstance().setActive(true); player.playImmediately(atRate: rate); reveal() }
        catch { notice = error.localizedDescription }
    }
    func toggle() { if player.rate > 0 { player.pause(); reveal() } else { start() } }
    func reveal() {
        controlsVisible = true; hiding?.cancel()
        hiding = Task { [weak self] in try? await Task.sleep(for: .milliseconds(2400)); guard !Task.isCancelled, let self, self.player.rate > 0, !self.interacting, !UIAccessibility.isVoiceOverRunning else { return }; self.controlsVisible = false }
    }
    func toggleControls() { if controlsVisible && player.rate > 0 { controlsVisible = false; hiding?.cancel() } else { reveal() } }
    func selectCaption(_ option: AVMediaSelectionOption?) { if let group { player.currentItem?.select(option, in: group) }; cues = []; cueText = "" }
    func importCaptions(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
        guard let value = ReadingText.decode(try Data(contentsOf: url)) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let parsed = SubtitleParser.parse(value); if parsed.isEmpty { throw CocoaError(.fileReadCorruptFile) }; selectCaption(nil); cues = parsed
    }
    func stop() { hiding?.cancel(); pip?.stopPictureInPicture(); player.pause(); if let observer { player.removeTimeObserver(observer); self.observer = nil } }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.notice = message }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(true) }
}
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
struct PlayerSurface: UIViewRepresentable {
    @ObservedObject var model: NativePlayerModel
    func makeUIView(context: Context) -> PlayerLayerView { let view = PlayerLayerView(); view.playerLayer.player = model.player; view.playerLayer.videoGravity = .resizeAspect; model.attach(view.playerLayer); return view }
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.tintColor = .white; view.activeTintColor = .white; view.prioritizesVideoDevices = true; return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
@MainActor
struct NativePlayer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var streams = StreamingDownloads.shared
    let item: PlayableItem
    @StateObject private var model: NativePlayerModel
    @State private var importingCaption = false
    init(item: PlayableItem) { self.item = item; _model = StateObject(wrappedValue: NativePlayerModel(url: item.url, cookies: item.cookies, startTime: item.startTime)) }
    private var source: URL { item.source ?? item.url }
    private var cached: Bool { item.url.isFileURL || downloads.jobs.contains { $0.url == source && $0.state == .complete && $0.kind == "video" } || streams.items.contains { $0.source == source && $0.state == "complete" } }
    private var caching: Bool { downloads.jobs.contains { $0.url == source && $0.state == .running } || streams.items.contains { $0.source == source && $0.state == "running" } }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(model: model).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { model.toggleControls() }
            if !model.cueText.isEmpty { VStack { Spacer(); Text(model.cueText).foregroundStyle(.white).padding(8).background(.black.opacity(0.6)).padding(.bottom, model.controlsVisible ? 115 : 45) }.allowsHitTesting(false) }
            if model.controlsVisible {
                VStack {
                    HStack { button("xmark", library.text("关闭", "Close")) { dismiss() }; Spacer(); Text(item.title).font(.caption).lineLimit(1); Spacer(); if model.pictureInPicturePossible { button("pip.enter", library.text("画中画", "Picture in Picture")) { model.pip?.startPictureInPicture(); model.reveal() } } }
                    Spacer()
                    VStack(spacing: 4) {
                        Slider(value: Binding(get: { min(model.position, max(model.duration, 1)) }, set: { value in model.player.seek(to: CMTime(seconds: value, preferredTimescale: 600)); model.reveal() }), in: 0...max(model.duration, 1), onEditingChanged: { editing in model.interacting = editing; model.reveal() }).disabled(model.duration <= 0).tint(.white).accessibilityLabel(library.text("播放进度", "Playback position"))
                        HStack {
                            button(model.playing ? "pause.fill" : "play.fill", library.text("播放或暂停", "Play or pause")) { model.toggle() }
                            Text(time(model.position) + " / " + time(model.duration)).font(.caption.monospacedDigit())
                            Spacer()
                            Menu { ForEach([Float(0.5), 1, 1.25, 1.5, 2], id: \.self) { value in Button("\(value.formatted())×") { model.rate = value; if model.playing { model.player.rate = value }; model.reveal() } } } label: { Text("\(model.rate.formatted())×").font(.caption).frame(minWidth: 36, minHeight: 44) }
                            Menu { Button(library.text("关闭字幕", "Captions off")) { model.selectCaption(nil) }; ForEach(Array(model.captions.enumerated()), id: \.offset) { _, option in Button(option.displayName) { model.selectCaption(option) } }; Button(library.text("导入 SRT / VTT", "Import SRT / VTT")) { importingCaption = true } } label: { Image(systemName: "captions.bubble").frame(width: 44, height: 44) }
                            AirPlayButton().frame(width: 35, height: 35)
                            button(cached ? "checkmark" : caching ? "hourglass" : "arrow.down.to.line", library.text(cached ? "已缓存" : "缓存当前视频", cached ? "Saved" : "Save current video")) {
                                if source.pathExtension.lowercased() == "m3u8" { Task { await streams.start(source, title: item.title, cookies: item.cookies) } }
                                else { _ = downloads.start(source, cookies: item.cookies, kind: "video") }
                                model.reveal()
                            }.disabled(cached || caching)
                        }
                    }
                }.padding().foregroundStyle(.white).background(LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.controlsVisible)
        .accessibilityIdentifier("offlinePlayer")
        .onChange(of: downloads.error) { _, value in if let value { model.notice = value; downloads.error = nil } }
        .onAppear { model.start() }.onDisappear { model.stop() }
        .fileImporter(isPresented: $importingCaption, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: false) { result in do { if let url = try result.get().first { try model.importCaptions(url) } } catch { model.notice = error.localizedDescription } }
        .alert(library.text("提示", "Notice"), isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button(library.text("好", "OK")) { model.notice = nil } } message: { Text(model.notice ?? "") }
    }
    private func time(_ value: Double) -> String { let seconds = max(0, Int(value.isFinite ? value : 0)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(label) }
}
