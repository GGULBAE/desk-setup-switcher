import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// Keeps short-lived operational state from permanently masking the latest
/// read-only readiness calculation.
public enum ProfileStatusLifetime {
  public static func visibleReadiness(
    calculated: ProfileReadiness?,
    operational: ProfileReadiness?
  ) -> ProfileReadiness {
    operational == .applying ? .applying : (calculated ?? .unavailable)
  }

  public static func retainingActiveOperations(
    _ statuses: [UUID: ProfileReadiness]
  ) -> [UUID: ProfileReadiness] {
    statuses.filter { _, status in status == .applying }
  }
}
