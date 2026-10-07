import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    let state = CatState()
    let stats = StatsStore()
    let shots = ScreenshotManager()

    private var monitor = InputMonitor()
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
        stats.recordScreenshot()
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
                               onGive: { [weak self] url in self?.give(url: url) }))
    }

    func showSettings() {
        show(id: "settings", title: "Настройки котика", size: NSSize(width: 440, height: 560),
             view: SettingsView(settings: settings,
                                isTrusted: { InputMonitor.isTrusted(prompt: false) },
                                requestAccess: { [weak self] in self?.requestAccess() }))
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
