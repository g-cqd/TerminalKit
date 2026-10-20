import Benchmark
import BenchmarkSupport
import TerminalKitText

// `TextWrap.lines` over three bodies a transcript holds, at two widths. Each sample wraps the whole body once;
// the body is about 4 KB, so the per-byte cost is the time divided by 4,096.
private let prose = String(
    String(
        repeating:
            "The quick brown fox jumps over the lazy dog, and then reads a long answer that wraps at spaces. ",
        count: 60
    )
    .prefix(4_096))
private let code = String(
    String(repeating: "    let result = try await session.run(arguments: [\"--flag\", value]) // comment\n", count: 60)
        .prefix(4_096))
private let cjk = String(String(repeating: "日本語のテキストは二列で表示されます。English words too. ", count: 60).prefix(1_400))

func registerWrapBenchmarks() {
    // One wrap per sample, reported as it is: not scaled like the per-grapheme suites.
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal], scalingFactor: .one, maxDuration: .seconds(1),
        maxIterations: 1_000, thresholds: Thresholds.perSuite)
    let bodies: [(name: String, text: String)] = [("prose", prose), ("code", code), ("CJK", cjk)]
    for (name, text) in bodies {
        for width in [80, 120] {
            Benchmark("wrap/\(name) at \(width)", configuration: configuration) { benchmark in
                benchmark.startMeasurement()
                blackHole(TextWrap.lines(text, width: width))
                benchmark.stopMeasurement()
            }
            // The same wrap with each row's hard line and grapheme offset, which a selection needs (roadmap 0017).
            Benchmark("wrap rows/\(name) at \(width)", configuration: configuration) { benchmark in
                benchmark.startMeasurement()
                blackHole(TextWrap.rows(text, width: width))
                benchmark.stopMeasurement()
            }
        }
    }
}
