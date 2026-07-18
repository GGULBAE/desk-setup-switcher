import Darwin
import Foundation

public struct ProfileValidationLimits: Equatable, Sendable {
  public static let standard = ProfileValidationLimits()

  public var maximumDocumentBytes: Int
  public var maximumProfiles: Int
  public var maximumConditionsPerProfile: Int
  public var maximumStringScalars: Int

  public init(
    maximumDocumentBytes: Int = 5 * 1024 * 1024,
    maximumProfiles: Int = 500,
    maximumConditionsPerProfile: Int = 100,
    maximumStringScalars: Int = 1_024
  ) {
    self.maximumDocumentBytes = maximumDocumentBytes
    self.maximumProfiles = maximumProfiles
    self.maximumConditionsPerProfile = maximumConditionsPerProfile
    self.maximumStringScalars = maximumStringScalars
  }
}

public struct ProfileDocumentValidator: Sendable {
  public let limits: ProfileValidationLimits

  public init(limits: ProfileValidationLimits = .standard) {
    self.limits = limits
  }

  public func validate(_ document: ProfileDocument) throws {
    var issues: [ProfileValidationIssue] = []

    if document.schemaVersion != ProfileDocument.currentSchemaVersion {
      issues.append(
        .unsupportedSchema(
          found: document.schemaVersion,
          expected: ProfileDocument.currentSchemaVersion
        ))
    }
    if document.profiles.count > limits.maximumProfiles {
      issues.append(
        .tooManyProfiles(
          actual: document.profiles.count,
          maximum: limits.maximumProfiles
        ))
    }

    var profileIDs = Set<UUID>()
    for profile in document.profiles {
      if !profileIDs.insert(profile.id).inserted {
        issues.append(.duplicateProfileID(profile.id))
      }
      validate(profile, issues: &issues)
    }

    if let selectedProfileID = document.selectedProfileID,
      !profileIDs.contains(selectedProfileID)
    {
      issues.append(.invalidSelectedProfileID(selectedProfileID))
    }

    if !issues.isEmpty {
      throw ProfileValidationError(issues: issues)
    }
  }

  private func validate(_ profile: DeskProfile, issues: inout [ProfileValidationIssue]) {
    let base = "profiles[\(profile.id)]"
    checkLength(profile.name, at: "\(base).name", issues: &issues)
    checkLength(
      profile.profileDescription,
      at: "\(base).profileDescription",
      issues: &issues
    )
    checkLength(profile.symbolName, at: "\(base).symbolName", issues: &issues)
    requireNonBlank(profile.name, at: "\(base).name", issues: &issues)
    requireNonBlank(profile.symbolName, at: "\(base).symbolName", issues: &issues)

    validateConditions(
      profile.conditions,
      profileID: profile.id,
      at: "\(base).conditions",
      issues: &issues
    )
    validateDisplay(
      profile.settings.display.value,
      semanticsEnabled: profile.settings.display.isIncluded,
      at: "\(base).settings.display",
      issues: &issues
    )
    validateAudio(
      profile.settings.audio.value,
      semanticsEnabled: profile.settings.audio.isIncluded,
      at: "\(base).settings.audio",
      issues: &issues
    )
    validateNetwork(
      profile.settings.network.value,
      semanticsEnabled: profile.settings.network.isIncluded,
      at: "\(base).settings.network",
      issues: &issues
    )
    validateInput(
      profile.settings.input.value,
      semanticsEnabled: profile.settings.input.isIncluded,
      at: "\(base).settings.input",
      issues: &issues
    )

    if let lastApplication = profile.lastApplication {
      for (index, item) in lastApplication.items.enumerated() {
        checkLength(
          item.key,
          at: "\(base).lastApplication.items[\(index)].key",
          issues: &issues
        )
        checkLength(
          item.message,
          at: "\(base).lastApplication.items[\(index)].message",
          issues: &issues
        )
      }
    }
  }

  private func validateDisplay(
    _ settings: DisplayProfileSettings,
    semanticsEnabled: Bool,
    at base: String,
    issues: inout [ProfileValidationIssue]
  ) {
    var targetIDs = Set<UUID>()
    for (index, display) in settings.displays.enumerated() {
      let path = "\(base).displays[\(index)]"
      if !targetIDs.insert(display.id).inserted {
        invalid("\(path).id", .duplicateIdentifier, issues: &issues)
      }
      checkLength(display.identity.productName, at: "\(path).productName", issues: &issues)

      if semanticsEnabled {
        validateIncludedPresence(
          display.colorProfile,
          at: "\(path).colorProfile",
          issues: &issues
        )
      }

      if semanticsEnabled, display.origin.isIncluded {
        let origin = display.origin.value
        if !fitsInt32(origin.x) {
          invalid("\(path).origin.x", .outOfRange, issues: &issues)
        }
        if !fitsInt32(origin.y) {
          invalid("\(path).origin.y", .outOfRange, issues: &issues)
        }
      }

      if semanticsEnabled, display.mode.isIncluded {
        let mode = display.mode.value
        let dimensions = [mode.width, mode.height, mode.pixelWidth, mode.pixelHeight]
        if !dimensions.allSatisfy({ (1...100_000).contains($0) }) {
          invalid("\(path).mode.dimensions", .invalidDimensions, issues: &issues)
        }
        if !mode.refreshRate.isFinite {
          invalid("\(path).mode.refreshRate", .nonFinite, issues: &issues)
        } else if !(0...1_000).contains(mode.refreshRate) {
          invalid("\(path).mode.refreshRate", .outOfRange, issues: &issues)
        }
      }

      if semanticsEnabled,
        display.rotationDegrees.isIncluded,
        !Set([0, 90, 180, 270]).contains(display.rotationDegrees.value)
      {
        invalid("\(path).rotationDegrees", .invalidRotation, issues: &issues)
      }

      if case .mirrors(let identity) = display.mirroring.value {
        checkLength(
          identity.productName,
          at: "\(path).mirroring.productName",
          issues: &issues
        )
      }
    }
  }

  private func validateAudio(
    _ settings: AudioProfileSettings,
    semanticsEnabled: Bool,
    at base: String,
    issues: inout [ProfileValidationIssue]
  ) {
    checkLength(settings.defaultInputUID.value, at: "\(base).defaultInputUID", issues: &issues)
    checkLength(settings.defaultOutputUID.value, at: "\(base).defaultOutputUID", issues: &issues)
    checkLength(settings.systemOutputUID.value, at: "\(base).systemOutputUID", issues: &issues)
    guard semanticsEnabled else { return }

    validateIncludedString(
      settings.defaultInputUID,
      at: "\(base).defaultInputUID",
      issues: &issues
    )
    validateIncludedString(
      settings.defaultOutputUID,
      at: "\(base).defaultOutputUID",
      issues: &issues
    )
    validateIncludedString(
      settings.systemOutputUID,
      at: "\(base).systemOutputUID",
      issues: &issues
    )
    validateIncludedNumber(
      settings.inputVolume,
      range: 0...1,
      at: "\(base).inputVolume",
      issues: &issues
    )
    validateIncludedNumber(
      settings.outputVolume,
      range: 0...1,
      at: "\(base).outputVolume",
      issues: &issues
    )
    validateIncludedPresence(
      settings.outputMuted,
      at: "\(base).outputMuted",
      issues: &issues
    )
  }

  private func validateNetwork(
    _ settings: NetworkProfileSettings,
    semanticsEnabled: Bool,
    at base: String,
    issues: inout [ProfileValidationIssue]
  ) {
    checkLength(settings.wifiSSID.value, at: "\(base).wifiSSID", issues: &issues)
    if semanticsEnabled {
      validateIncludedPresence(settings.wifiPower, at: "\(base).wifiPower", issues: &issues)
      validateIncludedString(settings.wifiSSID, at: "\(base).wifiSSID", issues: &issues)
    }

    for (index, service) in settings.serviceIPv4.enumerated() {
      let serviceBase = "\(base).serviceIPv4[\(index)]"
      checkLength(
        service.identity.serviceName,
        at: "\(serviceBase).identity.serviceName",
        issues: &issues
      )
      checkLength(
        service.identity.interfaceType,
        at: "\(serviceBase).identity.interfaceType",
        issues: &issues
      )
      guard let configuration = service.configuration.value else {
        if semanticsEnabled, service.configuration.isIncluded {
          invalid(serviceBase, .missingIncludedValue, issues: &issues)
        }
        continue
      }
      if case .manual(let address, let subnetMask, let router) = configuration {
        checkLength(address, at: "\(serviceBase).address", issues: &issues)
        checkLength(subnetMask, at: "\(serviceBase).subnetMask", issues: &issues)
        checkLength(router, at: "\(serviceBase).router", issues: &issues)
        if semanticsEnabled, service.configuration.isIncluded {
          if !isIPv4Address(address) {
            invalid("\(serviceBase).address", .malformedIPv4Address, issues: &issues)
          }
          if !isContiguousIPv4Mask(subnetMask) {
            invalid("\(serviceBase).subnetMask", .malformedSubnetMask, issues: &issues)
          }
          if let router, !isIPv4Address(router) {
            invalid("\(serviceBase).router", .malformedIPv4Address, issues: &issues)
          }
        }
      }
    }

    if semanticsEnabled, settings.ipv4.isIncluded {
      if let configuration = settings.ipv4.value {
        if case .manual(let address, let subnetMask, let router) = configuration {
          checkLength(address, at: "\(base).ipv4.address", issues: &issues)
          checkLength(subnetMask, at: "\(base).ipv4.subnetMask", issues: &issues)
          checkLength(router, at: "\(base).ipv4.router", issues: &issues)
          if !isIPv4Address(address) {
            invalid("\(base).ipv4.address", .malformedIPv4Address, issues: &issues)
          }
          if !isContiguousIPv4Mask(subnetMask) {
            invalid("\(base).ipv4.subnetMask", .malformedSubnetMask, issues: &issues)
          }
          if let router, !isIPv4Address(router) {
            invalid("\(base).ipv4.router", .malformedIPv4Address, issues: &issues)
          }
        }
      } else {
        invalid("\(base).ipv4", .missingIncludedValue, issues: &issues)
      }
    } else if case .manual(let address, let subnetMask, let router)? = settings.ipv4.value {
      checkLength(address, at: "\(base).ipv4.address", issues: &issues)
      checkLength(subnetMask, at: "\(base).ipv4.subnetMask", issues: &issues)
      checkLength(router, at: "\(base).ipv4.router", issues: &issues)
    }

    validateDNS(
      settings.dnsServers,
      semanticsEnabled: semanticsEnabled,
      at: "\(base).dnsServers",
      issues: &issues
    )
    validateProxy(
      settings.webProxy,
      semanticsEnabled: semanticsEnabled,
      at: "\(base).webProxy",
      issues: &issues
    )
    validateProxy(
      settings.secureWebProxy,
      semanticsEnabled: semanticsEnabled,
      at: "\(base).secureWebProxy",
      issues: &issues
    )
  }

  private func validateDNS(
    _ option: SettingOption<[String]>,
    semanticsEnabled: Bool,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) {
    for (index, server) in option.value.enumerated() {
      let itemPath = "\(path)[\(index)]"
      checkLength(server, at: itemPath, issues: &issues)
      if semanticsEnabled, option.isIncluded, !isIPAddress(server) {
        invalid(itemPath, .malformedIPAddress, issues: &issues)
      }
    }
  }

  private func validateProxy(
    _ option: SettingOption<ProxyConfiguration?>,
    semanticsEnabled: Bool,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) {
    if let proxy = option.value {
      checkLength(proxy.host, at: "\(path).host", issues: &issues)
    }
    guard semanticsEnabled, option.isIncluded else { return }
    guard let proxy = option.value else {
      invalid(path, .missingIncludedValue, issues: &issues)
      return
    }
    guard proxy.enabled else { return }
    if isBlank(proxy.host) {
      invalid("\(path).host", .blank, issues: &issues)
    }
    if !(1...65_535).contains(proxy.port) {
      invalid("\(path).port", .outOfRange, issues: &issues)
    }
  }

  private func validateInput(
    _ settings: InputProfileSettings,
    semanticsEnabled: Bool,
    at base: String,
    issues: inout [ProfileValidationIssue]
  ) {
    guard semanticsEnabled else { return }
    validateIncludedNumber(
      settings.pointerSpeed,
      range: -1...10,
      at: "\(base).pointerSpeed",
      issues: &issues
    )
    validateIncludedPresence(
      settings.naturalScrolling,
      at: "\(base).naturalScrolling",
      issues: &issues
    )
    validateIncludedNumber(
      settings.keyRepeatInterval,
      range: 1...120,
      at: "\(base).keyRepeatInterval",
      issues: &issues
    )
    validateIncludedNumber(
      settings.initialKeyRepeatDelay,
      range: 1...300,
      at: "\(base).initialKeyRepeatDelay",
      issues: &issues
    )
    validateIncludedPresence(
      settings.useStandardFunctionKeys,
      at: "\(base).useStandardFunctionKeys",
      issues: &issues
    )
  }

  private func validateConditions(
    _ conditionSet: ProfileConditionSet,
    profileID: UUID,
    at base: String,
    issues: inout [ProfileValidationIssue]
  ) {
    if conditionSet.conditions.count > limits.maximumConditionsPerProfile {
      issues.append(
        .tooManyConditions(
          profileID: profileID,
          actual: conditionSet.conditions.count,
          maximum: limits.maximumConditionsPerProfile
        ))
    }

    var conditionIDs = Set<UUID>()
    for (index, condition) in conditionSet.conditions.enumerated() {
      let path = "\(base)[\(index)]"
      if !conditionIDs.insert(condition.id).inserted {
        issues.append(
          .duplicateConditionID(
            profileID: profileID,
            conditionID: condition.id
          ))
      }
      validate(condition.kind, at: path, issues: &issues)
    }
  }

  private func validate(
    _ kind: ProfileConditionKind,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) {
    switch kind {
    case .displayConnected(let identity):
      checkLength(identity.productName, at: "\(path).display.productName", issues: &issues)
      if let productName = identity.productName, isBlank(productName) {
        invalid("\(path).display.productName", .blank, issues: &issues)
      } else if identity.productName == nil,
        identity.uuid == nil,
        (identity.vendorID ?? 0) == 0,
        (identity.modelID ?? 0) == 0,
        (identity.serialNumber ?? 0) == 0
      {
        invalid("\(path).display", .blank, issues: &issues)
      }
    case .audioInputConnected(let uid), .audioOutputConnected(let uid):
      checkLength(uid, at: "\(path).audioUID", issues: &issues)
      requireNonBlank(uid, at: "\(path).audioUID", issues: &issues)
    case .hardwareConnected(let identifier):
      checkLength(identifier, at: "\(path).hardwareIdentifier", issues: &issues)
      requireNonBlank(identifier, at: "\(path).hardwareIdentifier", issues: &issues)
    case .wifiSSID(let ssid):
      checkLength(ssid, at: "\(path).wifiSSID", issues: &issues)
      requireNonBlank(ssid, at: "\(path).wifiSSID", issues: &issues)
    case .ipAddressOrCIDR(let value):
      checkLength(value, at: "\(path).ipAddressOrCIDR", issues: &issues)
      if isBlank(value) {
        invalid("\(path).ipAddressOrCIDR", .blank, issues: &issues)
      } else if !isIPAddressOrCIDR(value) {
        invalid("\(path).ipAddressOrCIDR", .malformedCIDR, issues: &issues)
      }
    case .location(let region):
      validateFinite(
        region.latitude,
        range: -90...90,
        at: "\(path).location.latitude",
        issues: &issues
      )
      validateFinite(
        region.longitude,
        range: -180...180,
        at: "\(path).location.longitude",
        issues: &issues
      )
      if !region.radiusMeters.isFinite {
        invalid("\(path).location.radiusMeters", .nonFinite, issues: &issues)
      } else if region.radiusMeters < 0 || region.radiusMeters > 40_000_000 {
        invalid("\(path).location.radiusMeters", .outOfRange, issues: &issues)
      }
    case .ethernetConnected:
      break
    }
  }

  private func validateIncludedString(
    _ option: SettingOption<String?>,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) {
    guard option.isIncluded else { return }
    guard let value = option.value else {
      invalid(path, .missingIncludedValue, issues: &issues)
      return
    }
    requireNonBlank(value, at: path, issues: &issues)
  }

  private func validateIncludedNumber(
    _ option: SettingOption<Double?>,
    range: ClosedRange<Double>,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) {
    guard option.isIncluded else { return }
    guard let value = option.value else {
      invalid(path, .missingIncludedValue, issues: &issues)
      return
    }
    validateFinite(value, range: range, at: path, issues: &issues)
  }

  private func validateIncludedPresence<Value>(
    _ option: SettingOption<Value?>,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) where Value: Codable & Hashable & Sendable {
    if option.isIncluded, option.value == nil {
      invalid(path, .missingIncludedValue, issues: &issues)
    }
  }

  private func validateFinite(
    _ value: Double,
    range: ClosedRange<Double>,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) {
    if !value.isFinite {
      invalid(path, .nonFinite, issues: &issues)
    } else if !range.contains(value) {
      invalid(path, .outOfRange, issues: &issues)
    }
  }

  private func requireNonBlank(
    _ value: String,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) {
    if isBlank(value) {
      invalid(path, .blank, issues: &issues)
    }
  }

  private func checkLength(
    _ value: String?,
    at path: String,
    issues: inout [ProfileValidationIssue]
  ) {
    guard let value else { return }
    let scalarCount = value.unicodeScalars.count
    if scalarCount > limits.maximumStringScalars {
      issues.append(
        .stringTooLong(
          path: path,
          scalarCount: scalarCount,
          maximum: limits.maximumStringScalars
        ))
    }
  }

  private func invalid(
    _ path: String,
    _ reason: ProfileInvalidValueReason,
    issues: inout [ProfileValidationIssue]
  ) {
    issues.append(.invalidValue(path: path, reason: reason))
  }

  private func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func fitsInt32(_ value: Int) -> Bool {
    Int(Int32.min) <= value && value <= Int(Int32.max)
  }

  private func isIPv4Address(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.utf8.contains(0) else { return false }
    var address = in_addr()
    return trimmed.withCString {
      inet_pton(AF_INET, $0, &address) == 1
    }
  }

  private func isIPAddress(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.utf8.contains(0) else { return false }
    var ipv4 = in_addr()
    if trimmed.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
      return true
    }
    var ipv6 = in6_addr()
    return trimmed.withCString { inet_pton(AF_INET6, $0, &ipv6) == 1 }
  }

  private func isIPAddressOrCIDR(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.utf8.contains(0) else { return false }
    return (try? CIDR(trimmed)) != nil
  }

  private func isContiguousIPv4Mask(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.utf8.contains(0) else { return false }
    var address = in_addr()
    let parsed = trimmed.withCString {
      inet_pton(AF_INET, $0, &address) == 1
    }
    guard parsed else { return false }

    let bytes = withUnsafeBytes(of: &address) { Array($0) }
    var sawZero = false
    for byte in bytes {
      for shift in stride(from: 7, through: 0, by: -1) {
        let isOne = byte & (UInt8(1) << shift) != 0
        if sawZero && isOne { return false }
        if !isOne { sawZero = true }
      }
    }
    return true
  }
}
