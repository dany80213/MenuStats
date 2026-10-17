// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MenuStats",
    platforms: [.macOS(.v13)],
    targets: [
        // Private IOKit HID (temperatures), SMC read/write and the macOS charge limit (PowerUI).
        .target(
            name: "CIOKitPrivate",
            path: "Sources/CIOKitPrivate",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Foundation")]
        ),
        // XPC interface shared by the app and its privileged helper.
        .target(name: "MenuStatsShared", path: "Sources/MenuStatsShared"),
        .executableTarget(
            name: "MenuStats",
            dependencies: ["CIOKitPrivate", "MenuStatsShared"],
            path: "Sources/MenuStats",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreLocation"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        // LaunchDaemon (root) that writes the fan keys; installed from the app with SMAppService.
        .executableTarget(
            name: "MenuStatsHelper",
            dependencies: ["CIOKitPrivate", "MenuStatsShared"],
            path: "Sources/MenuStatsHelper",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Security")]
        ),
    ]
)
