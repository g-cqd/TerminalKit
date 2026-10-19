import Benchmark
import TerminalKitRender

/// `ScreenBuffer.write` over the whole screen: every cell changing, and every cell rewritten unchanged,
/// which a layout that redraws its rows does on every frame.
func registerWriteBenchmarks(_ size: ScreenSize) {
    let (first, second) = (size.first, size.second)
    Benchmark("write/\(size.label) new text, every row") { benchmark in
        var buffer = ScreenBuffer(columns: size.columns, rows: size.rows)
        size.fill(&buffer, with: first)
        buffer.dirty.clear()
        benchmark.startMeasurement()
        size.fill(&buffer, with: second)
        benchmark.stopMeasurement()
        blackHole(buffer.dirty.isEmpty)
    }
    Benchmark("write/\(size.label) identical text, every row") { benchmark in
        var buffer = ScreenBuffer(columns: size.columns, rows: size.rows)
        size.fill(&buffer, with: first)
        buffer.dirty.clear()
        benchmark.startMeasurement()
        size.fill(&buffer, with: first)
        benchmark.stopMeasurement()
        blackHole(buffer.dirty.isEmpty)
    }
}
