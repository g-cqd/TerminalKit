internal import Dispatch
internal import Foundation
internal import Synchronization
import Testing

@testable import TerminalKitIO

/// Two writers on one terminal, a render thread's frames and an event loop's escape sequences, must not
/// interleave: a sequence cut in two by a frame is garbage on screen.
@Suite("Serialized writes never interleave")
struct SerializedConnectionTests {
    /// Appends a write one byte at a time, so two writes that overlap in time interleave in the log.
    private final class ByteWise: TerminalConnection {
        private let log = Mutex<[UInt8]>([])
        var bytes: [UInt8] { log.withLock { $0 } }
        func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
        func write(_ bytes: [UInt8]) throws(TerminalError) {
            for byte in bytes {
                log.withLock { $0.append(byte) }
                sched_yield()
            }
        }
        func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) { try write(Array(bytes)) }
        func enterRawMode() throws(TerminalError) {}
        func restoreMode() throws(TerminalError) {}
        func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 80, rows: 24) }
    }

    /// The number of runs of equal bytes: two whole writes of distinct bytes make two runs.
    private func runs(_ bytes: [UInt8]) -> Int {
        zip(bytes, bytes.dropFirst()).reduce(1) { $0 + ($1.0 == $1.1 ? 0 : 1) }
    }

    @Test func `two threads writing at once leave two whole runs`() {
        let inner = ByteWise()
        let connection = SerializedConnection(inner)
        let done = DispatchGroup()
        for byte: UInt8 in [0x41, 0x42] {
            done.enter()
            Thread {
                try? connection.writeContiguous(ContiguousArray(repeating: byte, count: 2_000))
                done.leave()
            }
            .start()
        }
        done.wait()

        #expect(inner.bytes.count == 4_000)
        #expect(runs(inner.bytes) == 2)
    }

    @Test func `without it, the same writes interleave`() {
        // The control: the probe can fail.
        let inner = ByteWise()
        let done = DispatchGroup()
        for byte: UInt8 in [0x41, 0x42] {
            done.enter()
            Thread {
                try? inner.writeContiguous(ContiguousArray(repeating: byte, count: 2_000))
                done.leave()
            }
            .start()
        }
        done.wait()

        #expect(runs(inner.bytes) > 2)
    }

    @Test func `everything else is forwarded`() throws {
        let mock = MockTerminalConnection(size: TerminalSize(columns: 10, rows: 5))
        let connection = SerializedConnection(mock)

        try connection.enterRawMode()
        try connection.write([1, 2])
        try connection.restoreMode()

        #expect(mock.writtenOutput == [1, 2])
        #expect(mock.restoreModeCallCount == 1)
        #expect(try connection.getSize().columns == 10)
    }
}
