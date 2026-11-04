// swift-tools-version: 6.4
import PackageDescription

// TerminalKit's time benchmarks (roadmap 0006), on ordo-one's package-benchmark.
//
// A separate package, so the shipping graph never resolves the framework, and it depends on TerminalKit by
// path, so it measures the working tree: the before and after of the change being made. ADR-0016's
// allocation ceilings stay in the test suites; these hold the hot paths to a time.
//
// Run:     cd Benchmarks && swift package benchmark
// Compare: swift package --allow-writing-to-package-directory benchmark baseline update before
//          (make the change) swift package benchmark baseline compare before
// Gate:    swift package benchmark thresholds check   (against Thresholds/, recorded on one machine)
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictMemorySafety"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "benchmarks",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "TerminalKit", path: ".."),
        // Exact, like every other pin in the ecosystem: a benchmark harness that moves under the numbers
        // changes the numbers.
        .package(url: "https://github.com/ordo-one/benchmark", exact: "1.38.0"),
        // For the probe that reads the thread's instructions and counts allocations: the revision TerminalKit itself pins.
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "4879ca7522a6277e9425c69309a801de43b57771"),
        // The parser the probe reads documents with: the revision TerminalKit itself pins.
        .package(url: "https://github.com/g-cqd/AemiMarkdown.git", revision: "9000ebeccef2a1ad1edc15c6c143a0662f8df7de")
    ],
    targets: [
        // The thresholds every suite shares.
        .target(
            name: "BenchmarkSupport",
            dependencies: [.product(name: "Benchmark", package: "benchmark")],
            path: "Sources/BenchmarkSupport",
            swiftSettings: strictSettings
        ),
        .executableTarget(
            name: "InputBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
                "BenchmarkSupport",
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit")
            ],
            path: "Benchmarks/InputBenchmarks",
            swiftSettings: strictSettings,
            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
        ),
        .executableTarget(
            name: "RenderBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
                "BenchmarkSupport",
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit")
            ],
            path: "Benchmarks/RenderBenchmarks",
            swiftSettings: strictSettings,
            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
        ),
        .executableTarget(
            name: "TextBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
                "BenchmarkSupport",
                .product(name: "TerminalKitText", package: "TerminalKit")
            ],
            path: "Benchmarks/TextBenchmarks",
            swiftSettings: strictSettings,
            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
        ),
        // Not a benchmark: drives the real pipeline inside a real terminal for Scripts/verify-scroll-region.sh.
        .executableTarget(
            name: "StreamProbe",
            dependencies: [
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit")
            ],
            path: "Probes/StreamProbe",
            swiftSettings: strictSettings
        ),
        // Not a benchmark: does a running InputSource take a cooperative pool thread (roadmap 0009)?
        .executableTarget(
            name: "InputPoolProbe",
            dependencies: [
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit")
            ],
            path: "Probes/InputPoolProbe",
            swiftSettings: strictSettings
        ),
        // Not a benchmark: UnicodeWidth's answers for the corpus real terminals are asked about (roadmap 0013).
        .executableTarget(
            name: "WidthProbe",
            dependencies: [
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit")
            ],
            path: "Probes/WidthProbe",
            swiftSettings: strictSettings
        ),
        // Not a benchmark: the cost of a Markdown document laid out as rows, by size of document, in CPU time, instructions and allocations (roadmap 0206).
        .executableTarget(
            name: "MarkdownRowsProbe",
            dependencies: [
                .product(name: "TerminalKitMarkdown", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "AemiMetrics", package: "aemi"),
                .product(name: "CAemiTestKitMalloc", package: "aemi")
            ],
            path: "Probes/MarkdownRowsProbe",
            swiftSettings: strictSettings
        ),
        // Not a benchmark: who should own the render pipeline, under load (roadmap 0014).
        .executableTarget(
            name: "IsolationProbe",
            dependencies: [
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit")
            ],
            path: "Probes/IsolationProbe",
            swiftSettings: strictSettings
        )
    ]
)
