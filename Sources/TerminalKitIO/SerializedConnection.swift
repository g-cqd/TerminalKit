internal import Synchronization

/// A connection whose writes never overlap in time, so two writers cannot cut each other's bytes in two.
///
/// A render thread writes whole frames while an event loop writes the odd escape sequence (a keyboard mode, a
/// title). Each `write` takes a lock for as long as it runs, so a sequence lands before a frame or after it,
/// never inside it (ADR-0026). Reads and the rest are forwarded untouched: a read blocks, and must not hold
/// up a write.
public final class SerializedConnection: TerminalConnection {
    private let inner: any TerminalConnection
    private let writeLock = Mutex(())

    public init(_ inner: any TerminalConnection) { self.inner = inner }

    public func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int {
        try inner.read(into: buffer)
    }

    public func write(_ bytes: [UInt8]) throws(TerminalError) {
        try writeLock.withLock { _ throws(TerminalError) in try inner.write(bytes) }
    }

    public func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
        try writeLock.withLock { _ throws(TerminalError) in try inner.writeContiguous(bytes) }
    }

    public func enterRawMode() throws(TerminalError) { try inner.enterRawMode() }
    public func restoreMode() throws(TerminalError) { try inner.restoreMode() }
    public func getSize() throws(TerminalError) -> TerminalSize { try inner.getSize() }
    public var pollableFileDescriptor: Int32? { inner.pollableFileDescriptor }

    public func readAvailable(until deadline: ContinuousClock.Instant, into buffer: UnsafeMutableRawBufferPointer)
        throws(TerminalError) -> Int?
    {
        try inner.readAvailable(until: deadline, into: buffer)
    }
}
