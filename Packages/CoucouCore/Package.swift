// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CoucouCore",
  platforms: [.macOS("26.0")],
  products: [.library(name: "CoucouCore", targets: ["CoucouCore"])],
  dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7")],
  targets: [
    .target(
      name: "CoucouCore",
      dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
      path: "Sources/CoucouCore",
      swiftSettings: [.swiftLanguageMode(.v6)]
    )
  ]
)
