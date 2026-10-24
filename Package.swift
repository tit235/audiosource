// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "audiosource",
  platforms: [
    .macOS(.v12)
  ],
  products: [
    .executable(name: "audiosource", targets: ["audiosource"])
  ],
  targets: [
    .executableTarget(
      name: "audiosource"
    )
  ]
)
