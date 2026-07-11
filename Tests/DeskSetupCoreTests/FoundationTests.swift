import Testing

@testable import DeskSetupCore

@Suite("Domain foundation")
struct FoundationTests {
  @Test("group payload reports its group")
  func payloadReportsGroup() {
    #expect(SettingsPayload.audio(.init()).group == .audio)
    #expect(SettingsPayload.display(.init()).group == .display)
    #expect(SettingsPayload.input(.init()).group == .input)
    #expect(SettingsPayload.network(.init()).group == .network)
  }

  @Test("new document uses the current schema")
  func currentSchema() {
    #expect(ProfileDocument().schemaVersion == ProfileDocument.currentSchemaVersion)
  }
}
