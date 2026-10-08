import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageLoader {
    static func thumbnail(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

enum FileKind {
    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Миниатюра картинки, а для любого другого файла — его системная иконка.
    static func preview(for url: URL, maxPixel: Int) -> NSImage {
        if isImage(url), let thumb = ImageLoader.thumbnail(url: url, maxPixel: maxPixel) {
            return thumb
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 256, height: 256)
        return icon
    }
}

/// Папка котика: ~/Pictures/CatIsNotHelper. Скриншоты и любые файлы, которые ему дали.
final class ScreenshotManager: ObservableObject {
    @Published private(set) var items: [URL] = []
    let directory: URL

    init() {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        directory = pictures.appendingPathComponent("CatIsNotHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    private static func stamp() -> String { stampFormatter.string(from: Date()) }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        let files = urls.filter { !$0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }
        items = files.sorted { modified($0) > modified($1) }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Интерактивный скриншот через системный screencapture (выделение области).
    func capture(completion: @escaping (URL?) -> Void) {
        let url = directory.appendingPathComponent("cat-\(Self.stamp()).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                let ok = FileManager.default.fileExists(atPath: url.path)
                self?.reload()
                completion(ok ? url : nil)
            }
        }
        do {
            try process.run()
        } catch {
            completion(nil)
        }
    }

    /// Копирует сторонний файл (картинку или любой документ) в папку котика, если он ещё не там.
    func importImage(from source: URL) -> URL? {
        if source.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
            return source
        }
        guard !source.hasDirectoryPath else { return nil }
        let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        if let existing = existingCopy(ofName: "\(base).\(ext)", size: fileSize(source)) {
            return existing
        }
        let dest = directory.appendingPathComponent("cat-\(Self.stamp())-\(base).\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            reload()
            return dest
        } catch {
            return nil
        }
    }

    /// Уже скопированный ранее файл с тем же исходным именем и размером — чтобы не плодить дубли.
    private func existingCopy(ofName name: String, size: Int) -> URL? {
        guard size > 0 else { return nil }
        reload()
        return items.first { $0.lastPathComponent.hasSuffix("-\(name)") && fileSize($0) == size }
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    func delete(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        reload()
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func openFolder() { NSWorkspace.shared.open(directory) }
}
