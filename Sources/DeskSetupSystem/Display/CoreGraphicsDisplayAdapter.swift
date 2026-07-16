import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public struct CoreGraphicsDisplayAdapter: SystemSettingsAdapter {
  public let group: SettingGroup = .display

  private let systemAPI: any DisplaySystemAPI
  private let matcher: DisplayIdentityMatcher
  private let now: @Sendable () -> Date

  public init(
    systemAPI: any DisplaySystemAPI = CoreGraphicsDisplaySystemAPI(),
    matcher: DisplayIdentityMatcher = .init(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.systemAPI = systemAPI
    self.matcher = matcher
    self.now = now
  }

  public func capability() async -> AdapterCapability {
    AdapterCapability(
      group: .display,
      state: .supported,
      reason:
        "Public Core Graphics supports active-display discovery, topology, mirroring, and modes. Rotation and active-state mutation are unavailable."
    )
  }

  public func snapshot() async throws -> AdapterSnapshot {
    let displays = try await systemAPI.activeDisplays()
    let displayBySessionID = Dictionary(
      uniqueKeysWithValues: displays.map { ($0.sessionID, $0) }
    )
    var targets: [DisplayTargetSettings] = []
    var items: [SnapshotItem] = []

    for (index, display) in displays.enumerated() {
      let fallbackMode = DisplayMode(
        width: display.bounds.width,
        height: display.bounds.height,
        refreshRate: 0
      )
      let mirrorSource = display.mirrorSourceSessionID.flatMap {
        displayBySessionID[$0]?.identity
      }
      let mirrorWasReadable = display.mirrorSourceSessionID == nil || mirrorSource != nil
      let mirroring: DisplayMirroring = mirrorSource.map(DisplayMirroring.mirrors) ?? .extended
      let target = DisplayTargetSettings(
        id: display.identity.uuid ?? UUID(),
        identity: display.identity,
        isPrimary: SettingOption(value: display.isMain),
        origin: SettingOption(
          value: DisplayPoint(x: display.bounds.x, y: display.bounds.y)
        ),
        mirroring: SettingOption(
          isIncluded: mirrorWasReadable,
          value: mirroring
        ),
        mode: SettingOption(
          isIncluded: display.currentMode != nil,
          value: display.currentMode ?? fallbackMode
        ),
        colorProfile: SettingOption(
          isIncluded: display.canSetColorProfile
            && display.currentColorProfile != nil
            && display.currentColorProfileMapping != nil,
          value: display.currentColorProfile
        ),
        rotationDegrees: SettingOption(
          isIncluded: false,
          value: display.rotationDegrees
        ),
        isActive: SettingOption(
          isIncluded: false,
          value: display.isActive
        )
      )
      targets.append(target)

      let readable = display.currentMode != nil && mirrorWasReadable
      let label =
        display.identity.productName
        ?? (display.identity.isBuiltIn ? "Built-in Display" : "External Display")
      items.append(
        SnapshotItem(
          key: display.identity.uuid.map { "display.\($0.uuidString)" }
            ?? "display.\(index)",
          label: label,
          state: readable ? .storable : .unreadable,
          detail:
            "Bounds \(display.bounds.width)×\(display.bounds.height) at (\(display.bounds.x), \(display.bounds.y))."
        )
      )
      if target.colorProfile.isIncluded {
        items.append(
          SnapshotItem(
            key: "display.colorProfile.\(index)",
            label: "ColorSync ICC profile",
            state: .storable,
            detail: "A public ColorSync profile catalog and rollback mapping are available."
          )
        )
      }
    }

    if displays.isEmpty {
      items.append(
        SnapshotItem(
          key: "display.active",
          label: "Displays",
          state: .unsupported,
          detail: "Core Graphics reported no active displays."
        )
      )
    }

    return AdapterSnapshot(
      group: .display,
      capturedAt: now(),
      payload: .display(DisplayProfileSettings(displays: targets)),
      items: items,
      displayModeCatalog: displays.map {
        DisplayModeCatalogEntry(identity: $0.identity, modes: $0.supportedModes)
      },
      displayColorEvidence: displays.compactMap { display in
        display.currentColorSpaceName.map {
          DisplayColorEvidenceEntry(identity: display.identity, colorSpaceName: $0)
        }
      },
      displayColorProfileCatalog: displays.map {
        DisplayColorProfileCatalogEntry(
          identity: $0.identity,
          profiles: $0.availableColorProfiles,
          canApply: $0.canSetColorProfile
            && $0.currentColorProfileMapping != nil
        )
      }
    )
  }

  public func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue] {
    guard snapshot.group == .display,
      snapshot.payload == nil || snapshot.payload?.group == .display
    else {
      return [
        makeIssue(
          key: "snapshot",
          message: "The supplied snapshot does not contain display settings.",
          isFatal: true
        )
      ]
    }
    guard case .display(let settings) = desired else {
      return [
        makeIssue(
          key: "payload",
          message: "The display adapter received a payload for another settings group.",
          isFatal: true
        )
      ]
    }

    do {
      let current = try await systemAPI.activeDisplays()
      let displayAnalysis = analyze(settings, current: current)
      let colorAnalysis = try analyzeColorProfiles(
        settings,
        current: current,
        createOperations: false
      )
      return displayAnalysis.issues + colorAnalysis.issues
    } catch {
      return [
        makeIssue(
          key: "snapshot",
          message: "The current display configuration could not be read safely.",
          isFatal: true
        )
      ]
    }
  }

  public func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan {
    guard snapshot.group == .display,
      case .display(let settings) = desired
    else {
      throw DisplayAdapterError.invalidConfiguration(
        "The display adapter received an invalid snapshot or payload."
      )
    }
    _ = mode

    let current = try await systemAPI.activeDisplays()
    let analysis = analyze(settings, current: current)
    let colorAnalysis = try analyzeColorProfiles(
      settings,
      current: current,
      createOperations: true
    )
    var operations: [PlannedOperation] = []
    if let finalConfiguration = analysis.finalConfiguration,
      let rollbackConfiguration = analysis.rollbackConfiguration,
      finalConfiguration != rollbackConfiguration
    {
      operations.append(
        PlannedOperation(
          group: .display,
          key: "display.atomic-configuration",
          summary: "Apply the complete display configuration",
          risk: .high,
          isFatalOnFailure: true,
          preview: OperationPreview(
            previousValue: previewDescription(rollbackConfiguration),
            desiredValue: previewDescription(finalConfiguration)
          ),
          payload: try encode(finalConfiguration),
          rollbackPayload: try encode(rollbackConfiguration)
        )
      )
    }

    operations.append(contentsOf: colorAnalysis.operations)

    return AdapterPlan(
      group: .display,
      operations: operations,
      omissions: analysis.omissions + colorAnalysis.omissions,
      issues: analysis.issues + colorAnalysis.issues
    )
  }

  private func previewDescription(_ configuration: DisplayAtomicConfiguration) -> String {
    configuration.targets.map { target in
      let identity = previewIdentity(target.identity)
      let mode = target.mode
      let refresh = String(
        format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), mode.refreshRate)
      let mirror = target.mirrorSource.map { " → \(previewIdentity($0))" } ?? ""
      return
        "\(identity) • \(mode.width)×\(mode.height) (\(mode.pixelWidth)×\(mode.pixelHeight) px) @ \(refresh) Hz • x:\(target.origin.x) y:\(target.origin.y)\(mirror)"
    }
    .joined(separator: "\n")
  }

  private func previewIdentity(_ identity: DisplayIdentity) -> String {
    if let name = identity.productName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    {
      return name
    }
    if identity.isBuiltIn {
      return "Built-in display"
    }
    if let uuid = identity.uuid {
      return "🖥 \(uuid.uuidString.prefix(8))"
    }
    if let vendor = identity.vendorID, let model = identity.modelID {
      return "🖥 \(vendor):\(model)"
    }
    return "🖥"
  }

  public func apply(_ operation: PlannedOperation) async -> OperationResult {
    guard operation.group == .display else {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: DisplayAdapterError.invalidOperationPayload.localizedDescription
      )
    }

    do {
      if operation.key == "display.atomic-configuration" {
        let configuration = try decode(operation.payload)
        try await systemAPI.apply(configuration, commitScope: .appOnly)
        guard try await configurationMatchesCurrentState(configuration) else {
          throw DisplayAdapterError.topologyChanged
        }
      } else if operation.key.hasPrefix("display.colorProfile."),
        let colorOperation = try? JSONDecoder().decode(
          DisplayColorProfileOperation.self,
          from: operation.payload
        )
      {
        try await systemAPI.setColorProfile(
          colorOperation.target,
          for: colorOperation.display
        )
        guard
          try await currentColorProfile(for: colorOperation.display)
            == colorOperation.target
        else {
          throw DisplayAdapterError.colorProfileReadBackMismatch
        }
      } else {
        throw DisplayAdapterError.invalidOperationPayload
      }
      return OperationResult(
        operationID: operation.id,
        status: .succeeded,
        message: operation.key == "display.atomic-configuration"
          ? "The display configuration was applied temporarily and will revert if the app exits before confirmation."
          : "The ColorSync ICC display profile was applied and verified."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "The atomic display configuration could not be applied."
      )
    }
  }

  public func confirm(_ operation: PlannedOperation) async -> OperationResult {
    guard operation.group == .display else {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: DisplayAdapterError.invalidOperationPayload.localizedDescription
      )
    }

    do {
      if operation.key == "display.atomic-configuration" {
        let configuration = try decode(operation.payload)
        try await systemAPI.apply(configuration, commitScope: .sessionOnly)
        guard try await configurationMatchesCurrentState(configuration) else {
          throw DisplayAdapterError.topologyChanged
        }
      } else if operation.key.hasPrefix("display.colorProfile."),
        let colorOperation = try? JSONDecoder().decode(
          DisplayColorProfileOperation.self,
          from: operation.payload
        )
      {
        guard
          try await currentColorProfile(for: colorOperation.display)
            == colorOperation.target
        else {
          throw DisplayAdapterError.colorProfileReadBackMismatch
        }
      } else {
        throw DisplayAdapterError.invalidOperationPayload
      }
      return OperationResult(
        operationID: operation.id,
        status: .succeeded,
        message: operation.key == "display.atomic-configuration"
          ? "The confirmed display configuration was committed for the login session."
          : "The ColorSync ICC display profile was kept."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "The temporary display configuration could not be committed."
      )
    }
  }

  public func rollback(_ operation: PlannedOperation) async -> OperationResult {
    guard operation.group == .display,
      let rollbackPayload = operation.rollbackPayload
    else {
      return OperationResult(
        operationID: operation.id,
        status: .rollbackFailed,
        message: "No complete display rollback configuration is available."
      )
    }

    do {
      if operation.key == "display.atomic-configuration" {
        let configuration = try decode(rollbackPayload)
        try await systemAPI.apply(configuration, commitScope: .sessionOnly)
        guard try await configurationMatchesCurrentState(configuration) else {
          throw DisplayAdapterError.topologyChanged
        }
      } else if operation.key.hasPrefix("display.colorProfile."),
        let rollback = try? JSONDecoder().decode(
          DisplayColorProfileRollback.self,
          from: rollbackPayload
        )
      {
        try await systemAPI.restoreColorProfileMapping(
          rollback.mapping,
          for: rollback.display
        )
        guard try await currentColorProfile(for: rollback.display) == rollback.expectedTarget
        else {
          throw DisplayAdapterError.colorProfileReadBackMismatch
        }
      } else {
        throw DisplayAdapterError.invalidOperationPayload
      }
      return OperationResult(
        operationID: operation.id,
        status: .rolledBack,
        message: operation.key == "display.atomic-configuration"
          ? "The previous display configuration was restored."
          : "The previous ColorSync ICC display profile mapping was restored."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .rollbackFailed,
        message: "The previous display configuration could not be restored."
      )
    }
  }

  public func diagnostics() async -> [DiagnosticEntry] {
    [
      DiagnosticEntry(
        severity: .info,
        component: "adapter.display",
        code: "display.public-core-graphics",
        message:
          "Display discovery and supported mutations use public Core Graphics APIs. Rotation and active-state mutation are not attempted."
      )
    ]
  }

  private func analyzeColorProfiles(
    _ desired: DisplayProfileSettings,
    current displays: [DisplaySystemDisplay],
    createOperations: Bool
  ) throws -> DisplayColorAnalysis {
    var analysis = DisplayColorAnalysis()

    for target in desired.displays where target.colorProfile.isIncluded {
      let key = "display.colorProfile.\(target.id.uuidString)"
      guard let desiredProfile = target.colorProfile.value else {
        recordColorIssue(
          key: key,
          message: "Choose a ColorSync ICC display profile.",
          isFatal: true,
          in: &analysis
        )
        continue
      }

      let display: DisplaySystemDisplay
      switch resolve(target.identity, among: displays) {
      case .matched(let match):
        display = match
      case .ambiguous:
        recordColorIssue(
          key: key,
          message: "The saved display identity is ambiguous.",
          isFatal: true,
          in: &analysis
        )
        continue
      case .missing:
        // The row is absent when its display is not resolvable in this runtime.
        continue
      }

      guard display.canSetColorProfile,
        let rollbackMapping = display.currentColorProfileMapping
      else {
        // Unsupported ColorSync controls are hidden, not disabled or omitted.
        continue
      }
      let matches = display.availableColorProfiles.filter { $0 == desiredProfile }
      guard matches.count == 1 else {
        recordColorIssue(
          key: key,
          message: matches.isEmpty
            ? "The saved ColorSync ICC profile is no longer available for this display."
            : "The saved ColorSync ICC profile identity is ambiguous.",
          isFatal: true,
          in: &analysis
        )
        continue
      }
      guard display.currentColorProfile != desiredProfile, createOperations else { continue }

      let payload = DisplayColorProfileOperation(
        display: display.identity,
        target: desiredProfile
      )
      let rollback = DisplayColorProfileRollback(
        display: display.identity,
        mapping: rollbackMapping,
        expectedTarget: display.currentColorProfile
      )
      analysis.operations.append(
        PlannedOperation(
          group: .display,
          key: key,
          summary: "Apply the ColorSync ICC profile for a display",
          risk: .high,
          isFatalOnFailure: true,
          preview: OperationPreview(
            previousValue: display.currentColorProfile?.displayName ?? "Factory default",
            desiredValue: desiredProfile.displayName
          ),
          payload: try encodeJSON(payload),
          rollbackPayload: try encodeJSON(rollback)
        )
      )
    }

    return analysis
  }

  private func recordColorIssue(
    key: String,
    message: String,
    isFatal: Bool,
    in analysis: inout DisplayColorAnalysis
  ) {
    analysis.issues.append(makeIssue(key: key, message: message, isFatal: isFatal))
    analysis.omissions.append(
      PlanOmission(
        group: .display,
        key: key,
        status: .skipped,
        reason: message
      )
    )
  }

  private func configurationMatchesCurrentState(
    _ configuration: DisplayAtomicConfiguration
  ) async throws -> Bool {
    let current = try await systemAPI.activeDisplays()
    guard current.count == configuration.targets.count else { return false }
    for target in configuration.targets {
      guard case .matched(let display) = resolve(target.identity, among: current),
        display.bounds.x == target.origin.x,
        display.bounds.y == target.origin.y,
        let currentMode = display.currentMode,
        DisplayModeMatcher().matches(currentMode, target.mode)
      else { return false }

      let currentMirrorIdentity = display.mirrorSourceSessionID.flatMap { sourceID in
        current.first(where: { $0.sessionID == sourceID })?.identity
      }
      guard currentMirrorIdentity == target.mirrorSource else { return false }
    }
    return true
  }

  private func currentColorProfile(
    for identity: DisplayIdentity
  ) async throws -> ColorSyncProfileTarget? {
    let displays = try await systemAPI.activeDisplays()
    guard case .matched(let display) = resolve(identity, among: displays) else {
      throw DisplayAdapterError.topologyChanged
    }
    return display.currentColorProfile
  }

  private func encodeJSON<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  private func analyze(
    _ desired: DisplayProfileSettings,
    current displays: [DisplaySystemDisplay]
  ) -> DisplayAnalysis {
    var analysis = DisplayAnalysis()
    let rollbackConfiguration: DisplayAtomicConfiguration
    do {
      rollbackConfiguration = try completeConfiguration(from: displays)
    } catch {
      record(
        key: "display.rollback",
        message: "A complete rollback configuration could not be captured.",
        isFatal: true,
        status: .skipped,
        in: &analysis
      )
      return analysis
    }
    analysis.rollbackConfiguration = rollbackConfiguration

    let indexBySessionID = Dictionary(
      uniqueKeysWithValues: displays.enumerated().map { ($0.element.sessionID, $0.offset) }
    )
    var finalTargets = rollbackConfiguration.targets
    var matchedTargets: [(DisplayTargetSettings, DisplaySystemDisplay)] = []
    var usedSessionIDs = Set<UInt32>()
    var blocksEntirePlan = false

    for target in desired.displays {
      let key = "display.\(target.id.uuidString).identity"
      switch resolve(target.identity, among: displays) {
      case .matched(let display):
        guard usedSessionIDs.insert(display.sessionID).inserted else {
          record(
            key: key,
            message: "More than one saved target resolves to the same active display.",
            isFatal: true,
            status: .skipped,
            in: &analysis
          )
          blocksEntirePlan = true
          continue
        }
        matchedTargets.append((target, display))
      case .ambiguous:
        record(
          key: key,
          message: "The saved display identity matches more than one active display.",
          isFatal: false,
          status: .skipped,
          in: &analysis
        )
      case .missing:
        record(
          key: key,
          message: "The saved display is not currently active.",
          isFatal: false,
          status: .skipped,
          in: &analysis
        )
      }
    }

    let requestedPrimaryDisplays = matchedTargets.filter {
      $0.0.isPrimary.isIncluded && $0.0.isPrimary.value
    }
    if requestedPrimaryDisplays.count > 1 {
      record(
        key: "display.primary",
        message: "A display configuration can contain only one primary display.",
        isFatal: true,
        status: .skipped,
        in: &analysis
      )
      blocksEntirePlan = true
    }
    let requestedPrimarySessionID = requestedPrimaryDisplays.first?.1.sessionID

    for (target, display) in matchedTargets {
      guard let configurationIndex = indexBySessionID[display.sessionID] else {
        blocksEntirePlan = true
        continue
      }
      let keyPrefix = "display.\(target.id.uuidString)"

      if target.origin.isIncluded {
        let requestedOrigin = target.origin.value
        var canApplyOrigin = true
        if !displayPointFitsCoreGraphics(requestedOrigin) {
          record(
            key: "\(keyPrefix).origin",
            message: "The requested display origin is outside the public Core Graphics range.",
            isFatal: false,
            status: .unsupported,
            in: &analysis
          )
          canApplyOrigin = false
        } else if display.isMain && requestedOrigin != DisplayPoint(x: 0, y: 0)
          && requestedPrimarySessionID == nil
        {
          record(
            key: "\(keyPrefix).origin",
            message:
              "The primary display must remain at (0, 0) unless another display becomes primary.",
            isFatal: false,
            status: .unsupported,
            in: &analysis
          )
          canApplyOrigin = false
        } else if !display.isMain && requestedOrigin == DisplayPoint(x: 0, y: 0)
          && requestedPrimarySessionID != display.sessionID
        {
          record(
            key: "\(keyPrefix).origin",
            message: "Moving a display to (0, 0) requires selecting it as primary.",
            isFatal: false,
            status: .unsupported,
            in: &analysis
          )
          canApplyOrigin = false
        }
        if canApplyOrigin {
          finalTargets[configurationIndex].origin = requestedOrigin
        }
      }

      if target.mode.isIncluded {
        let candidates = display.supportedModes + [display.currentMode].compactMap { $0 }
        if let supportedMode = DisplayModeMatcher().match(
          target.mode.value,
          among: candidates
        ) {
          finalTargets[configurationIndex].mode = supportedMode
        } else {
          record(
            key: "\(keyPrefix).mode",
            message: "The requested logical size, pixel size, or refresh rate is unsupported.",
            isFatal: false,
            status: .unsupported,
            in: &analysis
          )
        }
      }

      if target.mirroring.isIncluded {
        switch target.mirroring.value {
        case .extended:
          finalTargets[configurationIndex].mirrorSource = nil
        case .mirrors(let sourceIdentity):
          switch resolve(sourceIdentity, among: displays) {
          case .matched(let source) where source.sessionID != display.sessionID:
            finalTargets[configurationIndex].mirrorSource = source.identity
          case .matched:
            record(
              key: "\(keyPrefix).mirroring",
              message: "A display cannot mirror itself.",
              isFatal: false,
              status: .unsupported,
              in: &analysis
            )
          case .ambiguous:
            record(
              key: "\(keyPrefix).mirroring",
              message: "The mirror source identity is ambiguous.",
              isFatal: false,
              status: .skipped,
              in: &analysis
            )
          case .missing:
            record(
              key: "\(keyPrefix).mirroring",
              message: "The mirror source is not currently active.",
              isFatal: false,
              status: .skipped,
              in: &analysis
            )
          }
        }
      }

      if target.rotationDegrees.isIncluded,
        target.rotationDegrees.value != display.rotationDegrees
      {
        let permittedRotations = Set([0, 90, 180, 270])
        let message =
          permittedRotations.contains(target.rotationDegrees.value)
          ? "Public Core Graphics does not expose display rotation mutation."
          : "Display rotation must be one of 0, 90, 180, or 270 degrees."
        record(
          key: "\(keyPrefix).rotation",
          message: message,
          isFatal: false,
          status: .unsupported,
          in: &analysis
        )
      }

      if target.isActive.isIncluded, target.isActive.value != display.isActive {
        record(
          key: "\(keyPrefix).active",
          message: "Public Core Graphics does not expose safe active-state mutation.",
          isFatal: false,
          status: .unsupported,
          in: &analysis
        )
      }

      if target.isPrimary.isIncluded && !target.isPrimary.value && display.isMain
        && requestedPrimarySessionID == nil
      {
        record(
          key: "\(keyPrefix).primary",
          message: "Select another active display as primary before clearing the current primary.",
          isFatal: false,
          status: .unsupported,
          in: &analysis
        )
      }
    }

    if let requestedPrimarySessionID,
      let primaryIndex = indexBySessionID[requestedPrimarySessionID]
    {
      let offset = finalTargets[primaryIndex].origin
      for index in finalTargets.indices {
        let (translatedX, xOverflow) = finalTargets[index].origin.x
          .subtractingReportingOverflow(offset.x)
        let (translatedY, yOverflow) = finalTargets[index].origin.y
          .subtractingReportingOverflow(offset.y)
        guard !xOverflow, !yOverflow else {
          record(
            key: "display.primary",
            message:
              "Selecting the primary display would overflow a display coordinate.",
            isFatal: true,
            status: .skipped,
            in: &analysis
          )
          blocksEntirePlan = true
          break
        }
        let translated = DisplayPoint(
          x: translatedX,
          y: translatedY
        )
        guard displayPointFitsCoreGraphics(translated) else {
          record(
            key: "display.primary",
            message:
              "Selecting the primary display would move an origin outside the supported range.",
            isFatal: true,
            status: .skipped,
            in: &analysis
          )
          blocksEntirePlan = true
          break
        }
        finalTargets[index].origin = translated
      }
    }

    if !blocksEntirePlan {
      analysis.finalConfiguration = DisplayAtomicConfiguration(targets: finalTargets)
    }
    return analysis
  }

  private func completeConfiguration(
    from displays: [DisplaySystemDisplay]
  ) throws -> DisplayAtomicConfiguration {
    guard Set(displays.map(\.identity)).count == displays.count else {
      throw DisplayAdapterError.invalidConfiguration(
        "Active displays do not have unique stable identities."
      )
    }
    let displayBySessionID = Dictionary(
      uniqueKeysWithValues: displays.map { ($0.sessionID, $0) }
    )
    let targets = try displays.map { display -> DisplayConfigurationTarget in
      guard let mode = display.currentMode else {
        throw DisplayAdapterError.invalidConfiguration(
          "The current mode could not be read for every active display."
        )
      }
      let mirrorSource: DisplayIdentity?
      if let mirrorSourceSessionID = display.mirrorSourceSessionID {
        guard let source = displayBySessionID[mirrorSourceSessionID] else {
          throw DisplayAdapterError.invalidConfiguration(
            "The current mirror source could not be identified."
          )
        }
        mirrorSource = source.identity
      } else {
        mirrorSource = nil
      }
      return DisplayConfigurationTarget(
        identity: display.identity,
        origin: DisplayPoint(x: display.bounds.x, y: display.bounds.y),
        mirrorSource: mirrorSource,
        mode: mode
      )
    }
    return DisplayAtomicConfiguration(targets: targets)
  }

  private func resolve(
    _ identity: DisplayIdentity,
    among displays: [DisplaySystemDisplay]
  ) -> DisplayResolution {
    switch matcher.match(identity, among: displays.map(\.identity)) {
    case .matched(let matchedIdentity):
      let matches = displays.filter { $0.identity == matchedIdentity }
      guard matches.count == 1, let match = matches.first else {
        return .ambiguous
      }
      return .matched(match)
    case .ambiguous:
      return .ambiguous
    case .noMatch:
      return .missing
    }
  }

  private func record(
    key: String,
    message: String,
    isFatal: Bool,
    status: ApplicationItemStatus,
    in analysis: inout DisplayAnalysis
  ) {
    analysis.issues.append(
      makeIssue(key: key, message: message, isFatal: isFatal)
    )
    analysis.omissions.append(
      PlanOmission(
        group: .display,
        key: key,
        status: status,
        reason: message
      )
    )
  }

  private func makeIssue(
    key: String,
    message: String,
    isFatal: Bool
  ) -> ValidationIssue {
    ValidationIssue(
      group: .display,
      key: key,
      severity: isFatal ? .error : .warning,
      isFatal: isFatal,
      message: message
    )
  }

  private func encode(_ configuration: DisplayAtomicConfiguration) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(configuration)
  }

  private func decode(_ data: Data) throws -> DisplayAtomicConfiguration {
    do {
      return try JSONDecoder().decode(DisplayAtomicConfiguration.self, from: data)
    } catch {
      throw DisplayAdapterError.invalidOperationPayload
    }
  }
}

private struct DisplayAnalysis {
  var issues: [ValidationIssue] = []
  var omissions: [PlanOmission] = []
  var finalConfiguration: DisplayAtomicConfiguration?
  var rollbackConfiguration: DisplayAtomicConfiguration?
}

private struct DisplayColorAnalysis {
  var issues: [ValidationIssue] = []
  var omissions: [PlanOmission] = []
  var operations: [PlannedOperation] = []
}

private struct DisplayColorProfileOperation: Codable, Hashable, Sendable {
  let display: DisplayIdentity
  let target: ColorSyncProfileTarget
}

private struct DisplayColorProfileRollback: Codable, Hashable, Sendable {
  let display: DisplayIdentity
  let mapping: ColorSyncCustomProfileMapping
  let expectedTarget: ColorSyncProfileTarget?
}

private enum DisplayResolution {
  case matched(DisplaySystemDisplay)
  case ambiguous
  case missing
}
