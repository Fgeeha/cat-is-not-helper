// Генерирует AppIcon.icns: рыжий кружок с котиком.
// Использование: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("CatIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try? FileManager.default.removeItem(at: tmp)
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size)
    image.lockFocus()
    let rect = NSRect(origin: .zero, size: size)
    let inset = CGFloat(px) * 0.06
    let bg = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: CGFloat(px) * 0.22, yRadius: CGFloat(px) * 0.22)
    NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.27, alpha: 1).setFill()
    bg.fill()
    let font = NSFont.systemFont(ofSize: CGFloat(px) * 0.62)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let text = NSAttributedString(string: "🐱", attributes: attrs)
    let textSize = text.size()
    text.draw(at: NSPoint(x: (CGFloat(px) - textSize.width) / 2, y: (CGFloat(px) - textSize.height) / 2 + CGFloat(px) * 0.02))
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return png
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: tmp.appendingPathComponent("icon_\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", tmp.path, "-o", output]
try proc.run()
proc.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
exit(proc.terminationStatus)
