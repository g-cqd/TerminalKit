// swift-tools-version: 6.4
import PackageDescription

// TerminalKit — the terminal stack for the Aemi ecosystem, shared by Atelier's KittyCode and `ask`.
//
// This is a package of its own, not a target inside Aemi. Terminal is neither a kernel runtime
// primitive (AemiKernel, AemiText, AemiRuntime) nor an application tier (AemiCore, AemiTesting); it
// is a third concern with its own escape-sequence grammar, its own capability negotiation, and its
// own release cadence. Keeping it separate also keeps its manifest focused: a consumer that wants a
// terminal does not inherit every tier Aemi ships.
//
// Zero external dependencies today. `TerminalKitCore` holds escape sequences and the tiered reset
// ladder, neither of which needs a byte kernel; `TerminalKitTestSupport` holds the oracle terminal
// model. The Aemi dependency arrives with the extraction from Atelier, and only because
// `KittyCodecs` and `KittyInput` genuinely use `AemiKernel` — not before.
//
// The strictest settings a Swift package can carry, matching `ask` and Aemi. Each is justified and
// recorded in docs/WHITE-PAPER.md rather than assumed.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictMemorySafety"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
    .unsafeFlags(["-Xfrontend", "-warn-long-function-bodies=100"]),
    .unsafeFlags(["-Xfrontend", "-warn-long-expression-type-checking=500"])
]

let package = Package(
    name: "TerminalKit",
    platforms: [.macOS(.v26)],
    products: [
        // The escape sequences and the reset ladder. No file descriptor, no termios, no clock.
        .library(name: "TerminalKitCore", targets: ["TerminalKitCore"]),
        // The oracle terminal model, so a consumer can test its own terminal layer the same way.
        .library(name: "TerminalKitTestSupport", targets: ["TerminalKitTestSupport"]),
        .library(name: "TerminalKitIO", targets: ["TerminalKitIO"]),
        .library(name: "TerminalKitText", targets: ["TerminalKitText"]),
        .library(name: "TerminalKitStyle", targets: ["TerminalKitStyle"]),
        // Umbrella — re-exports the core. Test support stays out, so shipping code never links the
        // oracle by accident.
        .library(name: "TerminalKit", targets: ["TerminalKit"])
    ],
    targets: [
        .target(name: "TerminalKitCore", path: "Sources/TerminalKitCore", swiftSettings: strictSettings),
        .target(
            name: "TerminalKitTestSupport",
            path: "Sources/TerminalKitTestSupport",
            swiftSettings: strictSettings),
        // Extracted from Atelier's Apps/KittyCode and Packages/AtelierCore. These three had no
        // sibling-module dependencies at all, which is what made them safe to move first.
        .target(
            name: "TerminalKitStyle",
            path: "Sources/TerminalKitStyle",
            swiftSettings: strictSettings),
        .target(
            name: "TerminalKitIO",
            path: "Sources/TerminalKitIO",
            swiftSettings: strictSettings),
        .target(
            name: "TerminalKitText",
            path: "Sources/TerminalKitText",
            swiftSettings: strictSettings),
        .target(
            name: "TerminalKit",
            dependencies: ["TerminalKitCore"],
            path: "Sources/TerminalKit",
            swiftSettings: strictSettings),
        .testTarget(
            name: "TerminalKitCoreTests",
            dependencies: ["TerminalKitCore", "TerminalKitTestSupport"],
            path: "Tests/TerminalKitCoreTests",
            swiftSettings: strictSettings)
    ]
)
