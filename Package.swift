// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SkyVaultForGoogle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SkyVaultForGoogle", targets: ["GoogleDriveClone"])
    ],
    targets: [
        .executableTarget(
            name: "GoogleDriveClone",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
