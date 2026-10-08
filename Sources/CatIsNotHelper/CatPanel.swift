import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Контейнер, который ловит клики/перетаскивание/drag&drop поверх SwiftUI-котика.
final class CatContainerView: NSView, NSDraggingSource {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDropFiles: (([URL]) -> Void)?
    var menuProvider: (() -> NSMenu)?
    /// Что котик держит сейчас (файл и миниатюра), чтобы это можно было утащить из лапок.
    var heldItemProvider: (() -> (url: URL, image: NSImage)?)?
    /// Картинку потянули из лапок — котик сразу её отпускает.
    var onHeldDragBegan: (() -> Void)?
    /// Перетаскивание закончилось: файл, и доставили ли его куда-то (false — бросили в пустоту).
    var onHeldDragEnded: ((URL, Bool) -> Void)?
    private var draggedURL: URL?
    /// Область картинки в лапках в координатах вью (обновляет панель при смене масштаба).
    var heldHitRect = NSRect.zero

    private var dragging = false
    private var downPoint = NSPoint.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragging = false
        downPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        let p = event.locationInWindow
        if hypot(p.x - downPoint.x, p.y - downPoint.y) > 3 {
            dragging = true
            if let held = heldItemProvider?(), heldHitRect.contains(convert(downPoint, from: nil)) {
                beginHeldDrag(held, event: event)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    // MARK: Утащить картинку из лапок

    private func beginHeldDrag(_ held: (url: URL, image: NSImage), event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: held.url as NSURL)
        item.setDraggingFrame(heldHitRect, contents: held.image)
        draggedURL = held.url
        onHeldDragBegan?()
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let url = draggedURL else { return }
        draggedURL = nil
        onHeldDragEnded?(url, !operation.isEmpty)
    }

    override func mouseUp(with event: NSEvent) {
        guard !dragging else { return }
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: Drag & drop картинок

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = imageURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    /// Любые файлы: картинки котик показывает, остальное держит как документ.
    private func imageURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        return urls.filter { !$0.hasDirectoryPath }
    }
}

/// Прозрачная плавающая панель с котиком. Не активирует приложение при клике,
/// чтобы фокус оставался там, где ты печатаешь.
final class CatPanel: NSPanel {
    let container: CatContainerView
    private let frameName = "CatPanel"

    init(state: CatState, settings: AppSettings) {
        let size = CatView.size(for: settings.scale)
        container = CatContainerView(frame: NSRect(origin: .zero, size: size))
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        animationBehavior = .none

        let hosting = NSHostingView(rootView: CatView(state: state, settings: settings))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        contentView = container

        placeInitially()
        apply(settings)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ settings: AppSettings) {
        level = settings.alwaysOnTop ? .floating : .normal
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        behavior.insert(settings.allSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        collectionBehavior = behavior

        let size = CatView.size(for: settings.scale)
        if frame.size != size {
            var f = frame
            f.size = size
            setFrame(f, display: true)
            keepOnScreen()
        }

        // Область картинки: дизайн-координаты (y вниз) → координаты вью (y вверх).
        let s = settings.scale
        let r = CatView.heldImageRect
        container.heldHitRect = NSRect(x: r.minX * s,
                                       y: (CatView.design.height - r.maxY) * s,
                                       width: r.width * s,
                                       height: r.height * s)
    }

    private func placeInitially() {
        if setFrameUsingName(frameName) {
            setFrameAutosaveName(frameName)
            return
        }
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            let origin = NSPoint(x: v.maxX - frame.width - 24, y: v.minY + 16)
            setFrameOrigin(origin)
        }
        setFrameAutosaveName(frameName)
    }

    private func keepOnScreen() {
        guard let screen = screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        var f = frame
        f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
        f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
        if f != frame { setFrame(f, display: true) }
    }
}
