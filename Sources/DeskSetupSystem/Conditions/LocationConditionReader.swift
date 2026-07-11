import CoreLocation
import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// Process-local handoff between the one-shot Core Location delegate and readiness
/// evaluation. Exact coordinates are never persisted or logged.
public actor AuthorizedLocationCache {
  public static let shared = AuthorizedLocationCache()

  private var region: LocationRegion?
  private var timestamp: Date?

  public init() {}

  public func store(_ region: LocationRegion, timestamp: Date) {
    guard region.latitude.isFinite,
      (-90...90).contains(region.latitude),
      region.longitude.isFinite,
      (-180...180).contains(region.longitude),
      region.radiusMeters.isFinite,
      region.radiusMeters >= 0
    else {
      return
    }
    self.region = region
    self.timestamp = timestamp
  }

  public func recentLocation(maximumAge: TimeInterval, now: Date) -> LocationRegion? {
    guard let region, let timestamp,
      now.timeIntervalSince(timestamp) <= max(0, maximumAge),
      timestamp.timeIntervalSince(now) <= 1
    else {
      return nil
    }
    return region
  }

  public func clear() {
    region = nil
    timestamp = nil
  }
}

/// Reads only an already-authorized, currently cached location. This reader never
/// requests authorization and never starts standard or significant-change updates.
public struct LiveConditionLocationReader: ConditionLocationReading {
  private let maximumAge: TimeInterval
  private let cache: AuthorizedLocationCache
  private let now: @Sendable () -> Date

  public init(
    maximumAge: TimeInterval = 300,
    cache: AuthorizedLocationCache = .shared,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.maximumAge = max(0, maximumAge)
    self.cache = cache
    self.now = now
  }

  public func readAuthorizedLocation() async throws -> LocationRegion? {
    let isAuthorized = await MainActor.run {
      let manager = CLLocationManager()
      switch manager.authorizationStatus {
      case .authorizedAlways, .authorized:
        return true
      case .denied, .notDetermined, .restricted:
        return false
      @unknown default:
        return false
      }
    }
    guard isAuthorized else { return nil }
    return await cache.recentLocation(maximumAge: maximumAge, now: now())
  }
}
