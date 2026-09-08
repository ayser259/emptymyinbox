// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProjectJadeShared",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "ProjectJadeShared",
            targets: ["ProjectJadeShared"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", exact: "9.2.0")
    ],
    targets: [
        .target(
            name: "ProjectJadeShared",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GoogleSignInSwift", package: "GoogleSignIn-iOS")
            ],
            path: "Sources/ProjectJadeShared",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ProjectJadeSharedTests",
            dependencies: ["ProjectJadeShared"],
            path: "Tests/ProjectJadeSharedTests"
        )
    ]
)
