import Testing

@testable import DeskSetupPresentation

@Suite("Audio volume presentation")
struct AudioVolumePresentationTests {
  @Test("zero through one scalar converts exactly to zero through one hundred percent")
  func scalarPercentageConversion() {
    for scalar in [0.0, 0.01, 0.25, 0.5, 0.75, 0.99, 1.0] {
      let percent = AudioVolumePresentation.percent(fromScalar: scalar)
      #expect(AudioVolumePresentation.scalar(fromPercent: percent) == scalar)
    }
    #expect(AudioVolumePresentation.percent(fromScalar: 0) == 0)
    #expect(AudioVolumePresentation.percent(fromScalar: 1) == 100)
  }
}
