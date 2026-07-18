import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore

  /// Preserves the system module's original public spelling while the source
  /// model now lives in the core condition context.
  public typealias ConditionContextSource = DeskSetupCore.ConditionContextSource
#endif

public struct ConditionAudioFacts: Hashable, Sendable {
  public var inputUIDs: Set<String>
  public var outputUIDs: Set<String>

  public init(inputUIDs: Set<String> = [], outputUIDs: Set<String> = []) {
    self.inputUIDs = inputUIDs
    self.outputUIDs = outputUIDs
  }
}

public struct ConditionNetworkFacts: Hashable, Sendable {
  public var wifiSSID: String?
  public var ethernetConnected: Bool
  public var ipAddresses: Set<String>

  public init(
    wifiSSID: String? = nil,
    ethernetConnected: Bool = false,
    ipAddresses: Set<String> = []
  ) {
    self.wifiSSID = wifiSSID
    self.ethernetConnected = ethernetConnected
    self.ipAddresses = ipAddresses
  }
}

public protocol ConditionDisplayReading: Sendable {
  func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity>
}

public protocol ConditionAudioReading: Sendable {
  func readAudioFacts() async throws -> ConditionAudioFacts
}

public protocol ConditionNetworkReading: Sendable {
  func readNetworkFacts() async throws -> ConditionNetworkFacts
}

public protocol ConditionHardwareReading: Sendable {
  func readHardwareIdentifiers() async throws -> Set<String>
}

public struct ConditionContextDiagnostic: Hashable, Sendable {
  public var source: ConditionContextSource
  public var message: String

  public init(source: ConditionContextSource, message: String) {
    self.source = source
    self.message = message
  }
}

public struct ConditionContextReadResult: Hashable, Sendable {
  public var context: ConditionContext
  public var unavailableSources: Set<ConditionContextSource> {
    get { context.unavailableSources }
    set { context.unavailableSources = newValue }
  }

  public init(
    context: ConditionContext,
    unavailableSources: Set<ConditionContextSource> = []
  ) {
    var context = context
    context.unavailableSources.formUnion(unavailableSources)
    self.context = context
  }

  /// Sanitized source-level diagnostics. Reader errors and discovered values are
  /// deliberately omitted so device serials and network details cannot leak.
  public var diagnostics: [ConditionContextDiagnostic] {
    unavailableSources
      .sorted { $0.rawValue < $1.rawValue }
      .map {
        ConditionContextDiagnostic(
          source: $0,
          message: "\($0.rawValue.capitalized) readiness facts are unavailable."
        )
      }
  }
}

/// Composes the public-beta runtime facts. Each reader is attempted independently
/// so one unavailable framework or permission does not erase facts from another
/// source. Imported location conditions remain decodable in core, but this
/// provider intentionally never requests or supplies coordinates.
public struct ConditionContextProvider: Sendable {
  private let displayReader: any ConditionDisplayReading
  private let audioReader: any ConditionAudioReading
  private let networkReader: any ConditionNetworkReading
  private let hardwareReader: any ConditionHardwareReading

  public init(
    displayReader: any ConditionDisplayReading = LiveConditionDisplayReader(),
    audioReader: any ConditionAudioReading = LiveConditionAudioReader(),
    networkReader: any ConditionNetworkReading = LiveConditionNetworkReader(),
    hardwareReader: any ConditionHardwareReading = LiveUSBHardwareConditionReader()
  ) {
    self.displayReader = displayReader
    self.audioReader = audioReader
    self.networkReader = networkReader
    self.hardwareReader = hardwareReader
  }

  public func read() async -> ConditionContext {
    await discover().context
  }

  public func discover() async -> ConditionContextReadResult {
    var context = ConditionContext()

    do {
      context.displays = try await displayReader.readActiveDisplayIdentities()
    } catch {
      context.unavailableSources.insert(.displays)
    }

    do {
      let audio = try await audioReader.readAudioFacts()
      context.audioInputUIDs = audio.inputUIDs
      context.audioOutputUIDs = audio.outputUIDs
    } catch {
      context.unavailableSources.insert(.audio)
    }

    do {
      let network = try await networkReader.readNetworkFacts()
      context.wifiSSID = network.wifiSSID
      context.ethernetConnected = network.ethernetConnected
      context.ipAddresses = network.ipAddresses
    } catch {
      context.unavailableSources.insert(.network)
    }

    do {
      context.hardwareIdentifiers = try await hardwareReader.readHardwareIdentifiers()
    } catch {
      context.unavailableSources.insert(.hardware)
    }

    return ConditionContextReadResult(context: context)
  }
}
