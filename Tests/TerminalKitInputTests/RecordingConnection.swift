internal import Synchronization
internal import TerminalKitIO

/// A connection that records each call in order, so a test can see how many writes a step took and
/// whether raw mode came before them. It can be told to fail its writes.
final class RecordingConnection: TerminalConnection {
    enum Call: Equatable {
        case enterRawMode
        case restoreMode
        case write([UInt8])
    }

    private let log = Mutex<[Call]>([])
    private let failWrites: Bool

    init(failWrites: Bool = false) { self.failWrites = failWrites }

    var calls: [Call] { log.withLock { $0 } }

    /// Every byte written, in order.
    var written: [UInt8] {
        calls.flatMap { call -> [UInt8] in
            if case .write(let bytes) = call { return bytes }
            return []
        }
    }

    /// The number of writes.
    var writeCount: Int { calls.count { if case .write = $0 { true } else { false } } }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { throw .connectionClosed }

    func write(_ bytes: [UInt8]) throws(TerminalError) {
        guard !failWrites else { throw .writeFailed(5) }
        log.withLock { $0.append(.write(bytes)) }
    }

    func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) { try write(Array(bytes)) }
    func enterRawMode() throws(TerminalError) { log.withLock { $0.append(.enterRawMode) } }
    func restoreMode() throws(TerminalError) { log.withLock { $0.append(.restoreMode) } }
    func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 80, rows: 24) }
}
