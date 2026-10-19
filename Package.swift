// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Jeeves",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Jeeves", path: "Sources/Jeeves")
    ]
)
