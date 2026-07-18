import AppKit
import Foundation

guard CommandLine.arguments.count == 5 else {
    fputs("usage: build-social-preview.swift <background> <icon> <screenshot> <output>\n", stderr)
    exit(64)
}

let backgroundURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
let screenshotURL = URL(fileURLWithPath: CommandLine.arguments[3])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[4])

func loadImage(_ url: URL) -> NSImage {
    guard let image = NSImage(contentsOf: url) else {
        fputs("error: could not read \(url.path)\n", stderr)
        exit(66)
    }
    return image
}

let background = loadImage(backgroundURL)
let icon = loadImage(iconURL)
let screenshot = loadImage(screenshotURL)
let canvasSize = NSSize(width: 1_280, height: 640)

let canvas = NSImage(size: canvasSize, flipped: true) { bounds in
    background.draw(
        in: bounds,
        from: NSRect(origin: .zero, size: background.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: true,
        hints: nil
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: 10)
    shadow.set()
    NSColor.black.withAlphaComponent(0.20).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 602, y: 114, width: 616, height: 397),
        xRadius: 18,
        yRadius: 18
    ).fill()
    NSGraphicsContext.restoreGraphicsState()

    let screenshotRect = NSRect(x: 610, y: 123, width: 600, height: 379)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenshotRect, xRadius: 12, yRadius: 12).addClip()
    screenshot.draw(
        in: screenshotRect,
        from: NSRect(origin: .zero, size: screenshot.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: nil
    )
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    let screenshotBorder = NSBezierPath(
        roundedRect: screenshotRect.insetBy(dx: -1, dy: -1),
        xRadius: 13,
        yRadius: 13
    )
    screenshotBorder.lineWidth = 2
    screenshotBorder.stroke()

    icon.draw(
        in: NSRect(x: 78, y: 70, width: 84, height: 84),
        from: NSRect(origin: .zero, size: icon.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: nil
    )

    let headlineAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 58, weight: .semibold),
        .foregroundColor: NSColor.white,
        .kern: -1.2,
    ]
    let flowAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 23, weight: .medium),
        .foregroundColor: NSColor(
            calibratedRed: 220 / 255,
            green: 235 / 255,
            blue: 250 / 255,
            alpha: 1
        ),
    ]
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 21, weight: .regular),
        .foregroundColor: NSColor(
            calibratedRed: 175 / 255,
            green: 200 / 255,
            blue: 214 / 255,
            alpha: 1
        ),
    ]

    NSAttributedString(string: "Desk Setup", attributes: headlineAttributes)
        .draw(at: NSPoint(x: 78, y: 202))
    NSAttributedString(string: "Switcher", attributes: headlineAttributes)
        .draw(at: NSPoint(x: 78, y: 266))
    NSAttributedString(
        string: "Capture  →  Edit  →  Review & Apply",
        attributes: flowAttributes
    ).draw(at: NSPoint(x: 81, y: 365))
    NSAttributedString(
        string: "Local-only macOS setup profiles",
        attributes: subtitleAttributes
    ).draw(at: NSPoint(x: 81, y: 415))

    return true
}

guard
    let tiff = canvas.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [.compressionFactor: 1])
else {
    fputs("error: could not encode social preview\n", stderr)
    exit(65)
}

try png.write(to: outputURL, options: .atomic)
