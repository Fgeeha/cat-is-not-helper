import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    let state = CatState()
    let stats = StatsStore()
    let shots = ScreenshotManager()
    let updates = UpdateChecker()

    private var monitor = InputMonitor()
    private var updateTimer: Timer?
    private var panel: CatPanel!
    private var statusBar: StatusBarController!
    private var windows: [String: NSWindow] = [:]
    private var ticker: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var wasTrusted = false
    private var lastMilestone = 0

    // MARK: - Жизненный цикл

    func applicationDidFinishLaunching(_ notification: Notification) {
        stats.load()
        shots.reload()
        lastMilestone = stats.data.totalKeys / 1000
        state.bubblesEnabled = settings.bubbles

        panel = CatPanel(state: state, settings: settings)
        panel.container.onClick = { [weak self] in self?.pet() }
        panel.container.onDoubleClick = { [weak self] in self?.openHeld() }
        panel.container.onDropFiles = { [weak self] urls in self?.give(files: urls) }
        panel.container.menuProvider = { [weak self] in self?.statusBar.makeMenu() ?? NSMenu() }
        panel.container.heldItemProvider = { [weak self] in
            guard let self, let url = self.state.heldURL, let image = self.state.heldImage else { return nil }
            return (url, image)
        }
        panel.container.onHeldDragBegan = { [weak self] in
            self?.state.putAway(message: nil)
        }
        panel.container.onHeldDragEnded = { [weak self] url, delivered in
            guard let self else { return }
            // Бросили обратно на котика — он уже снова держит, молчим.
            if self.state.heldURL == url { return }
            self.state.say(delivered ? "забирай, твоё" : "ладно, отпустил")
        }
        if settings.catVisible { panel.orderFrontRegardless() }

        monitor.onKey = { [weak self] paw in
            guard let self else { return }
            self.state.tap(paw)
            self.stats.recordKey()
            self.checkMilestone()
        }
        monitor.onClick = { [weak self] paw in
            self?.state.tap(paw)
            self?.stats.recordClick()
        }
        monitor.start()

        statusBar = StatusBarController(app: self)

        wasTrusted = InputMonitor.isTrusted(prompt: false)
        if wasTrusted {
            state.say("привет! я не помогаю, я тапаю", seconds: 4)
        } else {
            state.needsAccess = true
            _ = InputMonitor.isTrusted(prompt: true)
            state.say("дай доступ к клавиатуре 🙏 (меню 🐾)", seconds: 8)
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applySettings() }
            }
            .store(in: &cancellables)

        scheduleUpdateChecks()
    }

    // MARK: - Обновления

    private func scheduleUpdateChecks() {
        guard UpdateChecker.isReleaseBuild else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.autoCheckUpdates() }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in self?.autoCheckUpdates() }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func autoCheckUpdates() {
        guard settings.checkUpdates else { return }
        updates.check { [weak self] info in
            guard let self, let info else { return }
            self.state.say("есть обновление v\(info.version) — в меню 🐾", seconds: 6)
        }
    }

    func checkUpdatesNow() {
        state.say("проверяю…", seconds: 2)
        updates.check { [weak self] info in
            guard let self else { return }
            if let info {
                self.state.say("есть v\(info.version) — обновить в меню", seconds: 6)
            } else if case .upToDate = self.updates.status {
                self.state.say("у меня последняя версия")
            } else if case .failed(let message) = self.updates.status {
                self.state.say(message, seconds: 5)
            }
        }
    }

    func openReleasePage() {
        let url = updates.available?.pageURL
            ?? URL(string: "https://github.com/\(UpdateChecker.repo)/releases/latest")!
        NSWorkspace.shared.open(url)
    }

    func installUpdate() {
        guard let info = updates.available else { return }
        state.say("качаю v\(info.version)…", seconds: 60)
        updates.install(info) { [weak self] in self?.relaunch() }
    }

    private func relaunch() {
        stats.save()
        let path = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stats.save()
    }

    private func tick() {
        stats.tick()
        state.tick(cpm: stats.cpm)

        let trusted = InputMonitor.isTrusted(prompt: false)
        if trusted != wasTrusted {
            wasTrusted = trusted
            state.needsAccess = !trusted
            if trusted {
                monitor.start()
                state.say("вижу клавиатуру! 🎉", seconds: 4)
            }
        }
    }

    private func applySettings() {
        state.bubblesEnabled = settings.bubbles
        panel.apply(settings)
        if settings.catVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func checkMilestone() {
        let milestone = stats.data.totalKeys / 1000
        if milestone > lastMilestone {
            lastMilestone = milestone
            state.say("🎉 \(milestone * 1000) тапов!", seconds: 4)
        }
    }

    // MARK: - Действия

    func pet() {
        state.pet()
        stats.recordPet()
    }

    func feed() {
        state.feed()
        stats.recordFeed()
    }

    func toggleCat() {
        settings.catVisible.toggle()
    }

    func takeScreenshot() {
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        shots.capture { [weak self] url in
            guard let self else { return }
            if wasVisible, self.settings.catVisible { self.panel.orderFrontRegardless() }
            if let url {
                self.state.hold(url: url)
                self.stats.recordScreenshot()
            } else {
                self.state.say("передумал? ладно")
            }
        }
    }

    /// Картинки, брошенные на котика.
    func give(files urls: [URL]) {
        guard let first = urls.first, let stored = shots.importImage(from: first) else { return }
        state.hold(url: stored)
        // Новый файл — считаем; свой же из папки (например, вернули после перетаскивания) — нет.
        if stored != first { stats.recordScreenshot() }
    }

    /// Картинка из галереи (уже лежит в папке котика).
    func give(url: URL) {
        state.hold(url: url)
    }

    func openHeld() {
        if let url = state.heldURL {
            shots.open(url)
        } else {
            pet()
        }
    }

    func putAway() {
        state.putAway()
    }

    /// Картинку — как изображение и как файл, любой документ — как файл.
    func copyHeld() {
        guard let url = state.heldURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = [url as NSURL]
        if FileKind.isImage(url), let image = NSImage(contentsOf: url) {
            objects.insert(image, at: 0)
        }
        pasteboard.writeObjects(objects)
        state.say("в буфере обмена, вставляй", seconds: 3)
    }

    func requestAccess() {
        _ = InputMonitor.isTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func showStats() {
        show(id: "stats", title: "Статистика котика", size: NSSize(width: 600, height: 700),
             view: StatsView(stats: stats, state: state, shots: shots))
    }

    func showGallery() {
        show(id: "gallery", title: "Скриншоты котика", size: NSSize(width: 720, height: 520),
             view: GalleryView(shots: shots, state: state,
                               onCapture: { [weak self] in self?.takeScreenshot() },
                               onGive: { [weak self] url in self?.give(url: url) },
                               onTakeBack: { [weak self] in self?.putAway() }))
    }

    func showSettings() {
        show(id: "settings", title: "Настройки котика", size: NSSize(width: 760, height: 640),
             view: SettingsView(settings: settings, state: state, updates: updates,
                                isTrusted: { InputMonitor.isTrusted(prompt: false) },
                                requestAccess: { [weak self] in self?.requestAccess() },
                                checkUpdates: { [weak self] in self?.checkUpdatesNow() },
                                installUpdate: { [weak self] in self?.installUpdate() }))
    }

    func quit() {
        stats.save()
        NSApp.terminate(nil)
    }

    // MARK: - Окна

    private func show<V: View>(id: String, title: String, size: NSSize, view: V) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.setFrameAutosaveName("window-\(id)")
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
