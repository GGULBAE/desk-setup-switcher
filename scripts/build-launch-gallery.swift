import AppKit
import Foundation

guard CommandLine.arguments.count == 7 else {
  fputs(
    "usage: build-launch-gallery.swift <icon> <capture> <display> <sound> <review> <output-directory>\n",
    stderr
  )
  exit(64)
}

let iconURL = URL(fileURLWithPath: CommandLine.arguments[1])
let captureURL = URL(fileURLWithPath: CommandLine.arguments[2])
let displayURL = URL(fileURLWithPath: CommandLine.arguments[3])
let soundURL = URL(fileURLWithPath: CommandLine.arguments[4])
let reviewURL = URL(fileURLWithPath: CommandLine.arguments[5])
let outputDirectory = URL(
  fileURLWithPath: CommandLine.arguments[6],
  isDirectory: true
)

func loadImage(_ url: URL) -> NSImage {
  guard let image = NSImage(contentsOf: url) else {
    fputs("error: could not read \(url.path)\n", stderr)
    exit(66)
  }
  return image
}

struct LaunchCard {
  let fileName: String
  let step: String
  let title: String
  let body: String
  let tags: [String]
  let screenshot: NSImage
}

let icon = loadImage(iconURL)
let cards = [
  LaunchCard(
    fileName: "01-capture.png",
    step: "01  CAPTURE",
    title: "Save what already works.",
    body: "Capture available Display and Sound values into a local profile. Nothing changes.",
    tags: ["Read-only capture", "Local profile"],
    screenshot: loadImage(captureURL)
  ),
  LaunchCard(
    fileName: "02-edit-display.png",
    step: "02  EDIT DISPLAY",
    title: "Choose the display setup.",
    body: "Set the main display and an available resolution for this desk.",
    tags: ["Main display", "Resolution"],
    screenshot: loadImage(displayURL)
  ),
  LaunchCard(
    fileName: "03-edit-sound.png",
    step: "03  EDIT SOUND",
    title: "Bring the right sound back.",
    body: "Choose output and input devices, volumes, and output mute.",
    tags: ["Output + Input", "No microphone recording"],
    screenshot: loadImage(soundURL)
  ),
  LaunchCard(
    fileName: "04-review.png",
    step: "04  REVIEW",
    title: "See every change first.",
    body: "Apply starts only after a separate confirmation. Profiles never switch automatically.",
    tags: ["Explicit Apply", "No auto-switching"],
    screenshot: loadImage(reviewURL)
  ),
]

let canvasSize = NSSize(width: 1_270, height: 760)
let white = NSColor.white
let secondaryText = NSColor(
  calibratedRed: 210 / 255,
  green: 226 / 255,
  blue: 239 / 255,
  alpha: 1
)
let mutedText = NSColor(
  calibratedRed: 163 / 255,
  green: 188 / 255,
  blue: 204 / 255,
  alpha: 1
)
let accent = NSColor(
  calibratedRed: 94 / 255,
  green: 211 / 255,
  blue: 178 / 255,
  alpha: 1
)

func paragraphStyle(lineSpacing: CGFloat = 0) -> NSParagraphStyle {
  let style = NSMutableParagraphStyle()
  style.lineBreakMode = .byWordWrapping
  style.lineSpacing = lineSpacing
  return style
}

func aspectFitRect(imageSize: NSSize, inside bounds: NSRect) -> NSRect {
  guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
  let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
  let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
  return NSRect(
    x: bounds.midX - size.width / 2,
    y: bounds.midY - size.height / 2,
    width: size.width,
    height: size.height
  )
}

func drawTag(_ text: String, at origin: NSPoint) -> CGFloat {
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 16, weight: .medium),
    .foregroundColor: secondaryText,
  ]
  let attributed = NSAttributedString(string: text, attributes: attributes)
  let width = ceil(attributed.size().width) + 30
  let rect = NSRect(x: origin.x, y: origin.y, width: width, height: 38)
  NSColor.white.withAlphaComponent(0.10).setFill()
  NSColor.white.withAlphaComponent(0.16).setStroke()
  let path = NSBezierPath(roundedRect: rect, xRadius: 19, yRadius: 19)
  path.lineWidth = 1
  path.fill()
  path.stroke()
  attributed.draw(at: NSPoint(x: rect.minX + 15, y: rect.minY + 9))
  return width
}

func render(_ card: LaunchCard) -> Data? {
  let canvas = NSImage(size: canvasSize, flipped: true) { bounds in
    NSGraphicsContext.current?.imageInterpolation = .high

    let background = NSGradient(
      colorsAndLocations: (
        NSColor(
          calibratedRed: 10 / 255,
          green: 22 / 255,
          blue: 38 / 255,
          alpha: 1
        ), 0
      ),
      (
        NSColor(
          calibratedRed: 16 / 255,
          green: 49 / 255,
          blue: 58 / 255,
          alpha: 1
        ), 0.56
      ),
      (
        NSColor(
          calibratedRed: 17 / 255,
          green: 76 / 255,
          blue: 68 / 255,
          alpha: 1
        ), 1
      )
    )
    background?.draw(in: bounds, angle: -12)

    let glow = NSGradient(
      colorsAndLocations: (
        NSColor(calibratedRed: 45 / 255, green: 174 / 255, blue: 191 / 255, alpha: 0.24), 0
      ),
      (NSColor.clear, 1)
    )
    glow?.draw(
      in: NSRect(x: 760, y: -170, width: 700, height: 700),
      relativeCenterPosition: .zero
    )

    icon.draw(
      in: NSRect(x: 68, y: 54, width: 54, height: 54),
      from: NSRect(origin: .zero, size: icon.size),
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: nil
    )
    NSAttributedString(
      string: "Desk Setup Switcher",
      attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: white,
      ]
    ).draw(at: NSPoint(x: 138, y: 68))

    let stepAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold),
      .foregroundColor: accent,
      .kern: 0.8,
    ]
    NSAttributedString(string: card.step, attributes: stepAttributes)
      .draw(at: NSPoint(x: 70, y: 170))

    let titleAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
      .foregroundColor: white,
      .kern: -0.8,
      .paragraphStyle: paragraphStyle(lineSpacing: 2),
    ]
    NSAttributedString(string: card.title, attributes: titleAttributes)
      .draw(in: NSRect(x: 68, y: 215, width: 390, height: 145))

    let bodyAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 22, weight: .regular),
      .foregroundColor: secondaryText,
      .paragraphStyle: paragraphStyle(lineSpacing: 6),
    ]
    NSAttributedString(string: card.body, attributes: bodyAttributes)
      .draw(in: NSRect(x: 70, y: 385, width: 390, height: 130))

    var tagOrigin = NSPoint(x: 70, y: 552)
    for tag in card.tags {
      let tagWidth =
        ceil(
          NSAttributedString(
            string: tag,
            attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium)]
          ).size().width
        ) + 30
      if tagOrigin.x + tagWidth > 470 {
        tagOrigin = NSPoint(x: 70, y: tagOrigin.y + 50)
      }
      let renderedWidth = drawTag(tag, at: tagOrigin)
      tagOrigin.x += renderedWidth + 10
    }

    let panelRect = NSRect(x: 505, y: 105, width: 700, height: 552)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: 12)
    shadow.set()
    NSColor.black.withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: panelRect, xRadius: 24, yRadius: 24).fill()
    NSGraphicsContext.restoreGraphicsState()

    let screenshotBounds = panelRect.insetBy(dx: 26, dy: 26)
    let screenshotRect = aspectFitRect(imageSize: card.screenshot.size, inside: screenshotBounds)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenshotRect, xRadius: 14, yRadius: 14).addClip()
    card.screenshot.draw(
      in: screenshotRect,
      from: NSRect(origin: .zero, size: card.screenshot.size),
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: nil
    )
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.22).setStroke()
    let border = NSBezierPath(
      roundedRect: screenshotRect.insetBy(dx: -1, dy: -1),
      xRadius: 15,
      yRadius: 15
    )
    border.lineWidth = 2
    border.stroke()

    NSAttributedString(
      string: "Synthetic UI  ·  No live setting changes",
      attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .regular),
        .foregroundColor: mutedText,
      ]
    ).draw(at: NSPoint(x: 70, y: 697))

    return true
  }

  guard
    let tiff = canvas.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff)
  else { return nil }
  return bitmap.representation(using: .png, properties: [.compressionFactor: 1])
}

try FileManager.default.createDirectory(
  at: outputDirectory,
  withIntermediateDirectories: true
)

for card in cards {
  guard let png = render(card) else {
    fputs("error: could not encode \(card.fileName)\n", stderr)
    exit(65)
  }
  try png.write(
    to: outputDirectory.appendingPathComponent(card.fileName),
    options: .atomic
  )
}
