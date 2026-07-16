import Foundation

public enum AudioVolumePresentation {
  public static func percent(fromScalar scalar: Double) -> Double {
    scalar * 100
  }

  public static func scalar(fromPercent percent: Double) -> Double {
    percent / 100
  }
}
