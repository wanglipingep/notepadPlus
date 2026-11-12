// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NotepadPlusCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "NotepadPlusCore", targets: ["NotepadPlusCore"])
    ],
    targets: [
        .target(
            name: "NotepadPlusCore",
            path: "NotepadPlus/SharedCore"
        ),
        .testTarget(
            name: "NotepadPlusCoreTests",
            dependencies: ["NotepadPlusCore"],
            path: "Tests",
            exclude: ["WorkspaceIntegration", "PreviewIntegration"]
        )
    ]
)
