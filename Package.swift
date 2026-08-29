// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftSurvivor",
    platforms: [.custom("windows", versionString: "10")],
    products: [
        .executable(name: "SwiftSurvivor", targets: ["SwiftSurvivor"])
    ],
    targets: [
        // Thin Clang module over the vendored SDL3 headers. Keeping this as a
        // separate target prevents SDL's C API from leaking through gameplay.
        .target(
            name: "CSwiftSDL3",
            path: "Sources/CSwiftSDL3",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../Vendor/SDL3-3.4.14/include")
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "Vendor/SDL3-3.4.14/lib/x64"]),
                .linkedLibrary("SDL3")
            ]
        ),
        .executableTarget(
            name: "SwiftSurvivor",
            dependencies: ["CSwiftSDL3"],
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
