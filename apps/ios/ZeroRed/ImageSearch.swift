import SwiftUI
import ImageIO
import PhotosUI
import UIKit
import Vision

struct SearchImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 图片搜索入口：相册或拍照 → 本机识别图中文字与内容 → 选中结果直接搜网页。
/// 不依赖任何第三方识图 API，图片只在本机处理，不上传。
struct ImageSearchButton: View {
    @EnvironmentObject private var library: LibraryStore
    var onSearch: (String) -> Void
    @State private var choosing = false
    @State private var pickingPhoto = false
    @State private var cameraVisible = false
    @State private var photoItem: PhotosPickerItem?
    @State private var candidate: SearchImage?

    var body: some View {
        Button { choosing = true } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(library.text("图片搜索", "Search by image"))
        .accessibilityIdentifier("imageSearch")
        .confirmationDialog(library.text("用图片搜索", "Search with an image"), isPresented: $choosing, titleVisibility: .visible) {
            Button(library.text("从相册选择", "Choose from library")) { pickingPhoto = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(library.text("拍照", "Take a photo")) { cameraVisible = true }
            }
            Button(library.text("取消", "Cancel"), role: .cancel) {}
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in load(item) }
        .fullScreenCover(isPresented: $cameraVisible) {
            CameraPicker(onImage: { image in cameraVisible = false; candidate = SearchImage(image: image) },
                         onCancel: { cameraVisible = false })
                .ignoresSafeArea()
        }
        .sheet(item: $candidate) { image in
            SearchImageSheet(image: image.image) { keyword in
                onSearch(keyword)
            }
        }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                candidate = SearchImage(image: image)
            }
            photoItem = nil
        }
    }
}

/// 识别结果：优先用图中的文字，识别不到再退回物体/场景标签。
struct SearchImageSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var image: UIImage
    var onSearch: (String) -> Void
    @State private var keywords: [String] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(library.text("正在本机识别…", "Reading the image on device…")).font(.footnote).foregroundStyle(.secondary)
                        }
                    } else if keywords.isEmpty {
                        Text(library.text("没有识别到可搜索的文字或内容。换一张更清晰、主体更明确的图片试试。", "Nothing searchable was recognised. Try a sharper image with a clear subject."))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(library.text("选择要搜索的内容", "Choose something to search"))
                            .font(.footnote).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(keywords, id: \.self) { keyword in
                                Button { onSearch(keyword); dismiss() } label: {
                                    Text(keyword).font(.subheadline).lineLimit(1)
                                        .padding(.horizontal, 14).padding(.vertical, 9)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .zeroRedGlass(Capsule(), interactive: true)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .navigationTitle(library.text("图片搜索", "Search by image"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { GlassProminentButton(title: library.text("完成", "Done")) { dismiss() } } }
            .task {
                keywords = await ImageKeywords.extract(from: image)
                loading = false
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

enum ImageKeywords {
    /// 本机 Vision：先 OCR 文字，再补物体/场景分类；去重后最多 8 条。
    static func extract(from image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImageOrientation)
        var collected: [String] = []

        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        if (try? handler.perform([text])) != nil {
            for observation in text.results ?? [] {
                if let line = observation.topCandidates(1).first?.string { collected.append(line) }
            }
        }

        if collected.isEmpty {
            let classify = VNClassifyImageRequest()
            if (try? handler.perform([classify])) != nil {
                collected = (classify.results ?? [])
                    .filter { $0.confidence > 0.3 }
                    .prefix(5)
                    .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            }
        }

        var seen = Set<String>()
        var output: [String] = []
        for raw in collected {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard value.count >= 2, value.count <= 40 else { continue }
            guard seen.insert(value.lowercased()).inserted else { continue }
            output.append(value)
            if output.count == 8 { break }
        }
        return output
    }
}

private extension UIImage {
    /// CGImage 方向映射，避免竖拍照片识别时被转 90 度。
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) } else { parent.onCancel() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}