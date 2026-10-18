internal import AemiTestKit
import TerminalKitCodecs
import TerminalKitIO
import TerminalKitStyle
import Testing

@testable import TerminalKitRender

/// The ceilings describe the optimized renderer; an unoptimized build allocates where release does not.
private let isDebugBuild: Bool = {
    #if DEBUG
        true
    #else
        false
    #endif
}()

/// A frame flush runs after every input and every animation tick. The pipeline reuses its output
/// buffer for exactly this reason, so the ceiling for a flush is zero, whatever the frame changes.
///
/// Aemi's counter counts only the measuring thread (Aemi ADR-0010), so these ceilings hold in the
/// full suite alongside other tests.
@MainActor
@Suite("The renderer's frame flush does not allocate")
struct RenderPipelineAllocationTests {
    private let pipeline = RenderPipeline(connection: DiscardingConnection(), columns: 200, rows: 60)
    private let lines = [
        "the first line of a frame, long enough to need heap storage",
        "a second line with different text, so every row changes"
    ]

    @Test(.enabled(if: allocationCountingAvailable && !isDebugBuild))
    func `flushing a frame that changes every row does not allocate`() throws {
        try warmUp()
        let count = try #require(measuredFlushes { frame in paint(frame) })
        #expect(count == 0, "flushes of full-screen changes allocated \(count) times")
    }

    @Test(.enabled(if: allocationCountingAvailable && !isDebugBuild))
    func `flushing a frame with nothing to draw does not allocate`() throws {
        try warmUp()
        let count = try #require(measuredFlushes { _ in pipeline.beginFrame() })
        #expect(count == 0, "idle flushes allocated \(count) times")
    }

    @Test(.enabled(if: allocationCountingAvailable && !isDebugBuild))
    func `flushing a scrolled frame does not allocate`() throws {
        try warmUp()
        let count = try #require(
            measuredFlushes { frame in
                paint(frame)
                pipeline.scrollHint = ScrollHint(regionTop: 0, regionHeight: 60, delta: 1)
            })
        #expect(count == 0, "scrolled flushes allocated \(count) times")
    }

    /// Paints the whole screen, alternating the text so every row differs from the last frame.
    private func paint(_ frame: Int) {
        pipeline.beginFrame()
        for row in 0 ..< pipeline.rows {
            let style = row % 3 == 0 ? Style(bold: true) : .default
            pipeline.buffer.write(lines[(row + frame) % 2], row: row, col: 0, style: style)
        }
    }

    private func warmUp() throws {
        for frame in 0 ..< 8 {
            paint(frame)
            pipeline.scrollHint = frame.isMultiple(of: 2) ? ScrollHint(regionTop: 0, regionHeight: 60, delta: 1) : nil
            try pipeline.flush()
        }
    }

    /// The allocations eight flushes made in total; `prepare` runs unmeasured before each.
    private func measuredFlushes(_ prepare: (Int) -> Void) throws -> Int? {
        var total = 0
        for frame in 0 ..< 8 {
            prepare(frame)
            var failure: TerminalError?
            guard
                let count = mallocDelta({
                    do throws(TerminalError) { try pipeline.flush() } catch { failure = error }
                })
            else { return nil }
            if let failure { throw failure }
            total += count
        }
        return total
    }
}

/// A terminal that accepts every write and keeps none of it, so a measurement sees only the pipeline.
private final class DiscardingConnection: TerminalConnection {
    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
    func write(_ bytes: [UInt8]) throws(TerminalError) {}
    func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {}
    func enterRawMode() throws(TerminalError) {}
    func restoreMode() throws(TerminalError) {}
    func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 200, rows: 60) }
}
