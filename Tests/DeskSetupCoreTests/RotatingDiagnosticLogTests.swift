import Foundation
import XCTest

@testable import DeskSetupCore

final class RotatingDiagnosticLogTests: XCTestCase {
  private struct FixedClock: DiagnosticLogClock {
    let date: Date

    func now() -> Date {
      date
    }
  }

  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RotatingDiagnosticLogTests-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory,
      FileManager.default.fileExists(atPath: temporaryDirectory.path)
    {
      try FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  func testRedactsBeforePersistingJSONLine() async throws {
    let store = try makeStore(maximumFileSizeBytes: 4_096)
    let entry = makeEntry(
      index: 1,
      message: "password=never-write-this home=/Users/example/Desktop ip=192.168.50.99"
    )

    try await store.append(entry)

    let fileURL = temporaryDirectory.appendingPathComponent("diagnostics.jsonl")
    let raw = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertFalse(raw.contains("never-write-this"))
    XCTAssertFalse(raw.contains("/Users/example"))
    XCTAssertFalse(raw.contains("192.168.50.99"))
    XCTAssertTrue(raw.contains("<redacted>"))
    XCTAssertTrue(raw.contains("<home>/Desktop"))
    XCTAssertTrue(raw.contains("192.168.50.0/24"))
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    XCTAssertEqual(permissions & 0o777, 0o600)

    let persisted = try await store.entries()
    XCTAssertEqual(persisted.count, 1)
    XCTAssertEqual(persisted[0].id, entry.id)
  }

  func testRotatesBySizeAndPrunesOldestFilesToCountLimit() async throws {
    let sampleLineSize = try encodedLineSize(
      makeEntry(index: 0, message: String(repeating: "x", count: 80)))
    let store = try makeStore(
      maximumFileSizeBytes: sampleLineSize + 8,
      maximumFileCount: 3
    )

    for index in 0..<6 {
      try await store.append(
        makeEntry(
          index: index,
          message: String(repeating: Character(String(index)), count: 80)
        ))
    }

    let files = try managedFiles()
    XCTAssertEqual(files.count, 3)
    for file in files {
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      let size = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
      XCTAssertLessThanOrEqual(size, sampleLineSize + 8)
    }

    let entries = try await store.entries()
    XCTAssertEqual(entries.map(\.code), ["event.3", "event.4", "event.5"])
    XCTAssertTrue(
      files.contains { $0.lastPathComponent == "diagnostics-0000001000000-000005.jsonl" })
  }

  func testRejectsEntryLargerThanMaximumWithoutCreatingLog() async throws {
    let store = try makeStore(maximumFileSizeBytes: 32)

    do {
      try await store.append(makeEntry(index: 1, message: String(repeating: "x", count: 1_000)))
      XCTFail("Expected an oversized-entry error")
    } catch let error as RotatingDiagnosticLogError {
      guard case .entryTooLarge(let actualBytes, let maximumBytes) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertGreaterThan(actualBytes, maximumBytes)
      XCTAssertEqual(maximumBytes, 32)
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.path))
  }

  func testConcurrentAppendsAreSerializedAsCompleteJSONLines() async throws {
    let store = try makeStore(maximumFileSizeBytes: 128 * 1_024)
    let entriesToAppend = (0..<40).map {
      makeEntry(index: $0, message: "synthetic")
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for entry in entriesToAppend {
        group.addTask {
          try await store.append(entry)
        }
      }
      try await group.waitForAll()
    }

    let entries = try await store.entries()
    XCTAssertEqual(entries.count, 40)
    XCTAssertEqual(Set(entries.map(\.code)).count, 40)

    let raw = try Data(contentsOf: temporaryDirectory.appendingPathComponent("diagnostics.jsonl"))
    XCTAssertEqual(raw.filter { $0 == 0x0A }.count, 40)
  }

  func testRemoveAllLeavesUnmanagedFilesAlone() async throws {
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    let unrelated = temporaryDirectory.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: unrelated)
    let store = try makeStore(maximumFileSizeBytes: 4_096)
    try await store.append(makeEntry(index: 1, message: "synthetic"))

    try await store.removeAll()

    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    XCTAssertEqual(try managedFiles(), [])
  }

  private func makeStore(
    maximumFileSizeBytes: Int,
    maximumFileCount: Int = 4
  ) throws -> RotatingDiagnosticLogStore {
    try RotatingDiagnosticLogStore(
      directoryURL: temporaryDirectory,
      maximumFileSizeBytes: maximumFileSizeBytes,
      maximumFileCount: maximumFileCount,
      redactor: SensitiveDataRedactor(
        homeDirectory: URL(fileURLWithPath: "/Users/example", isDirectory: true)
      ),
      clock: FixedClock(date: Date(timeIntervalSince1970: 1_000))
    )
  }

  private func makeEntry(index: Int, message: String) -> DiagnosticEntry {
    DiagnosticEntry(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
      timestamp: Date(timeIntervalSince1970: TimeInterval(2_000 + index)),
      severity: .info,
      component: "synthetic",
      code: "event.\(index)",
      message: message
    )
  }

  private func encodedLineSize(_ entry: DiagnosticEntry) throws -> Int {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(entry).count + 1
  }

  private func managedFiles() throws -> [URL] {
    guard FileManager.default.fileExists(atPath: temporaryDirectory.path) else {
      return []
    }
    return try FileManager.default.contentsOfDirectory(
      at: temporaryDirectory,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "jsonl" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}
