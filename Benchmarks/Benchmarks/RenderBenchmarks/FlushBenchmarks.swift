import Benchmark
import TerminalKitIO
import TerminalKitRender
import TerminalKitStyle

/// Frames warmed before each measurement, so the output buffer and the caches are in their steady state.
private let warmFrames = 16

/// One frame of each shape the roadmap names: one cell, one row, every cell, and a forced redraw.
///
/// `RenderPipeline` is main-actor isolated, so these closures are `@MainActor` and asynchronous: the
/// framework hops to the main actor to run them, and the measurement covers only the synchronous work
/// between `startMeasurement()` and `stopMeasurement()`.
func registerFlushBenchmarks(_ size: ScreenSize) {
    let (first, second) = (size.first, size.second)
    let lastRow = size.rows - 1

    Benchmark("flush/\(size.label) one cell") { @MainActor benchmark async in
        let pipeline = warmedPipeline(size, first)
        for frame in 0 ..< warmFrames { oneCell(pipeline, frame, row: lastRow) }
        benchmark.startMeasurement()
        oneCell(pipeline, warmFrames, row: lastRow)
        benchmark.stopMeasurement()
    }
    Benchmark("flush/\(size.label) one row") { @MainActor benchmark async in
        let pipeline = warmedPipeline(size, first)
        for frame in 0 ..< warmFrames { oneRow(pipeline, frame, lines: (first, second), row: lastRow) }
        benchmark.startMeasurement()
        oneRow(pipeline, warmFrames, lines: (first, second), row: lastRow)
        benchmark.stopMeasurement()
    }
    Benchmark("flush/\(size.label) every cell") { @MainActor benchmark async in
        let pipeline = warmedPipeline(size, first)
        for frame in 0 ..< warmFrames { everyCell(pipeline, frame, size: size) }
        benchmark.startMeasurement()
        everyCell(pipeline, warmFrames, size: size)
        benchmark.stopMeasurement()
    }
    Benchmark("forceRedraw/\(size.label)") { @MainActor benchmark async in
        let pipeline = warmedPipeline(size, first)
        for _ in 0 ..< warmFrames { try? pipeline.forceRedraw() }
        benchmark.startMeasurement()
        try? pipeline.forceRedraw()
        benchmark.stopMeasurement()
    }
}

@MainActor private func warmedPipeline(_ size: ScreenSize, _ line: String) -> RenderPipeline {
    let pipeline = RenderPipeline(
        connection: DiscardingConnection(size: TerminalSize(columns: size.columns, rows: size.rows)),
        columns: size.columns, rows: size.rows)
    size.fill(&pipeline.buffer, with: line)
    try? pipeline.forceRedraw()
    return pipeline
}

@MainActor private func oneCell(_ pipeline: RenderPipeline, _ frame: Int, row: Int) {
    pipeline.beginFrame()
    pipeline.buffer.write(frame.isMultiple(of: 2) ? "x" : "y", row: row, col: 5, style: .default)
    try? pipeline.flush()
}

@MainActor private func oneRow(_ pipeline: RenderPipeline, _ frame: Int, lines: (String, String), row: Int) {
    pipeline.beginFrame()
    pipeline.buffer.write(frame.isMultiple(of: 2) ? lines.1 : lines.0, row: row, col: 0, style: .default)
    try? pipeline.flush()
}

@MainActor private func everyCell(_ pipeline: RenderPipeline, _ frame: Int, size: ScreenSize) {
    pipeline.beginFrame()
    size.fill(&pipeline.buffer, with: frame.isMultiple(of: 2) ? size.second : size.first)
    try? pipeline.flush()
}
