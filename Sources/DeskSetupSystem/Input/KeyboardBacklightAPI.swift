import Foundation
import IOKit.hidsystem

#if canImport(CoreHID)
  import CoreHID
#endif

/// Read-only availability evidence for the built-in keyboard backlight.
/// Permission and support failures are values so an input snapshot can keep
/// unrelated keyboard controls available.
public enum KeyboardBacklightReadResult: Equatable, Sendable {
  case available(KeyboardBacklightMeasurement)
  case permissionRequired
  case temporarilyUnavailable
  case unsupported
}

/// A normalized public-CoreHID value and the device-specific half-step used
/// to judge whether a requested value resolves to the same logical level.
public struct KeyboardBacklightMeasurement: Equatable, Sendable {
  public let value: Double
  public let quantizationTolerance: Double

  public init(value: Double, quantizationTolerance: Double) {
    self.value = value
    self.quantizationTolerance = quantizationTolerance
  }
}

extension KeyboardBacklightReadResult {
  /// Exact-value convenience for deterministic adapters without quantization.
  public static func available(_ value: Double) -> Self {
    .available(.init(value: value, quantizationTolerance: 0))
  }
}

public enum KeyboardBacklightAPIError: Error, Equatable, Sendable {
  case invalidValue
  case permissionRequired
  case temporarilyUnavailable
  case unsupported
  case verificationFailed(expected: Double, actual: Double)
}

public protocol KeyboardBacklightAPI: Sendable {
  func readBrightness() async -> KeyboardBacklightReadResult

  /// Writes a normalized `0...1` value and returns a verified immediate
  /// public-API read-back with the same device-specific tolerance as snapshot.
  func setBrightness(_ brightness: Double) async throws -> KeyboardBacklightMeasurement
}

enum KeyboardBacklightAccessStatus: Sendable {
  case granted
  case denied
  case unknown
}

enum KeyboardBacklightCandidatePolicy {
  static func soleCandidate<Value>(_ candidates: [Value]) -> Value? {
    candidates.count == 1 ? candidates[0] : nil
  }
}

/// A public-API-only CoreHID implementation. It never requests Input Monitoring
/// permission: background snapshots stop before discovery unless access was
/// already granted by the user.
public struct CoreHIDKeyboardBacklightAPI: KeyboardBacklightAPI {
  private let discoveryTimeout: Duration
  private let accessStatus: @Sendable () -> KeyboardBacklightAccessStatus

  public init(discoveryTimeout: Duration = .milliseconds(250)) {
    self.discoveryTimeout = discoveryTimeout
    accessStatus = Self.systemAccessStatus
  }

  init(
    discoveryTimeout: Duration = .milliseconds(250),
    accessStatus: @escaping @Sendable () -> KeyboardBacklightAccessStatus
  ) {
    self.discoveryTimeout = discoveryTimeout
    self.accessStatus = accessStatus
  }

  public func readBrightness() async -> KeyboardBacklightReadResult {
    #if canImport(CoreHID)
      guard #available(macOS 15, *) else { return .unsupported }
      guard accessStatus() == .granted else {
        return .permissionRequired
      }
      do {
        guard let target = try await discoverTarget() else { return .unsupported }
        return .available(target.measurement(value: target.brightness))
      } catch {
        return Self.readResult(for: error)
      }
    #else
      return .unsupported
    #endif
  }

  public func setBrightness(_ brightness: Double) async throws -> KeyboardBacklightMeasurement {
    #if canImport(CoreHID)
      guard #available(macOS 15, *) else {
        throw KeyboardBacklightAPIError.unsupported
      }
      guard brightness.isFinite, (0...1).contains(brightness) else {
        throw KeyboardBacklightAPIError.invalidValue
      }
      guard accessStatus() == .granted else {
        throw KeyboardBacklightAPIError.permissionRequired
      }
      do {
        guard let target = try await discoverTarget() else {
          throw KeyboardBacklightAPIError.unsupported
        }
        let actual = try await target.writeAndReadBack(brightness)
        let measurement = target.measurement(value: actual)
        guard abs(actual - brightness) <= measurement.quantizationTolerance else {
          throw KeyboardBacklightAPIError.verificationFailed(
            expected: brightness,
            actual: actual
          )
        }
        return measurement
      } catch let error as KeyboardBacklightAPIError {
        throw error
      } catch {
        throw Self.apiError(for: error)
      }
    #else
      _ = brightness
      throw KeyboardBacklightAPIError.unsupported
    #endif
  }

  private static func readResult(for error: any Error) -> KeyboardBacklightReadResult {
    switch apiError(for: error) {
    case .permissionRequired:
      return .permissionRequired
    case .unsupported, .invalidValue:
      return .unsupported
    case .temporarilyUnavailable, .verificationFailed:
      return .temporarilyUnavailable
    }
  }

  private static func systemAccessStatus() -> KeyboardBacklightAccessStatus {
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted:
      return .granted
    case kIOHIDAccessTypeDenied:
      return .denied
    default:
      return .unknown
    }
  }

  private static func apiError(for error: any Error) -> KeyboardBacklightAPIError {
    #if canImport(CoreHID)
      if #available(macOS 15, *), let error = error as? HIDDeviceError {
        switch error {
        case .notPrivileged, .notPermitted:
          return .permissionRequired
        case .unsupported, .badArgument:
          return .unsupported
        case .noResources, .exclusiveAccess, .ioError, .busy, .timeout, .notReady,
          .messageTooLarge, .noPower, .deviceError, .aborted, .notResponding, .unknown:
          return .temporarilyUnavailable
        @unknown default:
          return .temporarilyUnavailable
        }
      }
    #endif
    return .temporarilyUnavailable
  }
}

#if canImport(CoreHID)
  @available(macOS 15, *)
  extension CoreHIDKeyboardBacklightAPI {
    fileprivate struct Target: Sendable {
      let client: HIDDeviceClient
      let element: HIDElement
      let logicalMinimum: Int64
      let logicalMaximum: Int64
      let brightness: Double

      var quantizationTolerance: Double {
        let logicalRange = Double(logicalMaximum - logicalMinimum)
        return min(0.5, 0.5 / logicalRange + Double.ulpOfOne * 8)
      }

      func measurement(value: Double) -> KeyboardBacklightMeasurement {
        KeyboardBacklightMeasurement(
          value: value,
          quantizationTolerance: quantizationTolerance
        )
      }

      func writeAndReadBack(_ brightness: Double) async throws -> Double {
        let range = Double(logicalMaximum - logicalMinimum)
        let logicalValue = Int64((Double(logicalMinimum) + brightness * range).rounded())
        guard
          let value = HIDElement.Value(
            element: element,
            fromLogicalValueTruncatingIfNeeded: logicalValue,
            timestamp: .now
          )
        else {
          throw KeyboardBacklightAPIError.unsupported
        }

        let write = HIDDeviceClient.ProvideElementUpdate(values: [value])
        let writeResults = await client.updateElements([write], timeout: .milliseconds(250))
        guard let writeResult = writeResults[write] else {
          throw KeyboardBacklightAPIError.temporarilyUnavailable
        }
        try writeResult.get()

        return try await Self.read(
          client: client,
          element: element,
          logicalMinimum: logicalMinimum,
          logicalMaximum: logicalMaximum
        )
      }

      static func read(
        client: HIDDeviceClient,
        element: HIDElement,
        logicalMinimum: Int64,
        logicalMaximum: Int64
      ) async throws -> Double {
        let request = HIDDeviceClient.RequestElementUpdate(elements: [element])
        let results = await client.updateElements([request], timeout: .milliseconds(250))
        guard let result = results[request] else {
          throw KeyboardBacklightAPIError.temporarilyUnavailable
        }
        let values = try result.get()
        guard
          let value = values.first(where: { $0.element == element }),
          let logicalValue = value.logicalValue(asTypeTruncatingIfNeeded: Int64.self)
        else {
          throw KeyboardBacklightAPIError.unsupported
        }
        return min(
          1,
          max(
            0,
            Double(logicalValue - logicalMinimum) / Double(logicalMaximum - logicalMinimum)
          )
        )
      }
    }

    fileprivate actor TargetAccumulator {
      private var targets: [Target] = []

      func append(_ target: Target) {
        targets.append(target)
      }

      func allTargets() -> [Target] {
        targets
      }
    }

    fileprivate func discoverTarget() async throws -> Target? {
      let accumulator = TargetAccumulator()
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await Self.collectCompatibleTargets(into: accumulator)
        }
        group.addTask {
          try await Task.sleep(for: discoveryTimeout)
        }

        _ = try await group.next()
        group.cancelAll()
      }
      let targets = await accumulator.allTargets()
      // Every compatible readable output/feature element is a distinct candidate.
      // Ambiguous devices fail closed; no runtime handle is persisted or used to deduplicate.
      return KeyboardBacklightCandidatePolicy.soleCandidate(targets)
    }

    fileprivate static func collectCompatibleTargets(
      into accumulator: TargetAccumulator
    ) async throws {
      let manager = HIDDeviceManager()
      let criteria = [
        HIDDeviceManager.DeviceMatchingCriteria(
          isBuiltIn: true
        )
      ]
      let notifications = await manager.monitorNotifications(matchingCriteria: criteria)

      for try await notification in notifications {
        try Task.checkCancellation()
        guard case .deviceMatched(let reference) = notification,
          let client = HIDDeviceClient(deviceReference: reference),
          await client.isBuiltIn
        else {
          continue
        }

        let elements = await client.elements
        for element in elements
        where element.usage == .consumer(.keyboardBacklightSetLevel)
          && (element.type == .output || element.type == .feature)
        {
          guard let minimum = element.logicalMinimum,
            let maximum = element.logicalMaximum,
            minimum < maximum
          else {
            continue
          }
          do {
            let brightness = try await Target.read(
              client: client,
              element: element,
              logicalMinimum: minimum,
              logicalMaximum: maximum
            )
            await accumulator.append(
              Target(
                client: client,
                element: element,
                logicalMinimum: minimum,
                logicalMaximum: maximum,
                brightness: brightness
              )
            )
          } catch let error as HIDDeviceError {
            switch error {
            case .notPrivileged, .notPermitted:
              throw error
            case .noResources, .badArgument, .exclusiveAccess, .unsupported, .ioError, .busy,
              .timeout, .notReady, .messageTooLarge, .noPower, .deviceError, .aborted,
              .notResponding, .unknown:
              continue
            @unknown default:
              continue
            }
          } catch {
            continue
          }
        }
      }
    }
  }
#endif
