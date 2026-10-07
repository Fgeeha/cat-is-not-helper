import AppKit
import Combine

struct UpdateInfo: Equatable {
    let version: String
    let downloadURL: URL
    let pageURL: URL?
}

/// Простое обновление через GitHub Releases: берём latest, сравниваем версию,
/// скачиваем zip с универсальным бандлом, распаковываем и подменяем .app.
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var available: UpdateInfo?
    @Published private(set) var lastCheck: Date?

    static let repo = "Fgeeha/cat-is-not-helper"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Выставляется CI на сборках с тега. Для локальных сборок автопроверка выключена,
    /// чтобы разработческий бандл не предлагал «обновиться» до релиза.
    static var isReleaseBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "CatReleaseBuild") as? Bool) ?? false
    }

    private var progressObservation: NSKeyValueObservation?

    // MARK: - Проверка

    func check(completion: ((UpdateInfo?) -> Void)? = nil) {
        if case .checking = status { return }
        if case .downloading = status { return }
        status = .checking

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CatIsNotHelper/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastCheck = Date()
                if let error {
                    self.status = .failed(error.localizedDescription)
                    completion?(nil)
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.status = .failed(code == 404 ? "Релизов пока нет" : "Не удалось прочитать ответ GitHub")
                    completion?(nil)
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = json["assets"] as? [[String: Any]] ?? []
                let asset = assets.first { ($0["name"] as? String)?.hasSuffix("-universal.zip") == true }
                    ?? assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
                guard let urlString = asset?["browser_download_url"] as? String, let url = URL(string: urlString) else {
                    self.status = .failed("В релизе \(tag) нет zip-архива")
                    completion?(nil)
                    return
                }
                let info = UpdateInfo(version: version, downloadURL: url,
                                      pageURL: (json["html_url"] as? String).flatMap(URL.init))
                if Self.isNewer(version, than: Self.currentVersion) {
                    self.available = info
                    self.status = .available(version)
                    completion?(info)
                } else {
                    self.available = nil
                    self.status = .upToDate
                    completion?(nil)
                }
            }
        }.resume()
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
                .prefix(3)
                .map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Установка

    func install(_ info: UpdateInfo, relaunch: @escaping () -> Void) {
        status = .downloading(0)
        let task = URLSession.shared.downloadTask(with: info.downloadURL) { [weak self] tmp, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.progressObservation = nil
                if let error {
                    self.status = .failed(error.localizedDescription)
                    return
                }
                guard let tmp else {
                    self.status = .failed("Пустой ответ при скачивании")
                    return
                }
                // downloadTask удаляет временный файл после выхода из колбэка — переносим сразу.
                let zip = FileManager.default.temporaryDirectory.appendingPathComponent("CatIsNotHelper-\(info.version).zip")
                try? FileManager.default.removeItem(at: zip)
                do {
                    try FileManager.default.moveItem(at: tmp, to: zip)
                } catch {
                    self.status = .failed("Не удалось сохранить архив: \(error.localizedDescription)")
                    return
                }
                self.status = .installing
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Self.replaceBundle(with: zip)
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.status = .upToDate
                            relaunch()
                        case .failure(let err):
                            self.status = .failed(err.message)
                            if err.openDownloadFolder {
                                NSWorkspace.shared.activateFileViewerSelecting([zip])
                            }
                        }
                    }
                }
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                if case .downloading = self?.status ?? .idle {
                    self?.status = .downloading(progress.fractionCompleted)
                }
            }
        }
        task.resume()
    }

    struct InstallError: Error {
        let message: String
        var openDownloadFolder = false
    }

    private static func replaceBundle(with zip: URL) -> Result<Void, InstallError> {
        let fm = FileManager.default
        let unpackDir = fm.temporaryDirectory.appendingPathComponent("CatIsNotHelper-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: unpackDir) }
        do { try fm.createDirectory(at: unpackDir, withIntermediateDirectories: true) } catch {
            return .failure(InstallError(message: "Нет доступа к временной папке"))
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpackDir.path]
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            return .failure(InstallError(message: "Не удалось запустить ditto"))
        }
        guard ditto.terminationStatus == 0 else {
            return .failure(InstallError(message: "Архив повреждён", openDownloadFolder: true))
        }

        let contents = (try? fm.contentsOfDirectory(at: unpackDir, includingPropertiesForKeys: nil)) ?? []
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
            return .failure(InstallError(message: "В архиве нет .app", openDownloadFolder: true))
        }
        let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
        let plist = NSDictionary(contentsOf: plistURL) as? [String: Any]
        guard plist?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            return .failure(InstallError(message: "В архиве другое приложение", openDownloadFolder: true))
        }

        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            return .failure(InstallError(message: "Нет прав на запись в \(parent.path). Замени приложение вручную.", openDownloadFolder: true))
        }

        let backup = parent.appendingPathComponent(".CatIsNotHelper-old-\(UUID().uuidString).app")
        do {
            try fm.moveItem(at: target, to: backup)
        } catch {
            return .failure(InstallError(message: "Не удалось убрать старую версию: \(error.localizedDescription)", openDownloadFolder: true))
        }
        do {
            try fm.moveItem(at: newApp, to: target)
        } catch {
            try? fm.moveItem(at: backup, to: target)
            return .failure(InstallError(message: "Не удалось поставить новую версию: \(error.localizedDescription)", openDownloadFolder: true))
        }
        try? fm.removeItem(at: backup)
        try? fm.removeItem(at: zip)
        return .success(())
    }
}
