// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeepMeAlive",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KeepMeAlive",
            path: "Sources/KeepMeAlive",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Network"),
            ]
        ),
    ]
)
