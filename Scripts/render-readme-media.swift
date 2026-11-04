#!/usr/bin/env swift
// Rebuild the README illustrations on macOS: swift Scripts/render-readme-media.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("docs/images")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let muted = NSColor(srgbRed: 0.40, green: 0.45, blue: 0.52, alpha: 1)
let accent = NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)
let pale = NSColor(srgbRed: 0.93, green: 0.93, blue: 1, alpha: 1)
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, _ radius: CGFloat = 14) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 20, _ color: NSColor = ink, _ weight: NSFont.Weight = .regular) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
func width(_ text: String, size: CGFloat) -> CGFloat {
    (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
}
func canvas(height: Int = 620, draw: () -> Void) -> CGImage {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.translateX(by: 0, yBy: CGFloat(height)); transform.scaleX(by: 1, yBy: -1); transform.concat()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: NSGraphicsContext.current!.cgContext, flipped: true)
    box(0, 0, 1000, CGFloat(height), NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), 0)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.cgImage!
}
func png(_ image: CGImage, _ name: String) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
}
func demo(text: String, query: String?, committed: Bool, step: Int, caret: Bool = true) -> CGImage {
    canvas(height: 700) {
        label("Say it with an emoji.", 305, 32, 38, ink, .semibold)
        label("Type. Choose. Keep the conversation going.", 310, 84, 18, muted)
        box(63, 139, 874, 484, NSColor.black.withAlphaComponent(0.06), 22)
        box(60, 134, 880, 484, .white, 22)
        box(60, 134, 880, 76, NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1), 22)
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            box(CGFloat(82+i*22), 154, 12, 12, c, 6)
        }
        box(443, 148, 38, 38, NSColor(srgbRed: 0.62, green: 0.65, blue: 0.68, alpha: 1), 19)
        label("JA", 452, 158, 14, .white, .medium)
        label("Johnny Appleseed", 491, 153, 18, ink, .semibold)
        label("iMessage", 491, 177, 12, muted)
        label("Today 9:41 AM", 450, 229, 12, muted, .medium)
        box(90, 264, 331, 44, NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1), 19)
        label("How was the show last night?", 106, 275, 19)
        box(676, 326, 232, 44, accent, 19)
        label("Wish you were there!", 692, 337, 19, .white)
        label("Delivered", 849, 378, 11, muted)
        label("+", 88, 550, 27, muted)
        box(126, 548, 779, 45, NSColor(srgbRed: 0.84, green: 0.84, blue: 0.86, alpha: 1), 23)
        box(127, 549, 777, 43, .white, 22)
        label(text.isEmpty ? "iMessage" : text, 146, 559, 20, text.isEmpty ? muted : ink)
        let end = 146 + width(text, size: 20)
        if caret && !text.isEmpty { box(end+2, 558, 2, 26, accent, 0) }
        box(865, 556, 29, 29, accent, 15)
        label("↑", 873, 557, 22, .white, .medium)
        if let query {
            let px: CGFloat = 230
            box(px, 408, 274, 126, NSColor.black.withAlphaComponent(0.08), 12)
            box(px, 404, 274, 126, NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1), 12)
            box(px+5, 409, 264, 37, NSColor(srgbRed: 0.84, green: 0.91, blue: 1, alpha: 1), 7)
            let rows = query == ":f" ? [("🔥", ":fire:"), ("🚒", ":fire_engine:"), ("🎆", ":fireworks:")] : [("🔥", ":fire:"), ("🚒", ":fire_engine:"), ("🧯", ":fire_extinguisher:")]
            for (i, row) in rows.enumerated() {
                let y = CGFloat(413+i*38)
                label(row.0, px+13, y-2, 25)
                label(row.1, px+52, y+3, 16, ink, i == 0 ? .semibold : .regular)
            }
        }
        let captions = ["Type :fire", "Choose your emoji", "Press Enter. Keep typing."]
        let caption = captions[step]
        label(caption, (1000-width(caption, size: 20))/2, 641, 20, ink, .medium)
        label("Illustrated in Messages", 434, 677, 12, muted)
    }
}
var frames: [(CGImage, Double)] = []
func frame(_ text: String, _ query: String? = nil, _ committed: Bool = false, _ step: Int = 0, _ duration: Double = 0.11) {
    frames.append((demo(text: text, query: query, committed: committed, step: step), duration))
}
frame("", nil, false, 0, 0.6)
var typed = ""
for c in "It was " { typed.append(c); frame(typed) }
frame(typed, nil, false, 0, 0.35)
for c in ":fire" { typed.append(c); let q = String(typed.dropFirst("It was ".count)); frame(typed, q.count > 1 ? q : nil, false, 0, 0.22) }
frame(typed, ":fire", false, 1, 1.6)
frame(typed, ":fire", false, 2, 0.65)
frame("It was 🔥", nil, true, 2, 1.2)
typed = "It was 🔥"
for c in " So good." { typed.append(c); frame(typed, nil, true, 2) }
frame(typed, nil, true, 2, 2.8)
let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("colon-demo.gif") as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (image, delay) in frames {
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(destination))
try png(demo(text: "It was :fire", query: ":fire", committed: false, step: 1), "colon-demo-still.png")

let install = canvas(height: 780) {
    label("Ready in a few steps.", 40, 30, 32, ink, .semibold)
    label("Colon for Mac • macOS 26 or later", 40, 77, 19, muted)
    let titles = ["Move to Applications", "Install the input method", "Add and select Colon", "Type your first emoji"]
    let subtitles = ["Open the download. Drag Colon across.", "Open Colon → General.", "System Settings → Keyboard → Text Input.", "Open Messages and start typing."]
    for i in 0..<4 {
        let x: CGFloat = i % 2 == 0 ? 40 : 510
        let y: CGFloat = i < 2 ? 128 : 434
        box(x, y, 450, 284, .white, 18)
        box(x+20, y+20, 30, 30, accent, 15); label("\(i+1)", x+29, y+24, 17, .white, .bold)
        label(titles[i], x+62, y+23, 21, ink, .semibold)
        label(subtitles[i], x+20, y+65, 16, muted)
        box(x+20, y+108, 410, 150, NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), 12)
        switch i {
        case 0:
            box(x+65, y+127, 59, 59, accent, 14); label(":", x+86, y+121, 48, .white, .bold)
            label("Colon", x+73, y+199, 16)
            label("→", x+197, y+141, 31, accent)
            label("📁", x+300, y+127, 47)
            label("Applications", x+278, y+199, 16)
        case 1:
            label("Input method", x+37, y+128, 16, muted)
            label("Not installed", x+273, y+128, 16)
            box(x+37, y+176, 223, 39, accent, 9)
            label("Install Input Method", x+53, y+185, 18, .white, .medium)
        case 2:
            label("Text Input", x+37, y+127, 19, ink, .semibold)
            box(x+312, y+121, 98, 34, .white, 8); label("Edit…", x+337, y+129, 16, accent)
            label("+   Add Colon", x+37, y+173, 18)
            label("✓   Select Colon in the input menu", x+37, y+212, 18, accent)
        default:
            label("It was :fire", x+37, y+130, 22)
            label("Press Enter", x+37, y+173, 15, muted)
            label("It was 🔥", x+37, y+205, 24, accent, .medium)
        }
    }
    label("Illustrated guide • exact macOS screens may vary. Log out and back in if Colon does not appear.", 40, 743, 15, muted)
}
try png(install, "install-walkthrough.png")
print("Created README GIF and PNG illustrations in docs/images")
