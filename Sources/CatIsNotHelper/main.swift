import AppKit
import SwiftUI

// Отладочный режим: `CatIsNotHelper --render out.png [fur] [mood]` рисует котика в файл и выходит.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--render" {
    let path = CommandLine.arguments[2]
    let settings = AppSettings.shared
    if CommandLine.arguments.count >= 4, let fur = FurStyle(rawValue: CommandLine.arguments[3]) { settings.fur = fur }
    settings.scale = 1
    settings.opacity = 1
    let state = CatState()
    if CommandLine.arguments.count >= 5 {
        switch CommandLine.arguments[4] {
        case "happy": state.mood = .happy
        case "sleepy": state.mood = .sleepy
        case "grumpy": state.mood = .grumpy
        case "excited": state.mood = .excited
        case "tap": state.leftDown = true
        case "hold":
            if CommandLine.arguments.count >= 6 { state.hold(url: URL(fileURLWithPath: CommandLine.arguments[5])) }
        default: break
        }
    }
    state.bubble = CommandLine.arguments.count >= 7 ? CommandLine.arguments[6] : nil
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: CatView(state: state, settings: settings))
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                print("rendered \(path) \(cg.width)x\(cg.height)")
            }
        }
    }
    exit(0)
}

// Отладочный режим: `CatIsNotHelper --render-stats out.png` рисует окно статистики с текущими данными.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--render-stats" {
    let path = CommandLine.arguments[2]
    MainActor.assumeIsolated {
        let stats = StatsStore()
        stats.load()
        for _ in 0..<37 { stats.recordKey() }
        let shots = ScreenshotManager()
        shots.reload()
        let view = StatsView(stats: stats, state: CatState(), shots: shots).content
            .frame(width: 600)
            .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let cg = renderer.cgImage,
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("rendered \(path)")
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
