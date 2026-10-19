internal import Darwin
internal import Foundation
internal import Synchronization
internal import TerminalKitIO
import Testing

@testable import TerminalKitInput

/// Roadmap 0009: the input source reads on a thread of its own, not on one of Swift's cooperative pool threads,
/// and stopping it ends a read that is still waiting.
///
/// Measured before the change (`Benchmarks/Probes/InputPoolProbe`): a batch of one CPU-bound task per core took
/// 16.4 ms alone and 23.7 ms while an InputSource read an idle PTY; and a stopped source whose PTY stayed
/// quiet kept its pool thread for good, so ten of them exhausted the pool.
@Suite("Input is read on its own thread")
struct InputThreadTests {
    /// Records the name of the thread each read runs on, then reports the connection closed.
    private final class ThreadRecordingConnection: TerminalConnection {
        private let names = Mutex<[String?]>([])
        var readThreadNames: [String?] { names.withLock { $0 } }

        func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int {
            let name = Thread.current.name
            names.withLock { $0.append(name) }
            throw .connectionClosed
        }
        func write(_ bytes: [UInt8]) throws(TerminalError) {}
        func enterRawMode() throws(TerminalError) {}
        func restoreMode() throws(TerminalError) {}
        func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 80, rows: 24) }
    }

    @Test func `reads run on the input thread, not the cooperative pool`() async {
        let connection = ThreadRecordingConnection()
        let source = InputSource(connection: connection)

        await source.start().value

        #expect(connection.readThreadNames == ["TerminalKit.input"])
    }

    @Test func `stopping ends a read that is still waiting for input`() async throws {
        var emulator: Int32 = -1
        var terminal: Int32 = -1
        // SAFETY: two live out-parameters; name, settings and size omitted.
        #expect(unsafe openpty(&emulator, &terminal, nil, nil, nil) == 0)
        defer {
            close(emulator)
            close(terminal)
        }
        // Raw, as a full-screen program runs it: a canonical terminal would hold the key until a newline.
        var settings = termios()
        tcgetattr(terminal, &settings)
        unsafe cfmakeraw(&settings)
        tcsetattr(terminal, TCSANOW, &settings)
        let source = InputSource(connection: POSIXTerminalConnection(fileDescriptor: terminal))
        let task = source.start()
        // One key, received, proves the loop is running; it then goes back to waiting for the next.
        _ = write(emulator, "a", 1)
        var events = source.events.makeAsyncIterator()
        _ = await events.next()

        source.stop()

        await task.value  // returns although no further byte arrives
        #expect(await events.next() == nil)
    }
}
