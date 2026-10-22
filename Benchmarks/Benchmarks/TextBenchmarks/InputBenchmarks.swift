import Benchmark
import BenchmarkSupport
import TerminalKitText

func registerInputBenchmarks() {
    let once = Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal], scalingFactor: .one, maxDuration: .seconds(1),
        maxIterations: 1_000, thresholds: Thresholds.perSuite)
    let repeated = Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal], scalingFactor: .kilo, maxDuration: .seconds(1),
        maxIterations: 1_000, thresholds: Thresholds.perSuite)
    for (name, text) in [
        ("ASCII 6K", (0 ..< 100).map { _ in String(repeating: "word ", count: 12) }.joined(separator: "\n")),
        ("wide", String(repeating: "日本語 e\u{301} 👨‍👩‍👧 words\n", count: 100))
    ] {
        let sourceCount = text.count
        let layout = InputLayout(text, columns: 80, firstRowIndent: 5)
        Benchmark("input/layout \(name)", configuration: once) { benchmark in
            benchmark.startMeasurement()
            blackHole(InputLayout(text, columns: 80, firstRowIndent: 5))
            benchmark.stopMeasurement()
        }
        Benchmark("input/map \(name)", configuration: repeated) { benchmark in
            var sum = 0
            benchmark.startMeasurement()
            for index in 0 ..< 1_000 {
                let position = layout.position(at: index % sourceCount)
                sum &+= layout.offset(atRow: position.row, column: position.column)
            }
            benchmark.stopMeasurement()
            blackHole(sum)
        }
        Benchmark("input/viewport \(name)", configuration: repeated) { benchmark in
            var sum = 0
            benchmark.startMeasurement()
            for index in 0 ..< 1_000 {
                let view = InputViewport(layout: layout, cursorOffset: index % sourceCount, maximumRows: 6, firstRow: 7)
                sum &+= view.rowsAbove
            }
            benchmark.stopMeasurement()
            blackHole(sum)
        }
    }
}
