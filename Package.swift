// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CatIsNotHelper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CatIsNotHelper",
            path: "Sources/CatIsNotHelper"
        )
    ]
)
