import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public enum DisplayConfigurationCommitScope: String, Codable, Hashable, Sendable {
  case appOnly
  case sessionOnly
  case permanent
}

public struct DisplaySystemBounds: Hashable, Sendable {
  public var x: Int
  public var y: Int
  public var width: Int
  public var height: Int

  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

/// A live, session-scoped display record. `sessionID` must never be copied into a profile
/// or other persisted core model.
public struct DisplaySystemDisplay: Hashable, Sendable {
  public var sessionID: UInt32
  public var identity: DisplayIdentity
  public var bounds: DisplaySystemBounds
  public var isMain: Bool
  public var mirrorSourceSessionID: UInt32?
  public var rotationDegrees: Int
  public var isActive: Bool
  public var currentMode: DisplayMode?
  public var supportedModes: [DisplayMode]

  public init(
    sessionID: UInt32,
    identity: DisplayIdentity,
    bounds: DisplaySystemBounds,
    isMain: Bool,
    mirrorSourceSessionID: UInt32? = nil,
    rotationDegrees: Int,
    isActive: Bool,
    currentMode: DisplayMode?,
    supportedModes: [DisplayMode]
  ) {
    self.sessionID = sessionID
    self.identity = identity
    self.bounds = bounds
    self.isMain = isMain
    self.mirrorSourceSessionID = mirrorSourceSessionID
    self.rotationDegrees = rotationDegrees
    self.isActive = isActive
    self.currentMode = currentMode
    self.supportedModes = supportedModes
  }
}

/// One member of a complete atomic configuration. Only stable identity data is encoded.
public struct DisplayConfigurationTarget: Codable, Hashable, Sendable {
  public var identity: DisplayIdentity
  public var origin: DisplayPoint
  public var mirrorSource: DisplayIdentity?
  public var mode: DisplayMode

  public init(
    identity: DisplayIdentity,
    origin: DisplayPoint,
    mirrorSource: DisplayIdentity?,
    mode: DisplayMode
  ) {
    self.identity = identity
    self.origin = origin
    self.mirrorSource = mirrorSource
    self.mode = mode
  }
}

public struct DisplayAtomicConfiguration: Codable, Hashable, Sendable {
  public var targets: [DisplayConfigurationTarget]

  public init(targets: [DisplayConfigurationTarget]) {
    self.targets = targets
  }
}

public protocol DisplaySystemAPI: Sendable {
  func activeDisplays() async throws -> [DisplaySystemDisplay]
  func apply(
    _ configuration: DisplayAtomicConfiguration,
    commitScope: DisplayConfigurationCommitScope
  ) async throws
}

public enum DisplayAdapterError: Error, Hashable, Sendable {
  case coreGraphics(operation: String, code: Int32)
  case invalidConfiguration(String)
  case invalidOperationPayload
  case modeUnavailable
  case topologyChanged
}

extension DisplayAdapterError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .coreGraphics(let operation, let code):
      "Core Graphics could not \(operation) (error \(code))."
    case .invalidConfiguration(let reason):
      reason
    case .invalidOperationPayload:
      "The display operation payload is invalid."
    case .modeUnavailable:
      "A requested display mode is no longer available."
    case .topologyChanged:
      "The active display topology changed after the operation was planned."
    }
  }
}

func displayPointFitsCoreGraphics(_ point: DisplayPoint) -> Bool {
  Int(Int32.min) <= point.x && point.x <= Int(Int32.max) && Int(Int32.min) <= point.y
    && point.y <= Int(Int32.max)
}
