// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftSurvivor",
    platforms: [.custom("windows", versionString: "10")],
    products: [
        .executable(name: "SwiftSurvivor", targets: ["SwiftSurvivor"])
    ],
    targets: [
        .executableTarget(
            name: "SwiftSurvivor",
            linkerSettings: [
                .linkedLibrary("winmm"),
                // Link as a GUI application so Windows does not create an
                // extra console window next to the game. Keep Swift's normal
                // main entry point explicitly selected for the Windows CRT.
                .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"])
            ]
        )
    ]
)
