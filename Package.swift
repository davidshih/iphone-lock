// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "BrickCore",
  platforms: [
    .iOS(.v17),
    .macOS(.v14)
  ],
  products: [
    .library(name: "BrickCore", targets: ["BrickCore"])
  ],
  targets: [
    .target(name: "BrickCore", path: "BrickCore"),
    .testTarget(
      name: "BrickCoreTests",
      dependencies: ["BrickCore"],
      path: "BrickCoreTests"
    )
  ]
)
