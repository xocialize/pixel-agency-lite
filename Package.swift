// swift-tools-version: 6.2
import PackageDescription

// Pixel Agency Lite's run workflow, as an open package (Lite-PRD LITE-16): Lite is a thin app around it, and Pixel
// Agency Desktop embeds the same package, so both reach engines the same way (D-8).
//
//   PixelAgencyRun     the model: engines (discovery, pairing, credentials), a run (inputs, controls from the
//                      descriptor, progress, results, provenance), the session list, the working folder, masks.
//   PixelAgencyRunUI   the SwiftUI views of the workflow, on MESFormsUI and DesignScaffold.
//   lite-run           the same run workflow without a window, for the MES client conformance suite.
let package = Package(
    name: "PixelAgencyLite",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PixelAgencyRun", targets: ["PixelAgencyRun"]),
        .library(name: "PixelAgencyRunUI", targets: ["PixelAgencyRunUI"]),
        .executable(name: "lite-run", targets: ["LiteRun"]),
    ],
    dependencies: [
        // The Media Engine Specification SDKs.
        .package(url: "https://github.com/xocialize/media-engine-spec.git", from: "0.1.0"),
        .package(url: "https://github.com/xocialize/DesignScaffold.git", from: "0.25.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "PixelAgencyRun", dependencies: [
            .product(name: "MESClientKit", package: "media-engine-spec"),
            .product(name: "MESCore", package: "media-engine-spec"),
            .product(name: "MESFormsUI", package: "media-engine-spec"),
        ]),
        .target(name: "PixelAgencyRunUI", dependencies: [
            "PixelAgencyRun",
            .product(name: "MESClientKit", package: "media-engine-spec"),
            .product(name: "MESFormsUI", package: "media-engine-spec"),
            .product(name: "DesignScaffold", package: "DesignScaffold"),
            .product(name: "DesignScaffoldControls", package: "DesignScaffold"),
            .product(name: "DesignScaffoldMedia", package: "DesignScaffold"),
            .product(name: "DesignScaffoldStatus", package: "DesignScaffold"),
            .product(name: "DesignScaffoldWorkspace", package: "DesignScaffold"),
        ]),
        .executableTarget(name: "LiteRun", dependencies: [
            "PixelAgencyRun", .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "PixelAgencyRunTests", dependencies: [
            "PixelAgencyRun",
            .product(name: "MESEngineKit", package: "media-engine-spec"),
            .product(name: "MockEngineCore", package: "media-engine-spec"),
            .product(name: "MESConformance", package: "media-engine-spec"),
        ]),
    ]
)
