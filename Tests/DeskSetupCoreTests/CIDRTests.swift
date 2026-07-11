import XCTest

@testable import DeskSetupCore

final class CIDRTests: XCTestCase {
  func testIPv4NetworkNormalizesHostBitsAndMatchesBoundaries() throws {
    let network = try CIDR("192.168.7.99/24")

    XCTAssertEqual(network.family, .ipv4)
    XCTAssertEqual(network.prefixLength, 24)
    XCTAssertTrue(network.contains("192.168.7.0"))
    XCTAssertTrue(network.contains("192.168.7.255"))
    XCTAssertFalse(network.contains("192.168.8.0"))
  }

  func testIPv6CompressedNetworkMatchesAndAcceptsCandidateScope() throws {
    let network = try CIDR("fe80::1234/64")

    XCTAssertEqual(network.family, .ipv6)
    XCTAssertTrue(network.contains("fe80::abcd%en0"))
    XCTAssertFalse(network.contains("fe81::abcd%en0"))
  }

  func testBareAddressesAreSingleHostNetworks() throws {
    let ipv4 = try CIDR("203.0.113.8")
    let ipv6 = try CIDR("2001:db8::5")

    XCTAssertEqual(ipv4.prefixLength, 32)
    XCTAssertTrue(ipv4.contains("203.0.113.8"))
    XCTAssertFalse(ipv4.contains("203.0.113.9"))
    XCTAssertEqual(ipv6.prefixLength, 128)
    XCTAssertTrue(ipv6.contains("2001:0db8:0:0:0:0:0:5"))
  }

  func testZeroPrefixMatchesOnlyItsAddressFamily() throws {
    let ipv4 = try CIDR("0.0.0.0/0")
    let ipv6 = try CIDR("::/0")

    XCTAssertTrue(ipv4.contains("198.51.100.42"))
    XCTAssertFalse(ipv4.contains("2001:db8::1"))
    XCTAssertTrue(ipv6.contains("2001:db8::1"))
    XCTAssertFalse(ipv6.contains("198.51.100.42"))
  }

  func testIPv4MappedIPv6RemainsIPv6() throws {
    let mappedNetwork = try CIDR("::ffff:192.0.2.0/120")

    XCTAssertTrue(mappedNetwork.contains("::ffff:192.0.2.44"))
    XCTAssertFalse(mappedNetwork.contains("192.0.2.44"))
  }

  func testInvalidInputIsRejectedAndInvalidCandidatesDoNotMatch() throws {
    XCTAssertThrowsError(try CIDR(""))
    XCTAssertThrowsError(try CIDR("192.0.2.1/33"))
    XCTAssertThrowsError(try CIDR("2001:db8::/129"))
    XCTAssertThrowsError(try CIDR("192.0.2.1/-1"))
    XCTAssertThrowsError(try CIDR("192.0.2.1/24/7"))
    XCTAssertThrowsError(try CIDR("fe80::1%en0/64"))
    XCTAssertThrowsError(try CIDR("example.invalid/24"))

    let network = try CIDR("192.0.2.0/24")
    XCTAssertFalse(network.contains("not-an-address"))
    XCTAssertFalse(network.contains("192.0.2.1%en0"))
  }
}
