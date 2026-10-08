import AppKit

/// Иконка 🐾 в меню-баре и общее меню (оно же — контекстное меню котика).
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.title = "🐾"
        item.button?.toolTip = "Cat Is Not Helper"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        fill(menu)
        return menu
    }

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        let today = app.stats.today
        menu.addItem(info("Сегодня: \(today.keys.formatted()) тапов · \(app.stats.cpm)/мин"))
        menu.addItem(info("Настроение: \(moodEmoji(app.state.mood)) \(moodTitle(app.state.mood)) · \(Int(app.state.happiness * 100))%"))
        if app.state.needsAccess {
            menu.addItem(action("⚠️ Дать доступ к клавиатуре…", #selector(requestAccess)))
        }
        switch app.updates.status {
        case .available(let version):
            menu.addItem(action("⬆️ Обновить до v\(version)…", #selector(installUpdate)))
            menu.addItem(action("Открыть v\(version) на GitHub", #selector(openRelease)))
        case .downloading(let progress):
            menu.addItem(info("Скачиваю обновление… \(Int(progress * 100))%"))
        case .installing:
            menu.addItem(info("Устанавливаю обновление…"))
        case .checking:
            menu.addItem(info("Проверяю обновления…"))
        default:
            menu.addItem(action("Проверить обновления…", #selector(checkUpdates)))
        }
        menu.addItem(.separator())
        menu.addItem(action("Статистика…", #selector(showStats), key: "s"))
        menu.addItem(action("Сделать скриншот — котик подержит", #selector(takeScreenshot), key: "4"))
        menu.addItem(action("Галерея скриншотов…", #selector(showGallery), key: "g"))
        if app.state.heldURL != nil {
            menu.addItem(action("Открыть то, что держит котик", #selector(openHeld), key: "o"))
            menu.addItem(action("Скопировать в буфер обмена", #selector(copyHeld), key: "c"))
            menu.addItem(action("Забрать у котика", #selector(putAway)))
        }
        menu.addItem(.separator())
        menu.addItem(action("Погладить", #selector(pet), key: "p"))
        menu.addItem(action("Покормить 🐟", #selector(feed), key: "f"))
        menu.addItem(.separator())
        menu.addItem(action(app.settings.catVisible ? "Спрятать котика" : "Показать котика", #selector(toggleCat), key: "h"))
        menu.addItem(submenu("Размер", items: SizePreset.allCases.map { preset in
            let item = NSMenuItem(title: "\(preset.title) · \(Int(preset.scale * 100))%", action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = SizePreset.closest(to: app.settings.scale) == preset ? .on : .off
            return item
        }))
        menu.addItem(submenu("Окрас", items: FurStyle.allCases.map { fur in
            let item = NSMenuItem(title: fur.title, action: #selector(setFur(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = fur.rawValue
            item.state = app.settings.fur == fur ? .on : .off
            return item
        }))
        menu.addItem(action("Настройки…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(action("Выйти", #selector(quit), key: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach { sub.addItem($0) }
        parent.submenu = sub
        return parent
    }

    // MARK: - Действия

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = SizePreset(rawValue: raw) else { return }
        app.settings.scale = preset.scale
    }

    @objc private func setFur(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let fur = FurStyle(rawValue: raw) else { return }
        app.settings.fur = fur
    }

    @objc private func installUpdate() { app.installUpdate() }
    @objc private func checkUpdates() { app.checkUpdatesNow() }
    @objc private func openRelease() { app.openReleasePage() }
    @objc private func showStats() { app.showStats() }
    @objc private func showGallery() { app.showGallery() }
    @objc private func showSettings() { app.showSettings() }
    @objc private func takeScreenshot() { app.takeScreenshot() }
    @objc private func openHeld() { app.openHeld() }
    @objc private func putAway() { app.putAway() }
    @objc private func copyHeld() { app.copyHeld() }
    @objc private func pet() { app.pet() }
    @objc private func feed() { app.feed() }
    @objc private func toggleCat() { app.toggleCat() }
    @objc private func requestAccess() { app.requestAccess() }
    @objc private func quit() { app.quit() }
}
