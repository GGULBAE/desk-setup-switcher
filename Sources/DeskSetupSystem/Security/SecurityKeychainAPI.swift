import Foundation
import Security

public struct SecurityKeychainAPI: KeychainAPI {
  public init() {}

  public func add(
    _ descriptor: KeychainItemDescriptor,
    secret: Data
  ) -> KeychainMutationResult {
    var temporarySecret = copyTemporaryData(secret)
    var query = baseQuery(for: descriptor)
    query[kSecAttrAccessible as String] = accessibilityValue(descriptor.accessibility)
    query[kSecValueData as String] = temporarySecret
    defer {
      query[kSecValueData as String] = Data()
      zeroTemporaryData(&temporarySecret)
    }

    return mutationResult(
      for: SecItemAdd(query as CFDictionary, nil)
    )
  }

  public func update(
    _ descriptor: KeychainItemDescriptor,
    secret: Data
  ) -> KeychainMutationResult {
    var temporarySecret = copyTemporaryData(secret)
    var attributes: [String: Any] = [
      kSecAttrAccessible as String: accessibilityValue(descriptor.accessibility),
      kSecValueData as String: temporarySecret,
    ]
    defer {
      attributes[kSecValueData as String] = Data()
      zeroTemporaryData(&temporarySecret)
    }

    return mutationResult(
      for: SecItemUpdate(
        baseQuery(for: descriptor) as CFDictionary,
        attributes as CFDictionary
      )
    )
  }

  public func read(_ descriptor: KeychainItemDescriptor) -> KeychainReadResult {
    var query = baseQuery(for: descriptor)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else {
        return .unexpectedResult
      }
      return .value(data)
    case errSecItemNotFound:
      return .itemNotFound
    default:
      return .failure(status)
    }
  }

  public func delete(_ descriptor: KeychainItemDescriptor) -> KeychainMutationResult {
    mutationResult(
      for: SecItemDelete(baseQuery(for: descriptor) as CFDictionary)
    )
  }

  private func baseQuery(for descriptor: KeychainItemDescriptor) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: descriptor.service,
      kSecAttrAccount as String: descriptor.account,
    ]
  }

  private func accessibilityValue(_ accessibility: KeychainAccessibility) -> CFString {
    switch accessibility {
    case .afterFirstUnlockThisDeviceOnly:
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    }
  }

  private func mutationResult(for status: OSStatus) -> KeychainMutationResult {
    switch status {
    case errSecSuccess: .success
    case errSecItemNotFound: .itemNotFound
    case errSecDuplicateItem: .duplicateItem
    default: .failure(status)
    }
  }
}
