import Foundation

/// Application-facing secret boundary. Profiles and diagnostic records store only
/// opaque account labels; secret bytes remain behind this protocol.
public protocol SecretStore: Sendable {
  func save(_ secret: Data, account: String) throws
  func read(account: String) throws -> Data?
  func delete(account: String) throws
}

public enum KeychainOperation: String, Hashable, Sendable {
  case add
  case update
  case read
  case delete
}

public enum KeychainSecretStoreError: Error, Equatable, Sendable {
  case invalidAccountIdentifier
  case unexpectedReadResult
  case operationFailed(operation: KeychainOperation, status: Int32)
}

extension KeychainSecretStoreError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidAccountIdentifier:
      "The Keychain account identifier is invalid."
    case .unexpectedReadResult:
      "Keychain returned an unexpected value type."
    case .operationFailed(let operation, let status):
      "Keychain \(operation.rawValue) failed with status \(status)."
    }
  }
}

public struct KeychainSecretStore: SecretStore, Sendable {
  public static let serviceNamespace = "dev.ggulae.desk-setup-switcher.secrets"

  private let api: any KeychainAPI

  public init(api: any KeychainAPI = SecurityKeychainAPI()) {
    self.api = api
  }

  public func save(_ secret: Data, account: String) throws {
    let descriptor = try descriptor(for: account)
    var temporarySecret = copyTemporaryData(secret)
    defer { zeroTemporaryData(&temporarySecret) }

    let updateResult = api.update(descriptor, secret: temporarySecret)
    switch updateResult {
    case .success:
      return
    case .itemNotFound:
      break
    case .duplicateItem, .failure:
      throw failure(for: .update, result: updateResult)
    }

    let addResult = api.add(descriptor, secret: temporarySecret)
    switch addResult {
    case .success:
      return
    case .duplicateItem:
      // Another writer may have inserted the item between update and add.
      let retryResult = api.update(descriptor, secret: temporarySecret)
      guard retryResult == .success else {
        throw failure(for: .update, result: retryResult)
      }
    case .itemNotFound, .failure:
      throw failure(for: .add, result: addResult)
    }
  }

  public func read(account: String) throws -> Data? {
    let descriptor = try descriptor(for: account)
    switch api.read(descriptor) {
    case .value(let secret):
      return secret
    case .itemNotFound:
      return nil
    case .unexpectedResult:
      throw KeychainSecretStoreError.unexpectedReadResult
    case .failure(let status):
      throw KeychainSecretStoreError.operationFailed(
        operation: .read,
        status: status
      )
    }
  }

  public func delete(account: String) throws {
    let descriptor = try descriptor(for: account)
    let result = api.delete(descriptor)
    switch result {
    case .success, .itemNotFound:
      return
    case .duplicateItem, .failure:
      throw failure(for: .delete, result: result)
    }
  }

  private func descriptor(for account: String) throws -> KeychainItemDescriptor {
    guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      account.utf8.count <= 1_024,
      !account.contains("\0")
    else {
      throw KeychainSecretStoreError.invalidAccountIdentifier
    }
    return KeychainItemDescriptor(
      service: Self.serviceNamespace,
      account: account,
      accessibility: .afterFirstUnlockThisDeviceOnly
    )
  }

  private func failure(
    for operation: KeychainOperation,
    result: KeychainMutationResult
  ) -> KeychainSecretStoreError {
    .operationFailed(operation: operation, status: result.statusCode)
  }
}
