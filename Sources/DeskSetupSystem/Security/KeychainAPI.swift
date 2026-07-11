import Foundation
import Security

public enum KeychainAccessibility: Hashable, Sendable {
  /// Available after the user first unlocks the Mac, never migrates to another device,
  /// and remains suitable for a login-item app after the login unlock.
  case afterFirstUnlockThisDeviceOnly
}

/// Keychain lookup metadata only. Account identifiers must be opaque, non-secret labels.
/// This type deliberately does not conform to `Codable`.
public struct KeychainItemDescriptor: Hashable, Sendable {
  public var service: String
  public var account: String
  public var accessibility: KeychainAccessibility

  public init(
    service: String,
    account: String,
    accessibility: KeychainAccessibility
  ) {
    self.service = service
    self.account = account
    self.accessibility = accessibility
  }
}

public enum KeychainMutationResult: Equatable, Sendable {
  case success
  case itemNotFound
  case duplicateItem
  case failure(Int32)

  public var statusCode: Int32 {
    switch self {
    case .success: errSecSuccess
    case .itemNotFound: errSecItemNotFound
    case .duplicateItem: errSecDuplicateItem
    case .failure(let status): status
    }
  }
}

public enum KeychainReadResult: Equatable, Sendable {
  case value(Data)
  case itemNotFound
  case unexpectedResult
  case failure(Int32)
}

public protocol KeychainAPI: Sendable {
  func add(_ descriptor: KeychainItemDescriptor, secret: Data) -> KeychainMutationResult
  func update(_ descriptor: KeychainItemDescriptor, secret: Data) -> KeychainMutationResult
  func read(_ descriptor: KeychainItemDescriptor) -> KeychainReadResult
  func delete(_ descriptor: KeychainItemDescriptor) -> KeychainMutationResult
}

func zeroTemporaryData(_ data: inout Data) {
  guard !data.isEmpty else { return }
  data.resetBytes(in: data.startIndex..<data.endIndex)
  data.removeAll(keepingCapacity: false)
}

func copyTemporaryData(_ data: Data) -> Data {
  data.withUnsafeBytes { Data($0) }
}
