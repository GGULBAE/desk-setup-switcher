import AppKit

/// Contrast against a label's own dominant background, not an OS-specific
/// absolute gray threshold. Handles faint disabled text and light-on-dark text.
struct RenderedInkEvidence {
  let verticalBounds: ClosedRange<CGFloat>?
  let brightnessRange: CGFloat
}

func renderedInkEvidence(
  in bitmap: NSBitmapImageRep, viewport: CGSize, region: CGRect
) -> RenderedInkEvidence {
  let scaleX = CGFloat(bitmap.pixelsWide) / viewport.width
  let scaleY = CGFloat(bitmap.pixelsHigh) / viewport.height
  let left = max(0, Int((region.minX * scaleX).rounded(.up)))
  let right = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.down)))
  let top = max(0, Int((region.minY * scaleY).rounded(.up)))
  let bottom = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.down)))
  guard left < right, top < bottom else {
    return RenderedInkEvidence(verticalBounds: nil, brightnessRange: 0)
  }
  var samples: [(y: Int, brightness: CGFloat, bucket: Int)] = []
  var histogram: [Int: Int] = [:]
  for y in top..<bottom {
    for x in left..<right {
      guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
      let brightness =
        0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
      let bucket = Int((brightness * 255 / 4).rounded(.down))
      samples.append((y, brightness, bucket))
      histogram[bucket, default: 0] += 1
    }
  }
  let backgroundBucket = histogram.keys.sorted().max {
    histogram[$0, default: 0] < histogram[$1, default: 0]
  }
  let backgroundSamples = samples.filter { $0.bucket == backgroundBucket }
  guard !backgroundSamples.isEmpty else {
    return RenderedInkEvidence(verticalBounds: nil, brightnessRange: 0)
  }
  let background =
    backgroundSamples.reduce(CGFloat.zero) { $0 + $1.brightness }
    / CGFloat(backgroundSamples.count)
  let ink = samples.filter { abs($0.brightness - background) > 0.04 }
  let brightnessRange =
    (samples.map(\.brightness).max() ?? 0) - (samples.map(\.brightness).min() ?? 0)
  guard let first = ink.map(\.y).min(), let last = ink.map(\.y).max() else {
    return RenderedInkEvidence(verticalBounds: nil, brightnessRange: brightnessRange)
  }
  return RenderedInkEvidence(
    verticalBounds: CGFloat(first) / scaleY...CGFloat(last + 1) / scaleY,
    brightnessRange: brightnessRange
  )
}
