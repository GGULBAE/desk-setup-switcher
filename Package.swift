// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "DeskSetupSwitcher",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "DeskSetupCore", targets: ["DeskSetupCore"]),
    .library(name: "DeskSetupSystem", targets: ["DeskSetupSystem"]),
    .executable(name: "DeskSetupSwitcher", targets: ["DeskSetupSwitcher"]),
  ],
  targets: [
    .target(
      name: "DeskSetupCore",
      path: "Sources/DeskSetupCore"
    ),
    .target(
      name: "DeskSetupSystem",
      dependencies: ["DeskSetupCore"],
      path: "Sources/DeskSetupSystem",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("AudioToolbox"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("CoreLocation"),
        .linkedFramework("CoreWLAN"),
        .linkedFramework("IOKit"),
        .linkedFramework("Network"),
        .linkedFramework("Security"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("SystemConfiguration"),
      ]
    ),
    .executableTarget(
      name: "DeskSetupSwitcher",
      dependencies: ["DeskSetupCore", "DeskSetupSystem"],
      path: "Sources/DeskSetupSwitcher",
      resources: [.process("Resources")],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "DeskSetupCoreTests",
      dependencies: ["DeskSetupCore"],
      path: "Tests/DeskSetupCoreTests"
    ),
    .testTarget(
      name: "DeskSetupSystemTests",
      dependencies: ["DeskSetupCore", "DeskSetupSystem"],
      path: "Tests/DeskSetupSystemTests"
    ),
  ]
)
