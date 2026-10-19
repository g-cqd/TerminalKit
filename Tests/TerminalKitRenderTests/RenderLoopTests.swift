internal import Dispatch
internal import Foundation
internal import Synchronization
import TerminalKitIO
import TerminalKitStyle
import Testing

@testable import TerminalKitRender

/// Roadmap 0014 (ADR-0026): a render loop owns the pipeline on a thread of its own and draws the newest state it
/// is given, so whatever produces states, an event loop handling input, never waits for a frame.
@Suite("A render loop draws the newest state on its own thread")
struct RenderLoopTests {
    /// Draws `State.text` on row 0, records every state it draws and the thread it ran on, and can hold a frame
    /// open until the test lets it go.
    private struct Text: FrameComposer {
        struct State: Sendable { var text: String }
        final class Log: Sendable {
            private let inner = Mutex<(drawn: [String], threads: Set<String>)>(([], []))
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let blocksFirstFrame = Atomic<Bool>(false)
            /// Returns once the frame that blocks is open. A plain function, so a test may call it from async code.
            func waitUntilFrameIsOpen() { entered.wait() }
            func letFrameFinish() { release.signal() }
            var drawn: [String] { inner.withLock { $0.drawn } }
            var threads: Set<String> { inner.withLock { $0.threads } }
            func record(_ text: String) {
                inner.withLock {
                    $0.drawn.append(text)
                    $0.threads.insert(Thread.current.name ?? "")
                }
            }
        }
        let log: Log

        mutating func compose(_ state: State, into pipeline: RenderPipeline) {
            log.record(state.text)
            if log.blocksFirstFrame.exchange(false, ordering: .acquiringAndReleasing) {
                log.entered.signal()
                log.release.wait()
            }
            pipeline.buffer.write(state.text, row: 0, col: 0, style: .default)
        }
    }

    private func loop(blockingFirstFrame: Bool = false) -> (RenderLoop<Text>, Text.Log, MockTerminalConnection) {
        let log = Text.Log()
        log.blocksFirstFrame.store(blockingFirstFrame, ordering: .relaxed)
        let connection = MockTerminalConnection()
        return (RenderLoop(connection: connection, columns: 20, rows: 3, composer: Text(log: log)), log, connection)
    }

    @Test func `frames are drawn on a thread named for the render loop, not the caller's`() async {
        let (loop, log, _) = loop()

        loop.submit(.init(text: "one"))
        await loop.finish()

        #expect(log.threads == ["TerminalKit.render"])
    }

    @Test func `a state submitted while a frame is drawing replaces the ones before it`() async {
        let (loop, log, _) = loop(blockingFirstFrame: true)
        loop.submit(.init(text: "one"))
        log.waitUntilFrameIsOpen()  // frame one is open

        loop.submit(.init(text: "two"))
        loop.submit(.init(text: "three"))
        loop.submit(.init(text: "four"))
        log.letFrameFinish()
        await loop.finish()

        #expect(log.drawn == ["one", "four"])
    }

    @Test func `finishing draws the last state submitted, then stops`() async {
        let (loop, log, connection) = loop(blockingFirstFrame: true)
        loop.submit(.init(text: "one"))
        log.waitUntilFrameIsOpen()
        loop.submit(.init(text: "last"))
        log.letFrameFinish()

        await loop.finish()

        #expect(log.drawn.last == "last")
        #expect(String(decoding: connection.writtenOutput, as: UTF8.self).contains("last"))
    }

    @Test func `a state submitted after finishing is ignored`() async {
        let (loop, log, _) = loop()
        loop.submit(.init(text: "one"))
        await loop.finish()

        loop.submit(.init(text: "late"))
        await loop.finish()

        #expect(log.drawn == ["one"])
    }

    @Test func `the frame after the first is a diff, not a redraw`() async {
        let (loop, log, connection) = loop(blockingFirstFrame: true)
        loop.submit(.init(text: "hello"))
        log.waitUntilFrameIsOpen()
        loop.submit(.init(text: "hellp"))  // waits behind the open frame
        log.letFrameFinish()
        await loop.finish()

        let output = String(decoding: connection.writtenOutput, as: UTF8.self)
        #expect(log.drawn == ["hello", "hellp"])
        // The second frame writes the one cell that changed, at column 5.
        #expect(output.contains("\u{1B}[1;5Hp"))
        #expect(output.components(separatedBy: "hello").count == 2, "the second frame rewrote the first's text")
    }

    @Test func `a resize redraws everything at the new size`() async {
        let (loop, log, connection) = loop()
        loop.submit(.init(text: "kept"))
        loop.resize(columns: 30, rows: 5)
        loop.submit(.init(text: "kept"))
        await loop.finish()

        let output = String(decoding: connection.writtenOutput, as: UTF8.self)
        // A full redraw moves to the start of every row; 5 rows.
        #expect(output.components(separatedBy: "\u{1B}[5;1H").count >= 2)
        #expect(log.drawn.last == "kept")
    }

    @Test func `halting stops the thread at once and draws nothing more`() async {
        let (loop, log, connection) = loop(blockingFirstFrame: true)
        loop.submit(.init(text: "one"))
        log.waitUntilFrameIsOpen()
        loop.submit(.init(text: "never drawn"))
        // The open frame finishes (it cannot be taken back); then the loop halts without drawing the next. The
        // halt is requested before the frame is let go, so the order does not depend on scheduling.
        loop.beginHalt()
        log.letFrameFinish()
        let halted = Task.detached { loop.halt() }
        await halted.value

        #expect(log.drawn == ["one"])
        let written = connection.writtenOutput.count
        loop.submit(.init(text: "after"))
        await loop.finish()
        #expect(connection.writtenOutput.count == written)
    }

    @Test func `a connection that fails ends the loop and says so`() async {
        final class Failing: TerminalConnection {
            func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
            func write(_ bytes: [UInt8]) throws(TerminalError) { throw .writeFailed(5) }
            func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) { throw .writeFailed(5) }
            func enterRawMode() throws(TerminalError) {}
            func restoreMode() throws(TerminalError) {}
            func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 20, rows: 3) }
        }
        let log = Text.Log()
        let loop = RenderLoop(connection: Failing(), columns: 20, rows: 3, composer: Text(log: log))

        loop.submit(.init(text: "one"))
        await loop.finish()

        #expect(loop.failure == .writeFailed(5))
    }
}
