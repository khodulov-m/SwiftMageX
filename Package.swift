// swift-tools-version: 6.0
// SwiftMageX — image generation and processing CLI.
// macOS-only MVP 0.1. See SwiftMageX-MVP-0.1-spec for the full specification.
//
// Tools version 6.0 enables the Swift 6 language mode (strict concurrency)
// by default, which the Kit's Sendable types rely on.

import PackageDescription

let package = Package(
    name: "SwiftMageX",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Core library — shared by both frontends.
        .library(name: "SwiftMageXKit", targets: ["SwiftMageXKit"]),
        // CLI frontend.
        .executable(name: "swiftmagex", targets: ["swiftmagex"]),
        // MCP server frontend.
        .executable(name: "swiftmagex-mcp", targets: ["swiftmagex-mcp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.5.0"
        ),
        // MCP Swift SDK — the official, actively maintained SDK
        // (latest 0.12.1, May 2026; targets MCP spec 2025-11-25).
        // Still pre-1.0, and per the project's policy a 0.x minor bump may
        // include breaking changes — so the range is pinned to the current
        // minor (patch updates only). Bump deliberately when adopting 0.13+.
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            .upToNextMinor(from: "0.12.1")
        ),
    ],
    targets: [
        // MARK: - Core

        // Pure orchestration logic. No external dependencies — networking is
        // URLSession, raster work is CoreImage / ImageIO / CoreText. Bundles
        // CC0 device-frame artwork (Resources/Frames/) used by `appstore`.
        .target(
            name: "SwiftMageXKit",
            resources: [
                .copy("Resources/Frames")
            ]
        ),

        // MARK: - Frontends

        // Both frontends are thin wrappers over SwiftMageXKit and share no
        // dependency with each other.
        .executableTarget(
            name: "swiftmagex",
            dependencies: [
                "SwiftMageXKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "swiftmagex-mcp",
            dependencies: [
                "SwiftMageXKit",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),

        // MARK: - Tests

        .testTarget(
            name: "SwiftMageXKitTests",
            dependencies: ["SwiftMageXKit"]
        ),

        // Tests for the MCP server's tool dispatch layer. Drives each tool
        // handler in-process; does not boot a transport.
        .testTarget(
            name: "swiftmagexMCPTests",
            dependencies: [
                "swiftmagex-mcp",
                "SwiftMageXKit",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),

        // Tests for the CLI frontend's argument-parsing and validation layer.
        // Run-time behavior is exercised by SwiftMageXKitTests through the
        // shared orchestrator; this target covers the ArgumentParser surface.
        .testTarget(
            name: "swiftmagexTests",
            dependencies: [
                "swiftmagex",
                "SwiftMageXKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
