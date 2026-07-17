import AppKit
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

  private let manager: CLLocationManager?
  private let allowsSystemRequests: Bool
  private let requestWhenInUseAuthorization: @MainActor () -> Void
  private let requestLocation: @MainActor () -> Void
  private let openSystemSettingsApplication: @MainActor () -> Bool
  var onReadinessFactsChanged: (() -> Void)?

  init(
    manager: CLLocationManager? = nil,
    allowsSystemRequests: Bool = true,
    syntheticAuthorizationStatus: CLAuthorizationStatus? = nil,
    requestWhenInUseAuthorization: (@MainActor () -> Void)? = nil,
    requestLocation: (@MainActor () -> Void)? = nil,
    openSystemSettingsApplication: (@MainActor () -> Bool)? = nil
  ) {
    let activeManager =
      allowsSystemRequests
      ? (manager ?? (syntheticAuthorizationStatus == nil ? CLLocationManager() : nil))
      : nil
    self.manager = activeManager
    self.allowsSystemRequests = allowsSystemRequests
    self.requestWhenInUseAuthorization =
      requestWhenInUseAuthorization ?? { activeManager?.requestWhenInUseAuthorization() }
    self.requestLocation = requestLocation ?? { activeManager?.requestLocation() }
    self.openSystemSettingsApplication =
      openSystemSettingsApplication ?? {
        NSWorkspace.shared.open(
          URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        )
      }
    authorizationStatus =
      syntheticAuthorizationStatus ?? activeManager?.authorizationStatus ?? .denied
    super.init()
    guard let activeManager else { return }
    activeManager.delegate = self
    if authorizationStatus == .authorizedAlways || authorizationStatus == .authorized {
      Task { @MainActor [weak self] in
        self?.requestLocation()
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

  #if DEBUG
    /// Deterministic authorization transition for offscreen UI/state tests.
    /// It never calls Core Location or opens System Settings.
    func configureForUIAudit(authorizationStatus: CLAuthorizationStatus) {
      self.authorizationStatus = authorizationStatus
      lastError = nil
    }
  #endif

  func requestAccess() {
    lastError = nil
    guard allowsSystemRequests else {
      lastError = appLocalized("System access is disabled for this synthetic review.")
      return
    }
    switch authorizationStatus {
    case .notDetermined:
      requestWhenInUseAuthorization()
    case .authorizedAlways, .authorized:
      requestLocation()
    case .denied, .restricted:
      lastError = appLocalized(
        "Enable Location Services for Desk Setup Switcher in System Settings.")
    @unknown default:
      lastError = appLocalized("The current location authorization state is unknown.")
    }
  }

  func openSystemSettings() {
    lastError = nil
    guard allowsSystemRequests else {
      lastError = appLocalized("System access is disabled for this synthetic review.")
      return
    }
    guard openSystemSettingsApplication() else {
      lastError = appLocalized("macOS System Settings could not be opened.")
      return
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard allowsSystemRequests else { return }
      authorizationStatus = status
      if isAuthorized {
        requestLocation()
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
      guard allowsSystemRequests else { return }
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
      guard self?.allowsSystemRequests == true else { return }
      self?.lastError = appLocalized("A current location is not available yet.")
    }
  }
}
