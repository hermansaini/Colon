#!/usr/bin/env swift
// Rebuild the README illustrations on macOS: swift Scripts/render-readme-media.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("docs/images")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let ink = NSColor(srgbRed: 0.12, green: 0.16, blue: 0.24, alpha: 1)
let muted = NSColor(srgbRed: 0.40, green: 0.45, blue: 0.52, alpha: 1)
let accent = NSColor(srgbRed: 0.28, green: 0.32, blue: 0.86, alpha: 1)
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
    box(0, 0, 1000, CGFloat(height), NSColor(srgbRed: 0.96, green: 0.96, blue: 0.99, alpha: 1), 0)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.cgImage!
}
func png(_ image: CGImage, _ name: String) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
}
func demo(text: String, query: String?, committed: Bool, step: Int, caret: Bool = true) -> CGImage {
    canvas {
        box(40, 32, 48, 48, accent, 14); label(":", 56, 30, 38, .white, .bold)
        label("Colon", 101, 38, 28, ink, .bold)
        label("A little shortcut. A lot of expression.", 40, 99, 32, ink, .semibold)
        label("Emoji autocomplete, right where you type.", 40, 145, 19, muted)
        box(40, 195, 920, 318, NSColor.black.withAlphaComponent(0.06), 20)
        box(40, 190, 920, 318, .white, 20)
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() { box(CGFloat(62+i*23), 211, 12, 12, c, 6) }
        label("A note to your team", 145, 205, 15, muted)
        label("Today's update", 75, 256, 19, muted, .medium)
        label(text, 75, 424, 29)
        let end = 75 + width(text, size: 29)
        if caret { box(end+3, 427, 2, 34, accent, 0) }
        if let query {
            let px = min(75 + width("This idea is ", size: 29), 600)
            box(px, 295, 275, 117, NSColor.black.withAlphaComponent(0.08), 11)
            box(px, 291, 275, 117, NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1), 11)
            box(px+5, 296, 265, 34, pale, 7)
            let rows = query == ":f" ? [("🔥", ":fire:"), ("🚒", ":fire_engine:"), ("🎆", ":fireworks:")] : [("🔥", ":fire:"), ("🚒", ":fire_engine:"), ("🧯", ":fire_extinguisher:")]
            for (i, row) in rows.enumerated() {
                let y = CGFloat(299+i*35)
                label(row.0, px+13, y-1, 23); label(row.1, px+50, y+3, 16, ink, i == 0 ? .semibold : .regular)
            }
        }
        if committed { label("Inserted. Keep typing.", 691, 266, 16, accent, .medium) }
        let captions = ["1  Type a shortcode", "2  Choose an emoji", "3  Press Enter"]
        for i in 0..<3 {
            let x = CGFloat(40+i*312)
            box(x, 538, 296, 43, i == step ? accent : .white, 12)
            label(captions[i], x+18, 549, 17, i == step ? .white : muted, .medium)
        }
        label("Illustrated demo • picker results vary with your query and settings", 40, 593, 12, muted)
    }
}
var frames: [(CGImage, Double)] = []
func frame(_ text: String, _ query: String? = nil, _ committed: Bool = false, _ step: Int = 0, _ duration: Double = 0.11) {
    frames.append((demo(text: text, query: query, committed: committed, step: step), duration))
}
frame("", nil, false, 0, 0.6)
var typed = ""
for c in "This idea is " { typed.append(c); frame(typed) }
frame(typed, nil, false, 0, 0.35)
for c in ":fire" { typed.append(c); let q = String(typed.dropFirst("This idea is ".count)); frame(typed, q.count > 1 ? q : nil, false, 0, 0.22) }
frame(typed, ":fire", false, 1, 1.6)
frame(typed, ":fire", false, 2, 0.65)
frame("This idea is 🔥", nil, true, 2, 1.2)
typed = "This idea is 🔥"
for c in " Let's ship it." { typed.append(c); frame(typed, nil, true, 2) }
frame(typed, nil, true, 2, 2.8)
let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("colon-demo.gif") as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (image, delay) in frames {
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(destination))
try png(demo(text: "This idea is :fire", query: ":fire", committed: false, step: 1), "colon-demo-still.png")

let install = canvas(height: 780) {
    label("From download to your first 🔥", 40, 30, 32, ink, .bold)
    label("Signed release installation • macOS 26 or later", 40, 77, 19, muted)
    let titles = ["Move to Applications", "Install the input method", "Add and select Colon", "Try your first shortcode"]
    let subtitles = ["Open the signed DMG; drag Colon across.", "Open Colon → General.", "System Settings → Keyboard → Text Input.", "Open Notes or Messages and start typing."]
    for i in 0..<4 {
        let x: CGFloat = i % 2 == 0 ? 40 : 510
        let y: CGFloat = i < 2 ? 128 : 434
        box(x, y, 450, 284, .white, 18)
        box(x+20, y+20, 30, 30, accent, 15); label("\(i+1)", x+29, y+24, 17, .white, .bold)
        label(titles[i], x+62, y+23, 21, ink, .semibold)
        label(subtitles[i], x+20, y+65, 16, muted)
        box(x+20, y+108, 410, 150, NSColor(srgbRed: 0.96, green: 0.96, blue: 0.99, alpha: 1), 12)
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
            label("This idea is :fire", x+37, y+130, 22)
            label("Press Enter", x+37, y+173, 15, muted)
            label("This idea is 🔥", x+37, y+205, 24, accent, .medium)
        }
    }
    label("Illustrated guide • exact macOS screens may vary. Log out and back in if Colon does not appear.", 40, 743, 15, muted)
}
try png(install, "install-walkthrough.png")
print("Created README GIF and PNG illustrations in docs/images")
