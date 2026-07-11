import Darwin
import Foundation

public enum CIDRParseError: Error, Equatable, Sendable {
  case emptyInput
  case invalidAddress(String)
  case invalidPrefix(String)
}

public enum IPAddressFamily: String, Codable, Hashable, Sendable {
  case ipv4
  case ipv6

  fileprivate var byteCount: Int {
    switch self {
    case .ipv4: 4
    case .ipv6: 16
    }
  }

  fileprivate var maximumPrefixLength: Int {
    byteCount * 8
  }
}

/// A normalized IPv4 or IPv6 network.
///
/// A bare address is accepted as a single-host network (`/32` or `/128`),
/// which lets the profile condition use the same type for an IP literal and a
/// CIDR. IPv6 scope identifiers are accepted on candidate addresses but not on
/// the stored network address.
public struct CIDR: Hashable, Sendable {
  public let family: IPAddressFamily
  public let prefixLength: Int

  private let networkBytes: [UInt8]

  public init(_ value: String) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw CIDRParseError.emptyInput
    }

    let parts = trimmed.split(
      separator: "/",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard parts.count <= 2 else {
      throw CIDRParseError.invalidPrefix(trimmed)
    }

    let addressText = String(parts[0]).trimmingCharacters(in: .whitespaces)
    guard let address = IPAddress(addressText, allowsScopeIdentifier: false) else {
      throw CIDRParseError.invalidAddress(addressText)
    }

    let prefix: Int
    if parts.count == 1 {
      prefix = address.family.maximumPrefixLength
    } else {
      let prefixText = String(parts[1]).trimmingCharacters(in: .whitespaces)
      guard
        !prefixText.isEmpty,
        prefixText.allSatisfy(\.isNumber),
        let parsedPrefix = Int(prefixText),
        (0...address.family.maximumPrefixLength).contains(parsedPrefix)
      else {
        throw CIDRParseError.invalidPrefix(prefixText)
      }
      prefix = parsedPrefix
    }

    family = address.family
    prefixLength = prefix
    networkBytes = Self.mask(address.bytes, to: prefix)
  }

  public func contains(_ address: String) -> Bool {
    guard
      let candidate = IPAddress(address, allowsScopeIdentifier: true),
      candidate.family == family
    else {
      return false
    }

    return Self.mask(candidate.bytes, to: prefixLength) == networkBytes
  }

  private static func mask(_ bytes: [UInt8], to prefixLength: Int) -> [UInt8] {
    var masked = bytes
    let completeBytes = prefixLength / 8
    let remainingBits = prefixLength % 8

    if remainingBits > 0, completeBytes < masked.count {
      let bitMask = UInt8.max << (8 - remainingBits)
      masked[completeBytes] &= bitMask
    }

    let firstClearedIndex = completeBytes + (remainingBits > 0 ? 1 : 0)
    if firstClearedIndex < masked.count {
      for index in firstClearedIndex..<masked.count {
        masked[index] = 0
      }
    }

    return masked
  }
}

private struct IPAddress {
  var family: IPAddressFamily
  var bytes: [UInt8]

  init?(_ input: String, allowsScopeIdentifier: Bool) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    var addressText = trimmed
    var hasScopeIdentifier = false
    if let percentIndex = addressText.firstIndex(of: "%") {
      guard allowsScopeIdentifier else {
        return nil
      }
      let scope = addressText[addressText.index(after: percentIndex)...]
      guard
        !scope.isEmpty,
        !scope.contains("%"),
        !scope.contains(where: \.isWhitespace)
      else {
        return nil
      }
      hasScopeIdentifier = true
      addressText = String(addressText[..<percentIndex])
    }

    // Zone identifiers are meaningful only for IPv6. Do not accidentally
    // accept a malformed IPv4 value by stripping its suffix first.
    if !hasScopeIdentifier {
      var ipv4 = in_addr()
      if addressText.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
        family = .ipv4
        bytes = withUnsafeBytes(of: &ipv4) { Array($0) }
        return
      }
    }

    var ipv6 = in6_addr()
    if addressText.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
      family = .ipv6
      bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
      return
    }

    return nil
  }
}
