import AppKit
import SwiftUI
import Testing

@testable import DeskSetupSwitcher

#if DEBUG
  @MainActor
  final class UIAuditLayoutRecorder {
    var frames: [String: CGRect] = [:]
  }

  struct UIAuditLayoutCaptureModifier: ViewModifier {
    let recorder: UIAuditLayoutRecorder

    func body(content: Content) -> some View {
      content.backgroundPreferenceValue(UIAuditLayoutAnchorsKey.self) { anchors in
        GeometryReader { geometry in
          let frames = anchors.mapValues { geometry[$0] }
          Color.clear
            .onChange(of: frames, initial: true) { _, frames in
              recorder.frames = frames
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    }
  }

  func containsRenderedFrame(_ child: CGRect, in parent: CGRect) -> Bool {
    child.width > 0 && child.height > 0 && parent.width > 0 && parent.height > 0
      && parent.insetBy(dx: -0.5, dy: -0.5).contains(child)
  }

  @Suite("Opt-in rendered layout evidence", .serialized)
  @MainActor
  struct UIAuditLayoutEvidenceTests {
    @Test("anchors measure rendered bounds only in an enabled audit host")
    func measuresActualBounds() throws {
      #expect(try capture(enabled: false, offset: 0).isEmpty)
      let originalFrames = try capture(enabled: true, offset: 0)
      #expect(originalFrames.count == 2, "Parent measurements must preserve child anchors")
      let original = try #require(originalFrames["sample"])
      let parent = try #require(originalFrames["parent"])
      #expect(containsRenderedFrame(original, in: parent))
      let moved = try #require(capture(enabled: true, offset: 17)["sample"])
      #expect(original.size == CGSize(width: 30, height: 20))
      #expect(moved.minX - original.minX == 17)
      #expect(moved.minY == original.minY)
    }

    @Test("containment rejects clipped, detached, and empty controls")
    func containmentRejectsBrokenLayouts() {
      let parent = CGRect(x: 20, y: 20, width: 100, height: 60)
      #expect(containsRenderedFrame(CGRect(x: 30, y: 30, width: 50, height: 20), in: parent))
      #expect(!containsRenderedFrame(CGRect(x: 10, y: 30, width: 50, height: 20), in: parent))
      #expect(!containsRenderedFrame(CGRect(x: 30, y: 90, width: 50, height: 20), in: parent))
      #expect(!containsRenderedFrame(.zero, in: parent))
    }

    @Test("label evidence detects both contrast polarities but rejects blank or nearly flat pixels")
    func relativeInkEvidence() throws {
      let bitmap = try #require(
        NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20,
          bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 120, bitsPerPixel: 24
        ))
      for (background, glyph, expectedInk) in [
        (CGFloat(0.96), CGFloat(0.96), false),
        (0.96, 0.95, false),
        (0.96, 0.86, true),
        (0.2, 0.95, true),
      ] {
        for y in 0..<20 {
          for x in 0..<40 {
            let brightness = (10..<15).contains(x) && (6..<14).contains(y) ? glyph : background
            bitmap.setColor(
              NSColor(deviceRed: brightness, green: brightness, blue: brightness, alpha: 1),
              atX: x, y: y
            )
          }
        }
        let evidence = renderedInkEvidence(
          in: bitmap, viewport: CGSize(width: 40, height: 20),
          region: CGRect(x: 0, y: 0, width: 40, height: 20)
        )
        let writtenGlyph = try #require(bitmap.colorAt(x: 12, y: 8)?.usingColorSpace(.deviceRGB))
        #expect(abs(writtenGlyph.redComponent - glyph) < 0.01)
        #expect((evidence.verticalBounds != nil) == expectedInk)
        if expectedInk { #expect(evidence.verticalBounds == 6...14) }
      }
    }

    private func capture(enabled: Bool, offset: CGFloat) throws -> [String: CGRect] {
      let recorder = UIAuditLayoutRecorder()
      let configuration = UIAuditConfiguration(
        isEnabled: enabled, variant: .overview, displayMode: .standard,
        showsStatusPopover: false
      )
      let root = Color.red.frame(width: 30, height: 20)
        .uiAuditLayoutAnchor("sample")
        .offset(x: offset)
        .frame(width: 200, height: 100)
        .uiAuditLayoutAnchor("parent")
        .environment(\.uiAuditConfiguration, configuration)
        .modifier(UIAuditLayoutCaptureModifier(recorder: recorder))
      let host = NSHostingView(rootView: root)
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
        styleMask: .borderless, backing: .buffered, defer: false
      )
      window.contentView = host
      window.setContentSize(CGSize(width: 200, height: 100))
      host.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      host.layoutSubtreeIfNeeded()
      withExtendedLifetime(window) {}
      return recorder.frames
    }
  }
#endif
