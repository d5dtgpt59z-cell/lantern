// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Lantern", platforms: [.macOS(.v15)], products: [.executable(name: "Lantern", targets: ["Lantern"])], targets: [.executableTarget(name: "Lantern", path: "Sources")], swiftLanguageModes: [.v5])
