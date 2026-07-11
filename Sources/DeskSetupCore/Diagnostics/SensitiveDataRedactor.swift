import Darwin
import Foundation

public protocol SensitiveDataRedacting: Sendable {
  func redact(_ value: String) -> String
  func redact(_ entry: DiagnosticEntry) -> DiagnosticEntry
}

/// Deterministically removes secrets and identifying local data from text
/// before it is handed to a diagnostic persistence boundary.
public struct SensitiveDataRedactor: SensitiveDataRedacting, Sendable {
  public static let replacement = "<redacted>"
  public static let homeReplacement = "<home>"

  private let homeDirectoryPath: String?

  public init(homeDirectory: URL? = FileManager.default.homeDirectoryForCurrentUser) {
    let path = homeDirectory?.standardizedFileURL.path
    homeDirectoryPath = path?.isEmpty == false ? path : nil
  }

  public func redact(_ entry: DiagnosticEntry) -> DiagnosticEntry {
    var result = entry
    result.component = redact(entry.component)
    result.code = redact(entry.code)
    result.message = redact(entry.message)
    return result
  }

  public func redact(_ value: String) -> String {
    var result = value

    // Redact labeled values before network addresses so a password or SSID
    // that happens to look like an address is never retained as a prefix.
    result = Self.replacingLabeledValue(in: result, using: Self.credentialPattern)
    result = Self.replacingLabeledValue(in: result, using: Self.coordinatePattern)
    result = Self.replacingLabeledValue(in: result, using: Self.ssidPattern)
    result = redactHomeDirectories(in: result)
    result = Self.redactIPv6Addresses(in: result)
    result = Self.redactIPv4Addresses(in: result)

    return result
  }

  private func redactHomeDirectories(in value: String) -> String {
    var result = value

    if let homeDirectoryPath {
      let escapedPath = NSRegularExpression.escapedPattern(for: homeDirectoryPath)
      let pattern = "(?<![A-Za-z0-9._-])\(escapedPath)(?=/|\\\\|[\\s,;:)'\"]|$)"
      if let expression = try? NSRegularExpression(pattern: pattern) {
        result = expression.stringByReplacingMatches(
          in: result,
          range: NSRange(result.startIndex..., in: result),
          withTemplate: Self.homeReplacement
        )
      }
    }

    result = Self.genericHomePattern.stringByReplacingMatches(
      in: result,
      range: NSRange(result.startIndex..., in: result),
      withTemplate: Self.homeReplacement
    )
    return result
  }

  private static func replacingLabeledValue(
    in value: String,
    using expression: NSRegularExpression
  ) -> String {
    let original = value as NSString
    var result = original
    let matches = expression.matches(
      in: value,
      range: NSRange(location: 0, length: original.length)
    )

    // Work backwards so the UTF-16 ranges from the original string remain
    // valid after later matches change length.
    for match in matches.reversed() {
      guard match.numberOfRanges > 1 else {
        continue
      }
      let prefix = original.substring(with: match.range(at: 1))
      result =
        result.replacingCharacters(
          in: match.range,
          with: prefix + Self.replacement
        ) as NSString
    }
    return result as String
  }

  private static func redactIPv4Addresses(in value: String) -> String {
    replacingMatches(in: value, using: ipv4CandidatePattern) { candidate in
      guard let redacted = redactedNetwork(candidate, family: .ipv4) else {
        return candidate
      }
      return redacted
    }
  }

  private static func redactIPv6Addresses(in value: String) -> String {
    replacingMatches(in: value, using: ipv6CandidatePattern) { candidate in
      guard candidate.contains(":"),
        let redacted = redactedNetwork(candidate, family: .ipv6)
      else {
        return candidate
      }
      return redacted
    }
  }

  private static func replacingMatches(
    in value: String,
    using expression: NSRegularExpression,
    transform: (String) -> String
  ) -> String {
    let original = value as NSString
    var result = original
    let matches = expression.matches(
      in: value,
      range: NSRange(location: 0, length: original.length)
    )

    for match in matches.reversed() {
      let candidate = original.substring(with: match.range)
      result =
        result.replacingCharacters(
          in: match.range,
          with: transform(candidate)
        ) as NSString
    }
    return result as String
  }

  private static func redactedNetwork(
    _ candidate: String,
    family: IPAddressFamily
  ) -> String? {
    let pieces = candidate.split(
      separator: "/",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard pieces.count <= 2 else {
      return nil
    }

    var address = String(pieces[0])
    if family == .ipv6, let scopeIndex = address.firstIndex(of: "%") {
      address = String(address[..<scopeIndex])
    }

    let maximumPrefix = family == .ipv4 ? 32 : 128
    let privacyPrefix = family == .ipv4 ? 24 : 64
    let requestedPrefix: Int
    if pieces.count == 2 {
      guard let parsed = Int(pieces[1]), (0...maximumPrefix).contains(parsed) else {
        return nil
      }
      requestedPrefix = parsed
    } else {
      requestedPrefix = maximumPrefix
    }
    let retainedPrefix = min(requestedPrefix, privacyPrefix)

    switch family {
    case .ipv4:
      var parsed = in_addr()
      guard address.withCString({ inet_pton(AF_INET, $0, &parsed) }) == 1 else {
        return nil
      }
      var bytes = withUnsafeBytes(of: &parsed) { Array($0) }
      mask(&bytes, prefixLength: retainedPrefix)
      var masked = in_addr()
      withUnsafeMutableBytes(of: &masked) { destination in
        destination.copyBytes(from: bytes)
      }
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      guard inet_ntop(AF_INET, &masked, &buffer, socklen_t(buffer.count)) != nil else {
        return nil
      }
      return "\(decodedAddress(from: buffer))/\(retainedPrefix)"

    case .ipv6:
      var parsed = in6_addr()
      guard address.withCString({ inet_pton(AF_INET6, $0, &parsed) }) == 1 else {
        return nil
      }
      var bytes = withUnsafeBytes(of: &parsed) { Array($0) }
      mask(&bytes, prefixLength: retainedPrefix)
      var masked = in6_addr()
      withUnsafeMutableBytes(of: &masked) { destination in
        destination.copyBytes(from: bytes)
      }
      var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
      guard inet_ntop(AF_INET6, &masked, &buffer, socklen_t(buffer.count)) != nil else {
        return nil
      }
      return "\(decodedAddress(from: buffer))/\(retainedPrefix)"
    }
  }

  private static func decodedAddress(from buffer: [CChar]) -> String {
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }

  private static func mask(_ bytes: inout [UInt8], prefixLength: Int) {
    let completeBytes = prefixLength / 8
    let remainingBits = prefixLength % 8

    if remainingBits > 0, completeBytes < bytes.count {
      bytes[completeBytes] &= UInt8.max << (8 - remainingBits)
    }

    let firstClearedIndex = completeBytes + (remainingBits > 0 ? 1 : 0)
    if firstClearedIndex < bytes.count {
      for index in firstClearedIndex..<bytes.count {
        bytes[index] = 0
      }
    }
  }

  private static let credentialPattern = try! NSRegularExpression(
    pattern:
      #"(?i)(["']?(?:password|passwd|passphrase|access[_-]?token|refresh[_-]?token|auth[_-]?token|token|api[ _-]?key|credential(?:s)?|authorization|secret)\b["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|Bearer\s+[^\s,;}\]]+|[^\s,;}\]]+)"#
  )

  private static let coordinatePattern = try! NSRegularExpression(
    pattern:
      #"(?i)(["']?(?:latitude|longitude|lat|lon|lng)\b["']?\s*[:=]\s*)(?:["']?[-+]?(?:\d+(?:\.\d*)?|\.\d+)["']?)"#
  )

  private static let ssidPattern = try! NSRegularExpression(
    pattern:
      #"(?i)(["']?(?:(?:wi-?fi[ _-]*)?ssid)\b["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;}\]]+)"#
  )

  private static let genericHomePattern = try! NSRegularExpression(
    pattern: #"(?<![A-Za-z0-9._-])(?:/Users|/home)/[^/\s,;:)'\"]+"#
  )

  private static let ipv4CandidatePattern = try! NSRegularExpression(
    pattern: #"(?<![0-9A-Fa-f:.])(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,3})?(?![0-9A-Fa-f:.])"#
  )

  private static let ipv6CandidatePattern = try! NSRegularExpression(
    pattern:
      #"(?<![0-9A-Fa-f:])[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]+(?:%[A-Za-z0-9._-]+)?(?:/\d{1,3})?(?![0-9A-Fa-f:])"#
  )
}
