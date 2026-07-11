import Foundation
import XCTest

@testable import DeskSetupSystem

final class KeychainLiveTests: XCTestCase {
  func testLiveGenericPasswordRoundTripIsExplicitlyOptIn() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["DESK_SETUP_LIVE_KEYCHAIN_TESTS"] == "1",
      "Set DESK_SETUP_LIVE_KEYCHAIN_TESTS=1 to run the live Keychain round-trip test."
    )

    let store = KeychainSecretStore()
    let account = "live-test.\(UUID().uuidString)"
    var initialSecret = Data("synthetic.\(UUID().uuidString)".utf8)
    var updatedSecret = Data("synthetic.updated.\(UUID().uuidString)".utf8)
    defer {
      try? store.delete(account: account)
      wipe(&initialSecret)
      wipe(&updatedSecret)
    }

    try store.save(initialSecret, account: account)
    var firstRead = try XCTUnwrap(store.read(account: account))
    defer { wipe(&firstRead) }
    XCTAssertEqual(firstRead, initialSecret)

    try store.save(updatedSecret, account: account)
    var secondRead = try XCTUnwrap(store.read(account: account))
    defer { wipe(&secondRead) }
    XCTAssertEqual(secondRead, updatedSecret)

    try store.delete(account: account)
    XCTAssertNil(try store.read(account: account))
  }

  private func wipe(_ data: inout Data) {
    guard !data.isEmpty else { return }
    data.resetBytes(in: data.startIndex..<data.endIndex)
    data.removeAll(keepingCapacity: false)
  }
}
