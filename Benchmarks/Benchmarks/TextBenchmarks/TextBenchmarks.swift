import Benchmark
import BenchmarkSupport
import TerminalKitText

// `UnicodeWidth` per grapheme, over three corpora: ASCII, CJK, and emoji sequences (ZWJ families,
// skin tones, flags, VS16). Each sample walks 1,000 graphemes; the kilo scaling factor reports one.
private let graphemesPerSample = 1_000

private func corpus(_ graphemes: [Character]) -> [Character] {
    (0 ..< graphemesPerSample).map { graphemes[$0 % graphemes.count] }
}

private let corpora: [(name: String, graphemes: [Character])] = [
    ("ASCII", corpus(Array("The quick brown fox jumps over the lazy dog, 0123456789."))),
    ("CJK", corpus(Array("漢字仮名交じり文한국어中文字符全角ＡＢＣ"))),
    ("emoji", corpus(["😀", "👍🏽", "👨‍👩‍👧", "🇫🇷", "❤️", "🏳️‍🌈", "✅", "🧑‍💻"]))
]

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .mallocCountTotal],
        scalingFactor: .kilo,
        maxDuration: .seconds(1),
        maxIterations: 1_000,
        thresholds: Thresholds.perSuite
    )

    registerWrapBenchmarks()
    registerSelectionBenchmarks()
    registerInputBenchmarks()
    for (name, graphemes) in corpora {
        Benchmark("width/\(name)") { benchmark in
            benchmark.startMeasurement()
            var columns = 0
            for grapheme in graphemes { columns &+= UnicodeWidth.displayWidth(of: grapheme) }
            benchmark.stopMeasurement()
            blackHole(columns)
        }
    }
}
