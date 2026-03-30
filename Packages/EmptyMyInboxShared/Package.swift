// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EmptyMyInboxShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "EmptyMyInboxShared",
            targets: ["EmptyMyInboxShared"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", exact: "9.0.0")
    ],
    targets: [
        .target(
            name: "EmptyMyInboxShared",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GoogleSignInSwift", package: "GoogleSignIn-iOS")
            ],
            path: "Sources/EmptyMyInboxShared"
        ),
        .testTarget(
            name: "EmptyMyInboxSharedTests",
            dependencies: ["EmptyMyInboxShared"],
            path: "Tests/EmptyMyInboxSharedTests"
        )
    ]
)
