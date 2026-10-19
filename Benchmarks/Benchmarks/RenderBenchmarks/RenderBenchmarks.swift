import Benchmark
import BenchmarkSupport
import TerminalKitIO
import TerminalKitRender

// The frame path at three window sizes: writing cells into the back buffer, flushing a frame through the
// real `RenderPipeline` over a mock connection, and a forced redraw.
//
// Each sample builds its own buffers and warms them before the measurement starts, then times one
// operation, so the percentiles are per frame rather than averages over many frames.
let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .mallocCountTotal],
        maxDuration: .seconds(1),
        maxIterations: 1_000,
        thresholds: Thresholds.perSuite
    )

    for size in ScreenSize.all {
        registerWriteBenchmarks(size)
        registerFlushBenchmarks(size)
    }
}
