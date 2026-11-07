import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

@MainActor
final class ReadingLibrary: ObservableObject {
    @Published private(set) var documents: [ReadingDocument] = []
    @Published var error: String?
    private var writable = true
    private let folder = AppPaths.directory.appendingPathComponent("Reading", isDirectory: true)
    private var manifest: URL { folder.appendingPathComponent("documents.json") }
    init() {
        if FileManager.default.fileExists(atPath: manifest.path) {
            do { documents = try JSONDecoder().decode([ReadingDocument].self, from: Data(contentsOf: manifest)) }
            catch { writable = false; self.error = error.localizedDescription }
        }
    }
    private func commit(_ next: [ReadingDocument]) throws {
        guard writable else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: manifest, options: .atomic)
        documents = next
    }
    @discardableResult
    func save(_ document: ReadingDocument) throws -> ReadingDocument {
        guard document.text.count <= ReadingText.limit else { throw CocoaError(.fileReadTooLarge) }
        var next = documents
        if let index = next.firstIndex(where: { $0.id == document.id || (!document.source.isEmpty && $0.source == document.source && $0.text == document.text) }) {
            var updated = document; updated.id = next[index].id; updated.progress = max(updated.progress, next[index].progress)
            next[index] = updated; try commit(next); return updated
        }
        next.insert(document, at: 0); try commit(next); return document
    }
    func update(_ document: ReadingDocument) { do { _ = try save(document) } catch { self.error = error.localizedDescription } }
    func delete(_ document: ReadingDocument) {
        do {
            try commit(documents.filter { $0.id != document.id })
            if let url = document.originalURL { try? FileManager.default.removeItem(at: url) }
        } catch { self.error = error.localizedDescription }
    }
    func importFile(_ url: URL) throws -> ReadingDocument {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        var text = ""
        switch ext {
        case "pdf":
            guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount <= 500 else { throw CocoaError(.fileReadCorruptFile) }
            text = pdf.string ?? ""
        case "docx":
            let archive = try Archive(url: url, accessMode: .read)
            guard let entry = archive["word/document.xml"], entry.uncompressedSize <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            var xml = Data()
            _ = try archive.extract(entry) { chunk in
                guard xml.count + chunk.count <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                xml.append(chunk)
            }
            text = try DocxTextParser().parse(xml)
        case "html", "htm":
            text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil).string
        case "txt", "md", "markdown":
            guard let decoded = ReadingText.decode(data) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            text = decoded
        default: throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard text.count <= ReadingText.limit else { throw CocoaError(.fileReadTooLarge) }
        var document = ReadingDocument(title: url.deletingPathExtension().lastPathComponent, text: ReadingText.normalized(text), source: url.lastPathComponent, format: ext)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = "\(document.id.uuidString).\(FileNames.safe(ext))"
        let destination = folder.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        document.originalFilename = filename
        do { return try save(document) } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    func exportText(_ document: ReadingDocument) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(FileNames.safe(document.title) + ".txt")
        try document.text.write(to: url, atomically: true, encoding: .utf8); return url
    }
    func exportBackup() throws -> URL {
        var originals: [String: Data] = [:]
        for document in documents { if let url = document.originalURL { originals[document.id.uuidString] = try Data(contentsOf: url) } }
        let backup = ReadingBackup(documents: documents, originals: originals)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zero-red-reading-backup.json")
        try JSONEncoder().encode(backup).write(to: url, options: .atomic); return url
    }
    func restoreBackup(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 100 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let backup = try JSONDecoder().decode(ReadingBackup.self, from: Data(contentsOf: url))
        guard backup.version == 1, backup.documents.count <= 5000 else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var created: [URL] = [], imported: [ReadingDocument] = []
        do {
            for old in backup.documents {
                guard old.text.count <= ReadingText.limit else { throw CocoaError(.fileReadTooLarge) }
                var document = old; document.id = UUID(); document.originalFilename = nil
                if let data = backup.originals[old.id.uuidString] {
                    guard data.count <= 20 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                    let name = document.id.uuidString + "." + FileNames.safe(document.format)
                    let destination = folder.appendingPathComponent(name)
                    try data.write(to: destination, options: .atomic); created.append(destination); document.originalFilename = name
                }
                imported.append(document)
            }
            try commit(imported + documents)
        } catch { created.forEach { try? FileManager.default.removeItem(at: $0) }; throw error }
    }
    var bytes: Int64 { (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } ?? 0 }
}
