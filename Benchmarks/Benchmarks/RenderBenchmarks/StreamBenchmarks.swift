import Benchmark
import TerminalKitIO
import TerminalKitRender
import TerminalKitStyle

/// A bottom-aligned transcript taking a streamed line (roadmap 0011): every transcript row is rewritten one
/// line further on, and the last row is a status line that stays. Timed as the layout's writes plus the flush,
/// with and without the transcript declared as a scroll region. The bytes each frame writes are a metric of
/// their own, held exactly: they do not vary between runs.
/// Bytes written for one frame.
private let frameBytes = BenchmarkMetric.custom("Frame bytes", polarity: .prefersSmaller, useScalingFactor: false)

func registerStreamBenchmarks(_ size: ScreenSize) {
    let transcriptRows = size.rows - 1
    // ask's own benchmark transcript: lines of words that differ in their number, at the end.
    let lines = (0 ..< transcriptRows + 64).map { String(repeating: "word ", count: size.columns / 6) + "\($0)" }
    for detects in [false, true] {
        let name = "stream/\(size.label) one line" + (detects ? ", scroll region" : "")
        var configuration = Benchmark.defaultConfiguration
        configuration.metrics.append(frameBytes)
        configuration.thresholds?[frameBytes] = .init(absolute: [.p25: 0, .p50: 0, .p90: 0])
        Benchmark(name, configuration: configuration) { @MainActor benchmark async in
            let (pipeline, connection) = streamingPipeline(size, detects: detects)
            for first in 0 ..< 16 { streamFrame(pipeline, lines: lines, first: first, rows: transcriptRows) }
            benchmark.startMeasurement()
            streamFrame(pipeline, lines: lines, first: 16, rows: transcriptRows)
            benchmark.stopMeasurement()
            benchmark.measurement(frameBytes, connection.lastWriteBytes)
        }
    }
}

@MainActor private func streamingPipeline(_ size: ScreenSize, detects: Bool) -> (RenderPipeline, DiscardingConnection) {
    let connection = DiscardingConnection(size: TerminalSize(columns: size.columns, rows: size.rows))
    let pipeline = RenderPipeline(connection: connection, columns: size.columns, rows: size.rows)
    if detects { pipeline.scrollRegion = 0 ..< size.rows - 1 }
    pipeline.buffer.write("status", row: size.rows - 1, col: 0, style: Style(inverse: true))
    try? pipeline.forceRedraw()
    return (pipeline, connection)
}

@MainActor private func streamFrame(_ pipeline: RenderPipeline, lines: [String], first: Int, rows: Int) {
    pipeline.beginFrame()
    for row in 0 ..< rows { pipeline.buffer.write(lines[first + row], row: row, col: 0, style: .default) }
    try? pipeline.flush()
}
