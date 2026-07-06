// Renders the GamePorter app icon: teal-indigo gradient squircle + game controller glyph.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.05
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.55, blue: 0.60, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.15, blue: 0.55, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -60)

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "gamecontroller.fill",
                            accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symSize = NSSize(width: s * 0.62, height: s * 0.62 * symbol.size.height / symbol.size.width)
        symbol.draw(in: NSRect(x: (s - symSize.width) / 2,
                               y: (s - symSize.height) / 2,
                               width: symSize.width, height: symSize.height))
    }
    img.unlockFocus()
    return img
}

for size in sizes {
    let img = render(size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for n in names { try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(n)")) }
}
print("iconset written")
