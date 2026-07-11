import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public enum LiveAdapterFactory {
  /// Returns the concrete adapters in stable product order. Constructing the adapters
  /// performs no discovery and changes no system setting.
  public static func makeAdapters() -> [any SystemSettingsAdapter] {
    [
      CoreGraphicsDisplayAdapter(),
      CoreAudioAdapter(),
      NetworkAdapter(),
      InputPreferencesAdapter(),
    ]
  }
}
