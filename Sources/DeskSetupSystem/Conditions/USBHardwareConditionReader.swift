import CryptoKit
import Foundation
import IOKit

public enum USBHardwareConditionReaderError: Error, Hashable, Sendable {
  case registryUnavailable
}

/// Enumerates the public `IOUSBHostDevice` registry plane without opening a
/// device or vendor interface. Serial strings are hashed before leaving this reader.
public struct LiveUSBHardwareConditionReader: ConditionHardwareReading {
  public init() {}

  public func readHardwareIdentifiers() async throws -> Set<String> {
    guard let matching = IOServiceMatching("IOUSBHostDevice") else {
      throw USBHardwareConditionReaderError.registryUnavailable
    }

    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
    else {
      throw USBHardwareConditionReaderError.registryUnavailable
    }
    defer { IOObjectRelease(iterator) }

    var identifiers: Set<String> = []
    while true {
      let service = IOIteratorNext(iterator)
      guard service != 0 else { break }
      defer { IOObjectRelease(service) }

      var unmanagedProperties: Unmanaged<CFMutableDictionary>?
      guard
        IORegistryEntryCreateCFProperties(
          service,
          &unmanagedProperties,
          kCFAllocatorDefault,
          0
        ) == KERN_SUCCESS,
        let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any],
        let identifier = USBHardwareIdentifier.make(from: properties)
      else {
        continue
      }
      identifiers.insert(identifier)
    }

    return identifiers
  }
}

enum USBHardwareIdentifier {
  static func make(from properties: [String: Any]) -> String? {
    guard let vendorID = uint16(properties["idVendor"]), vendorID != 0,
      let productID = uint16(properties["idProduct"]), productID != 0
    else {
      return nil
    }

    let prefix = "usb:\(hex(vendorID)):\(hex(productID))"
    if let serial = nonemptyString(properties["USB Serial Number"])
      ?? nonemptyString(properties["kUSBSerialNumberString"])
    {
      return "\(prefix):serial-sha256:\(digest(serial))"
    }

    if let container = nonemptyString(properties["kUSBContainerID"]),
      let uuid = UUID(uuidString: container)
    {
      return "\(prefix):container:\(uuid.uuidString.lowercased())"
    }

    // Vendor/product is less specific but remains stable and is still useful
    // for hardware-presence conditions when no stable public instance key exists.
    // `locationID` is deliberately ignored because it identifies a USB topology
    // path and changes when the same device is moved to another port.
    return prefix
  }

  private static func nonemptyString(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func uint16(_ value: Any?) -> UInt16? {
    guard let number = value as? NSNumber else { return nil }
    return UInt16(exactly: number.uint64Value)
  }

  private static func hex(_ value: UInt16) -> String {
    String(format: "%04x", value)
  }

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
