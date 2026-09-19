
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "isa",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "isa", targets: ["isa"])
    ],
    targets: [
        .executableTarget(
            name: "isa",
            path: "Sources"
        )
    ]
)
