// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommonStats",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "StatKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .executableTarget(
            name: "StatBar",
            dependencies: ["StatKit"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .testTarget(name: "StatKitTests", dependencies: ["StatKit"]),
    ]
)
