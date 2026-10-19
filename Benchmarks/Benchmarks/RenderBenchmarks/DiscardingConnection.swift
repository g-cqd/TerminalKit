import Synchronization
public import TerminalKitIO

/// A connection that keeps only the size of the last write.
///
/// `MockTerminalConnection` appends every write to one array that grows for the whole run, under a lock, so
/// a benchmark through it would also time the mock's copy of each frame. A terminal write is the boundary
/// these suites stop at.
final class DiscardingConnection: TerminalConnection {
    private let lastWrite = Atomic<Int>(0)
    private let size: TerminalSize

    init(size: TerminalSize) { self.size = size }

    /// The byte count of the most recent write.
    var lastWriteBytes: Int { lastWrite.load(ordering: .relaxed) }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
    func write(_ bytes: [UInt8]) throws(TerminalError) { lastWrite.store(bytes.count, ordering: .relaxed) }
    func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
        lastWrite.store(bytes.count, ordering: .relaxed)
    }
    func enterRawMode() throws(TerminalError) {}
    func restoreMode() throws(TerminalError) {}
    func getSize() throws(TerminalError) -> TerminalSize { size }
}
