import Combine
import CoreLocation
import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupSystem)
  import DeskSetupSystem
#endif

@MainActor
final class LocationPermissionController: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published private(set) var authorizationStatus: CLAuthorizationStatus
  @Published private(set) var lastError: String?

  private let manager: CLLocationManager
  var onReadinessFactsChanged: (() -> Void)?

  override init() {
    let manager = CLLocationManager()
    self.manager = manager
    authorizationStatus = manager.authorizationStatus
    super.init()
    manager.delegate = self
    if authorizationStatus == .authorizedAlways || authorizationStatus == .authorized {
      Task { @MainActor [weak self] in
        self?.manager.requestLocation()
      }
    }
  }

  var isAuthorized: Bool {
    authorizationStatus == .authorizedAlways || authorizationStatus == .authorized
  }

  var statusText: String {
    if let lastError { return lastError }
    return switch authorizationStatus {
    case .notDetermined: appLocalized("Not requested")
    case .restricted: appLocalized("Restricted by system policy")
    case .denied: appLocalized("Denied")
    case .authorizedAlways, .authorized: appLocalized("Allowed")
    @unknown default: appLocalized("Unknown")
    }
  }

  func requestAccess() {
    lastError = nil
    switch authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorized:
      manager.requestLocation()
    case .denied, .restricted:
      lastError = appLocalized(
        "Enable Location Services for Desk Setup Switcher in System Settings.")
    @unknown default:
      lastError = appLocalized("The current location authorization state is unknown.")
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    Task { @MainActor [weak self] in
      guard let self else { return }
      authorizationStatus = status
      if isAuthorized {
        self.manager.requestLocation()
      } else {
        await AuthorizedLocationCache.shared.clear()
        onReadinessFactsChanged?()
      }
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
    let latitude = location.coordinate.latitude
    let longitude = location.coordinate.longitude
    let accuracy = location.horizontalAccuracy
    let timestamp = location.timestamp
    Task { @MainActor [weak self] in
      guard let self else { return }
      await AuthorizedLocationCache.shared.store(
        LocationRegion(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: accuracy
        ),
        timestamp: timestamp
      )
      lastError = nil
      onReadinessFactsChanged?()
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor [weak self] in
      self?.lastError = appLocalized("A current location is not available yet.")
    }
  }
}
