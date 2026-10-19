import TerminalKitIO

/// Writes go nowhere: the pipeline's own cost is what these designs are compared on.
final class DiscardingConnection: TerminalConnection {
    private let size: TerminalSize
    init(size: TerminalSize) { self.size = size }
    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
    func write(_ bytes: [UInt8]) throws(TerminalError) {}
    func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {}
    func enterRawMode() throws(TerminalError) {}
    func restoreMode() throws(TerminalError) {}
    func getSize() throws(TerminalError) -> TerminalSize { size }
}
