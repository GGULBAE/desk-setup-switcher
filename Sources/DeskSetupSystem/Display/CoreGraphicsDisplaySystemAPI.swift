import ColorSync
import CoreGraphics
import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public struct CoreGraphicsDisplaySystemAPI: DisplaySystemAPI {
  private let matcher: DisplayIdentityMatcher

  public init(matcher: DisplayIdentityMatcher = .init()) {
    self.matcher = matcher
  }

  public func activeDisplays() async throws -> [DisplaySystemDisplay] {
    try await MainActor.run {
      try activeDisplaysSynchronously()
    }
  }

  public func apply(
    _ configuration: DisplayAtomicConfiguration,
    commitScope: DisplayConfigurationCommitScope
  ) async throws {
    try await MainActor.run {
      try applySynchronously(configuration, commitScope: commitScope)
    }
  }

  private func activeDisplaysSynchronously() throws -> [DisplaySystemDisplay] {
    let identifiers = try activeDisplayIdentifiers()
    return identifiers.map(makeSystemDisplay)
  }

  private func applySynchronously(
    _ configuration: DisplayAtomicConfiguration,
    commitScope: DisplayConfigurationCommitScope
  ) throws {
    let current = try activeDisplaysSynchronously()
    guard current.count == configuration.targets.count else {
      throw DisplayAdapterError.topologyChanged
    }

    var sessionIDByIdentity: [DisplayIdentity: UInt32] = [:]
    var usedSessionIDs = Set<UInt32>()
    for target in configuration.targets {
      let display = try resolve(target.identity, among: current)
      guard usedSessionIDs.insert(display.sessionID).inserted else {
        throw DisplayAdapterError.topologyChanged
      }
      sessionIDByIdentity[target.identity] = display.sessionID
    }

    var selectedModes: [UInt32: CGDisplayMode] = [:]
    for target in configuration.targets {
      guard let sessionID = sessionIDByIdentity[target.identity],
        let mode = coreGraphicsMode(matching: target.mode, displayID: sessionID)
      else {
        throw DisplayAdapterError.modeUnavailable
      }
      guard displayPointFitsCoreGraphics(target.origin) else {
        throw DisplayAdapterError.invalidConfiguration(
          "A display origin is outside the range accepted by Core Graphics."
        )
      }
      selectedModes[sessionID] = mode
    }

    var displayConfiguration: CGDisplayConfigRef?
    try check(
      CGBeginDisplayConfiguration(&displayConfiguration),
      operation: "begin a display configuration"
    )
    guard let displayConfiguration else {
      throw DisplayAdapterError.invalidConfiguration(
        "Core Graphics returned no display configuration handle."
      )
    }

    var shouldCancel = true
    defer {
      if shouldCancel {
        CGCancelDisplayConfiguration(displayConfiguration)
      }
    }

    for target in configuration.targets {
      guard let sessionID = sessionIDByIdentity[target.identity],
        let selectedMode = selectedModes[sessionID]
      else {
        throw DisplayAdapterError.topologyChanged
      }

      try check(
        CGConfigureDisplayOrigin(
          displayConfiguration,
          sessionID,
          Int32(target.origin.x),
          Int32(target.origin.y)
        ),
        operation: "configure a display origin"
      )
      try check(
        CGConfigureDisplayWithDisplayMode(
          displayConfiguration,
          sessionID,
          selectedMode,
          nil
        ),
        operation: "configure a display mode"
      )
    }

    for target in configuration.targets {
      guard let sessionID = sessionIDByIdentity[target.identity] else {
        throw DisplayAdapterError.topologyChanged
      }
      let mirrorSourceID: UInt32
      if let mirrorSource = target.mirrorSource {
        guard let resolvedSourceID = sessionIDByIdentity[mirrorSource],
          resolvedSourceID != sessionID
        else {
          throw DisplayAdapterError.invalidConfiguration(
            "A mirror source is missing or refers to the same display."
          )
        }
        mirrorSourceID = resolvedSourceID
      } else {
        mirrorSourceID = kCGNullDirectDisplay
      }

      try check(
        CGConfigureDisplayMirrorOfDisplay(
          displayConfiguration,
          sessionID,
          mirrorSourceID
        ),
        operation: "configure display mirroring"
      )
    }

    let option: CGConfigureOption
    switch commitScope {
    case .appOnly:
      option = CGConfigureOption(rawValue: 0)
    case .sessionOnly:
      option = CGConfigureOption(rawValue: 1)
    case .permanent:
      option = CGConfigureOption(rawValue: 2)
    }
    let completionError = CGCompleteDisplayConfiguration(displayConfiguration, option)
    // The configuration handle is invalid after completion returns, including on failure.
    shouldCancel = false
    try check(completionError, operation: "complete a display configuration")
  }

  private func activeDisplayIdentifiers() throws -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    try check(
      CGGetActiveDisplayList(0, nil, &count),
      operation: "count active displays"
    )
    guard count > 0 else { return [] }

    var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
    var returnedCount = count
    let error = identifiers.withUnsafeMutableBufferPointer { buffer in
      CGGetActiveDisplayList(count, buffer.baseAddress, &returnedCount)
    }
    try check(error, operation: "list active displays")
    return Array(identifiers.prefix(Int(returnedCount)))
  }

  private func makeSystemDisplay(_ displayID: CGDirectDisplayID) -> DisplaySystemDisplay {
    let bounds = CGDisplayBounds(displayID)
    let mirrorSource = CGDisplayMirrorsDisplay(displayID)
    return DisplaySystemDisplay(
      sessionID: displayID,
      identity: DisplayIdentity(
        uuid: stableUUID(for: displayID),
        vendorID: meaningful(CGDisplayVendorNumber(displayID)),
        modelID: meaningful(CGDisplayModelNumber(displayID)),
        serialNumber: meaningful(CGDisplaySerialNumber(displayID)),
        // Core Graphics exposes no public product-name accessor.
        productName: nil,
        isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
      ),
      bounds: DisplaySystemBounds(
        x: Int(bounds.origin.x.rounded()),
        y: Int(bounds.origin.y.rounded()),
        width: Int(bounds.width.rounded()),
        height: Int(bounds.height.rounded())
      ),
      isMain: CGDisplayIsMain(displayID) != 0,
      mirrorSourceSessionID: mirrorSource == kCGNullDirectDisplay ? nil : mirrorSource,
      rotationDegrees: Int(CGDisplayRotation(displayID).rounded()),
      isActive: CGDisplayIsActive(displayID) != 0,
      currentMode: CGDisplayCopyDisplayMode(displayID).map(makeDisplayMode),
      supportedModes: allModes(for: displayID),
      currentColorSpaceName: CGDisplayCopyColorSpace(displayID).name as String?
    )
  }

  private func stableUUID(for displayID: CGDirectDisplayID) -> UUID? {
    guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
      return nil
    }
    let bytes = CFUUIDGetUUIDBytes(unmanagedUUID.takeRetainedValue())
    return UUID(
      uuid: (
        bytes.byte0, bytes.byte1, bytes.byte2, bytes.byte3,
        bytes.byte4, bytes.byte5, bytes.byte6, bytes.byte7,
        bytes.byte8, bytes.byte9, bytes.byte10, bytes.byte11,
        bytes.byte12, bytes.byte13, bytes.byte14, bytes.byte15
      )
    )
  }

  private func meaningful(_ value: UInt32) -> UInt32? {
    value == 0 ? nil : value
  }

  private func allModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode]
    else {
      return []
    }
    return DisplayModeMatcher().deduplicated(modes.map(makeDisplayMode))
  }

  private func makeDisplayMode(_ mode: CGDisplayMode) -> DisplayMode {
    DisplayMode(
      width: mode.width,
      height: mode.height,
      pixelWidth: mode.pixelWidth,
      pixelHeight: mode.pixelHeight,
      refreshRate: mode.refreshRate
    )
  }

  private func coreGraphicsMode(
    matching desired: DisplayMode,
    displayID: CGDirectDisplayID
  ) -> CGDisplayMode? {
    var candidates: [CGDisplayMode] = []
    if let current = CGDisplayCopyDisplayMode(displayID) {
      candidates.append(current)
    }
    if let available = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] {
      candidates.append(contentsOf: available)
    }
    let matcher = DisplayModeMatcher()
    return candidates.first { matcher.matches(makeDisplayMode($0), desired) }
  }

  private func resolve(
    _ identity: DisplayIdentity,
    among displays: [DisplaySystemDisplay]
  ) throws -> DisplaySystemDisplay {
    switch matcher.match(identity, among: displays.map(\.identity)) {
    case .matched(let matchedIdentity):
      let matches = displays.filter { $0.identity == matchedIdentity }
      guard matches.count == 1, let match = matches.first else {
        throw DisplayAdapterError.topologyChanged
      }
      return match
    case .ambiguous, .noMatch:
      throw DisplayAdapterError.topologyChanged
    }
  }

  private func check(_ error: CGError, operation: String) throws {
    guard error == .success else {
      throw DisplayAdapterError.coreGraphics(
        operation: operation,
        code: Int32(error.rawValue)
      )
    }
  }
}
