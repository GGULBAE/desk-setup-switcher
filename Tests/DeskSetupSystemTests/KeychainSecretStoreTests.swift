import Foundation
import Testing

@testable import DeskSetupSystem

@Suite("Keychain secret store")
struct KeychainSecretStoreTests {
  @Test("new secrets use the fixed namespace and device-only accessibility")
  func savesAndReadsNewSecret() throws {
    let api = MockKeychainAPI()
    let store = KeychainSecretStore(api: api)
    let account = "wifi-profile.synthetic-1"
    let secret = Data([0x10, 0x20, 0x30, 0x40])

    try store.save(secret, account: account)
    let readSecret = try store.read(account: account)
    let invocations = api.recordedInvocations()

    #expect(readSecret == secret)
    #expect(invocations.count == 3)
    guard case .update(let descriptor, let byteCount) = invocations[0] else {
      Issue.record("Expected update to be attempted before add.")
      return
    }
    #expect(descriptor.service == KeychainSecretStore.serviceNamespace)
    #expect(descriptor.account == account)
    #expect(descriptor.accessibility == .afterFirstUnlockThisDeviceOnly)
    #expect(byteCount == secret.count)
    #expect(invocations[1] == .add(descriptor, byteCount: secret.count))
    #expect(invocations[2] == .read(descriptor))
  }

  @Test("an existing secret is updated in place")
  func updatesExistingSecretInPlace() throws {
    let api = MockKeychainAPI()
    let store = KeychainSecretStore(api: api)
    let account = "wifi-profile.synthetic-2"
    try store.save(Data([0x01]), account: account)
    api.resetInvocations()

    let replacement = Data([0x09, 0x08, 0x07])
    try store.save(replacement, account: account)

    #expect(api.recordedInvocations().count == 1)
    #expect(api.storedSecret(account: account) == replacement)
    guard case .update = api.recordedInvocations()[0] else {
      Issue.record("Expected an in-place update without an add.")
      return
    }
  }

  @Test("a duplicate add race retries the update")
  func retriesUpdateAfterDuplicateAdd() throws {
    let api = MockKeychainAPI(simulateDuplicateOnNextAdd: true)
    let store = KeychainSecretStore(api: api)
    let secret = Data([0xAA, 0xBB])

    try store.save(secret, account: "race.synthetic")

    #expect(api.recordedInvocations().map(\.operation) == [.update, .add, .update])
    #expect(api.storedSecret(account: "race.synthetic") == secret)
  }

  @Test("delete is idempotent")
  func deleteIsIdempotent() throws {
    let api = MockKeychainAPI()
    let store = KeychainSecretStore(api: api)
    let account = "delete.synthetic"
    try store.save(Data([0x55]), account: account)

    try store.delete(account: account)
    try store.delete(account: account)

    #expect(try store.read(account: account) == nil)
  }

  @Test("invalid account identifiers fail before calling Keychain")
  func rejectsInvalidAccountIdentifiers() {
    let api = MockKeychainAPI()
    let store = KeychainSecretStore(api: api)

    #expect(throws: KeychainSecretStoreError.invalidAccountIdentifier) {
      try store.save(Data([0x01]), account: "  \n")
    }
    #expect(throws: KeychainSecretStoreError.invalidAccountIdentifier) {
      try store.read(account: String(repeating: "a", count: 1_025))
    }
    #expect(api.recordedInvocations().isEmpty)
  }

  @Test("typed failures never contain secret bytes")
  func errorsDoNotContainSecrets() {
    let api = MockKeychainAPI(forcedUpdateResult: .failure(-50))
    let store = KeychainSecretStore(api: api)
    let secretText = "synthetic-secret-that-must-not-appear"

    do {
      try store.save(Data(secretText.utf8), account: "failure.synthetic")
      Issue.record("Expected a Keychain failure.")
    } catch {
      #expect(
        error as? KeychainSecretStoreError
          == .operationFailed(operation: .update, status: -50)
      )
      #expect(!String(describing: error).contains(secretText))
      #expect(!error.localizedDescription.contains(secretText))
    }
  }

  @Test("unexpected read value is a typed non-secret error")
  func unexpectedReadValueIsTyped() {
    let api = MockKeychainAPI(forcedReadResult: .unexpectedResult)
    let store = KeychainSecretStore(api: api)

    #expect(throws: KeychainSecretStoreError.unexpectedReadResult) {
      try store.read(account: "unexpected.synthetic")
    }
  }
}

private enum MockKeychainOperation: Hashable, Sendable {
  case add
  case update
  case read
  case delete
}

private enum MockKeychainInvocation: Hashable, Sendable {
  case add(KeychainItemDescriptor, byteCount: Int)
  case update(KeychainItemDescriptor, byteCount: Int)
  case read(KeychainItemDescriptor)
  case delete(KeychainItemDescriptor)

  var operation: MockKeychainOperation {
    switch self {
    case .add: .add
    case .update: .update
    case .read: .read
    case .delete: .delete
    }
  }
}

private final class MockKeychainAPI: KeychainAPI, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [KeychainItemDescriptor: Data] = [:]
  private var invocations: [MockKeychainInvocation] = []
  private var simulateDuplicateOnNextAdd: Bool
  private let forcedUpdateResult: KeychainMutationResult?
  private let forcedReadResult: KeychainReadResult?

  init(
    simulateDuplicateOnNextAdd: Bool = false,
    forcedUpdateResult: KeychainMutationResult? = nil,
    forcedReadResult: KeychainReadResult? = nil
  ) {
    self.simulateDuplicateOnNextAdd = simulateDuplicateOnNextAdd
    self.forcedUpdateResult = forcedUpdateResult
    self.forcedReadResult = forcedReadResult
  }

  func add(
    _ descriptor: KeychainItemDescriptor,
    secret: Data
  ) -> KeychainMutationResult {
    lock.withLock {
      invocations.append(.add(descriptor, byteCount: secret.count))
      if simulateDuplicateOnNextAdd {
        simulateDuplicateOnNextAdd = false
        storage[descriptor] = Data([0x00])
        return .duplicateItem
      }
      guard storage[descriptor] == nil else { return .duplicateItem }
      storage[descriptor] = Data(secret)
      return .success
    }
  }

  func update(
    _ descriptor: KeychainItemDescriptor,
    secret: Data
  ) -> KeychainMutationResult {
    lock.withLock {
      invocations.append(.update(descriptor, byteCount: secret.count))
      if let forcedUpdateResult { return forcedUpdateResult }
      guard storage[descriptor] != nil else { return .itemNotFound }
      storage[descriptor] = Data(secret)
      return .success
    }
  }

  func read(_ descriptor: KeychainItemDescriptor) -> KeychainReadResult {
    lock.withLock {
      invocations.append(.read(descriptor))
      if let forcedReadResult { return forcedReadResult }
      return storage[descriptor].map(KeychainReadResult.value) ?? .itemNotFound
    }
  }

  func delete(_ descriptor: KeychainItemDescriptor) -> KeychainMutationResult {
    lock.withLock {
      invocations.append(.delete(descriptor))
      guard storage.removeValue(forKey: descriptor) != nil else {
        return .itemNotFound
      }
      return .success
    }
  }

  func recordedInvocations() -> [MockKeychainInvocation] {
    lock.withLock { invocations }
  }

  func resetInvocations() {
    lock.withLock { invocations.removeAll(keepingCapacity: true) }
  }

  func storedSecret(account: String) -> Data? {
    lock.withLock {
      storage.first { $0.key.account == account }?.value
    }
  }
}
