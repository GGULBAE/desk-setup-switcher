@preconcurrency import ColorSync
import CoreGraphics
import CryptoKit
import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public struct CoreGraphicsDisplaySystemAPI: DisplaySystemAPI {
  private let matcher: DisplayIdentityMatcher

  private static let colorSyncDisplayDeviceClass =
    kColorSyncDisplayDeviceClass!.takeUnretainedValue()
  private static let colorSyncDeviceDefaultProfileID =
    kColorSyncDeviceDefaultProfileID!.takeUnretainedValue()
  private static let colorSyncDeviceID = kColorSyncDeviceID!.takeUnretainedValue()
  private static let colorSyncDeviceClass = kColorSyncDeviceClass!.takeUnretainedValue()
  private static let colorSyncDeviceProfileID =
    kColorSyncDeviceProfileID!.takeUnretainedValue()
  private static let colorSyncDeviceProfileURL =
    kColorSyncDeviceProfileURL!.takeUnretainedValue()
  private static let colorSyncDeviceModeDescription =
    kColorSyncDeviceModeDescription!.takeUnretainedValue()
  private static let colorSyncDeviceProfileIsCurrent =
    kColorSyncDeviceProfileIsCurrent!.takeUnretainedValue()
  private static let colorSyncCustomProfiles =
    kColorSyncCustomProfiles!.takeUnretainedValue()

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

  public func setColorProfile(
    _ target: ColorSyncProfileTarget,
    for display: DisplayIdentity
  ) async throws {
    try await MainActor.run {
      try setColorProfileSynchronously(target, for: display)
    }
  }

  public func restoreColorProfileMapping(
    _ mapping: ColorSyncCustomProfileMapping,
    for display: DisplayIdentity
  ) async throws {
    try await MainActor.run {
      try restoreColorProfileMappingSynchronously(mapping, for: display)
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
    let colorState = colorProfileState(for: displayID)
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
      currentColorSpaceName: CGDisplayCopyColorSpace(displayID).name as String?,
      availableColorProfiles: colorState?.profiles.map(\.target) ?? [],
      currentColorProfile: colorState?.profiles.first(where: \.isCurrent)?.target,
      currentColorProfileMapping: colorState?.mapping,
      canSetColorProfile: colorState?.canSet ?? false
    )
  }

  private func setColorProfileSynchronously(
    _ target: ColorSyncProfileTarget,
    for identity: DisplayIdentity
  ) throws {
    let displays = try activeDisplaysSynchronously()
    let display = try resolve(identity, among: displays)
    guard let deviceUUID = CGDisplayCreateUUIDFromDisplayID(display.sessionID)?.takeRetainedValue(),
      let state = colorProfileState(for: display.sessionID),
      state.canSet
    else {
      throw DisplayAdapterError.colorProfileUnavailable
    }
    let matches = state.profiles.filter { $0.target == target }
    guard matches.count == 1, let match = matches.first else {
      throw DisplayAdapterError.colorProfileUnavailable
    }
    let mapping: [CFString: Any] = [
      Self.colorSyncDeviceDefaultProfileID: match.url as CFURL
    ]
    guard
      ColorSyncDeviceSetCustomProfiles(
        Self.colorSyncDisplayDeviceClass,
        deviceUUID,
        mapping as CFDictionary
      )
    else {
      throw DisplayAdapterError.colorProfileMutationFailed
    }
    guard
      colorProfileState(for: display.sessionID)?.profiles.first(where: \.isCurrent)?.target
        == target
    else {
      throw DisplayAdapterError.colorProfileReadBackMismatch
    }
  }

  private func restoreColorProfileMappingSynchronously(
    _ mapping: ColorSyncCustomProfileMapping,
    for identity: DisplayIdentity
  ) throws {
    let displays = try activeDisplaysSynchronously()
    let display = try resolve(identity, among: displays)
    guard let deviceUUID = CGDisplayCreateUUIDFromDisplayID(display.sessionID)?.takeRetainedValue()
    else {
      throw DisplayAdapterError.colorProfileUnavailable
    }
    let dictionary = colorSyncDictionary(from: mapping)
    guard
      ColorSyncDeviceSetCustomProfiles(
        Self.colorSyncDisplayDeviceClass,
        deviceUUID,
        dictionary as CFDictionary
      )
    else {
      throw DisplayAdapterError.colorProfileMutationFailed
    }
    guard colorProfileState(for: display.sessionID)?.mapping == mapping else {
      throw DisplayAdapterError.colorProfileReadBackMismatch
    }
  }

  private struct RuntimeColorProfile {
    let target: ColorSyncProfileTarget
    let url: URL
    let isCurrent: Bool
  }

  private struct ColorProfileState {
    let profiles: [RuntimeColorProfile]
    let mapping: ColorSyncCustomProfileMapping
    let canSet: Bool
  }

  private final class ColorProfileIterationBox {
    let deviceUUID: UUID
    var profiles: [RuntimeColorProfile] = []

    init(deviceUUID: UUID) {
      self.deviceUUID = deviceUUID
    }
  }

  private func colorProfileState(for displayID: CGDirectDisplayID) -> ColorProfileState? {
    guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
    let deviceUUID = unmanagedUUID.takeRetainedValue()
    let uuid = Self.foundationUUID(deviceUUID)
    let box = ColorProfileIterationBox(deviceUUID: uuid)
    ColorSyncIterateDeviceProfiles(
      { dictionary, userInfo in
        guard let dictionary, let userInfo else { return false }
        let box = Unmanaged<ColorProfileIterationBox>.fromOpaque(userInfo)
          .takeUnretainedValue()
        let values = dictionary as NSDictionary
        guard let rawDeviceID = values[Self.colorSyncDeviceID],
          CFGetTypeID(rawDeviceID as CFTypeRef) == CFUUIDGetTypeID(),
          let deviceClass = values[Self.colorSyncDeviceClass] as? String,
          deviceClass == (Self.colorSyncDisplayDeviceClass as String),
          let profileID = values[Self.colorSyncDeviceProfileID] as? String,
          let url = values[Self.colorSyncDeviceProfileURL] as? URL
        else { return true }
        let deviceID = unsafeDowncast(rawDeviceID as AnyObject, to: CFUUID.self)
        guard CoreGraphicsDisplaySystemAPI.foundationUUID(deviceID) == box.deviceUUID else {
          return true
        }
        let description =
          (values[Self.colorSyncDeviceModeDescription] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
        let displayName =
          description?.isEmpty == false
          ? description!
          : url.deletingPathExtension().lastPathComponent
        guard
          let target = CoreGraphicsDisplaySystemAPI.portableColorProfileTarget(
            registeredProfileID: profileID,
            url: url,
            displayName: displayName
          )
        else { return true }
        let isCurrent =
          (values[Self.colorSyncDeviceProfileIsCurrent] as? NSNumber)?.boolValue ?? false
        box.profiles.append(
          RuntimeColorProfile(
            target: target,
            url: url,
            isCurrent: isCurrent
          )
        )
        return true
      },
      Unmanaged.passUnretained(box).toOpaque()
    )

    guard
      let unmanagedInfo = ColorSyncDeviceCopyDeviceInfo(
        Self.colorSyncDisplayDeviceClass,
        deviceUUID
      )
    else { return nil }
    let info = unmanagedInfo.takeRetainedValue() as NSDictionary
    let mapping = customProfileMapping(from: info[Self.colorSyncCustomProfiles] as? NSDictionary)
    let uniqueProfiles = Dictionary(
      grouping: box.profiles,
      by: \.target
    ).compactMap { _, matches in
      matches.count == 1 ? matches[0] : nil
    }.sorted {
      let nameOrder = $0.target.displayName.localizedCaseInsensitiveCompare(
        $1.target.displayName
      )
      if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
      return $0.target.registeredProfileID < $1.target.registeredProfileID
    }
    return ColorProfileState(
      profiles: uniqueProfiles,
      mapping: mapping,
      canSet: !uniqueProfiles.isEmpty
    )
  }

  private func customProfileMapping(
    from dictionary: NSDictionary?
  ) -> ColorSyncCustomProfileMapping {
    guard let dictionary, dictionary.count > 0 else {
      return ColorSyncCustomProfileMapping(
        entries: [
          ColorSyncCustomProfileMappingEntry(
            key: Self.colorSyncDeviceDefaultProfileID as String,
            value: .unset
          )
        ]
      )
    }
    let entries = dictionary.compactMap { rawKey, rawValue -> ColorSyncCustomProfileMappingEntry? in
      guard let key = rawKey as? String else { return nil }
      let value: ColorSyncCustomProfileMappingValue
      if let url = rawValue as? URL {
        value = .profileURL(url)
      } else if rawValue is NSNull {
        value = .unset
      } else if let scope = rawValue as? String {
        value = .scope(scope)
      } else {
        return nil
      }
      return ColorSyncCustomProfileMappingEntry(key: key, value: value)
    }.sorted { $0.key < $1.key }
    return ColorSyncCustomProfileMapping(entries: entries)
  }

  private func colorSyncDictionary(
    from mapping: ColorSyncCustomProfileMapping
  ) -> [CFString: Any] {
    Dictionary(
      uniqueKeysWithValues: mapping.entries.map { entry in
        let value: Any
        switch entry.value {
        case .profileURL(let url): value = url as CFURL
        case .unset: value = kCFNull as Any
        case .scope(let scope): value = scope as CFString
        }
        return (entry.key as CFString, value)
      })
  }

  private static func foundationUUID(_ uuid: CFUUID) -> UUID {
    let bytes = CFUUIDGetUUIDBytes(uuid)
    return UUID(
      uuid: (
        bytes.byte0, bytes.byte1, bytes.byte2, bytes.byte3,
        bytes.byte4, bytes.byte5, bytes.byte6, bytes.byte7,
        bytes.byte8, bytes.byte9, bytes.byte10, bytes.byte11,
        bytes.byte12, bytes.byte13, bytes.byte14, bytes.byte15
      )
    )
  }

  private static func sha256(url: URL) -> String? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// Converts one public ColorSync enumeration record into a portable profile
  /// target. The runtime file URL is used only to hash the ICC bytes and never
  /// crosses into the persisted model.
  static func portableColorProfileTarget(
    registeredProfileID: String,
    url: URL,
    displayName: String
  ) -> ColorSyncProfileTarget? {
    guard let hash = sha256(url: url) else { return nil }
    return ColorSyncProfileTarget(
      registeredProfileID: registeredProfileID,
      fileSHA256: hash,
      displayName: displayName
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
