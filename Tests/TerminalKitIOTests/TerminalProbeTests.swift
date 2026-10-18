internal import Foundation
internal import Synchronization
internal import Testing

@testable import TerminalKitIO

/// The three cases a capability probe has to survive, named in `ask`'s roadmap 0003: a terminal that
/// **answers correctly**, one that **lies**, and one that **times out**.
///
/// The third is the one that shaped the design. Silence is not a "no": a terminal that ignores a query
/// has told us nothing, so every probed field is optional and `nil` means *unknown*. Collapsing that
/// into `false` is exactly how the env-var guess came to be wrong.
@Suite("Terminal capabilities are probed, not guessed")
struct TerminalProbeTests {
    /// A connection that answers with `reply`, so a well-behaved terminal can be simulated exactly.
    /// Builds a connection that answers each query with its own reply.
    ///
    /// - Parameters:
    ///   - replies: one entry per query, in order. An empty entry means the terminal says nothing.
    ///   - size: the window the connection reports.
    /// - Returns: a connection that replays those replies.
    private func answering(_ replies: [[UInt8]], size: TerminalSize = TerminalSize(columns: 120, rows: 40))
        -> ScriptedConnection
    {
        ScriptedConnection(replies: replies, size: size)
    }

    /// A connection that never answers, so the deadline is what ends the wait.
    private func silent(size: TerminalSize = TerminalSize(columns: 120, rows: 40)) -> ScriptedConnection {
        ScriptedConnection(replies: [[], []], size: size)
    }

    // MARK: - Answers correctly

    @Test func `a terminal that answers the keyboard query reports its flags`() throws {
        let connection = answering([[0x1B, 0x5B, 0x3F, 0x31, 0x35, 0x75], []])  // CSI ? 15 u

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        #expect(probed.keyboardProtocolFlags == 15)
    }

    @Test func `a terminal that answers DECRQM as set reports synchronised output`() throws {
        let connection = answering([[], [0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x32, 0x36, 0x3B, 0x31, 0x24, 0x79]])

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        #expect(probed.synchronizedOutput == true)
    }

    @Test func `a terminal that answers DECRQM as reset reports no synchronised output`() throws {
        let connection = answering([[], [0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x32, 0x36, 0x3B, 0x32, 0x24, 0x79]])

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        #expect(probed.synchronizedOutput == false)
    }

    @Test func `the cell size comes from the window the terminal reports`() throws {
        let connection = answering(
            [[], []], size: TerminalSize(columns: 120, rows: 40, pixelWidth: 1080, pixelHeight: 720))

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        #expect(probed.cellPixelSize?.width == 9)
        #expect(probed.cellPixelSize?.height == 18)
        #expect(probed.canDrawPixelChrome)
    }

    @Test func `a terminal reporting no pixels has no drawable cell size`() throws {
        let connection = answering([[], []], size: TerminalSize(columns: 80, rows: 24))

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        #expect(probed.cellPixelSize == nil)
        #expect(probed.canDrawPixelChrome == false)
    }

    // MARK: - Lies

    @Test func `a reply that is not the query's own is discarded rather than guessed at`() throws {
        // A terminal emitting an unrelated escape sequence must not be read as a capability.
        let connection = answering([[0x1B, 0x5B, 0x33, 0x31, 0x6D], []])

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        #expect(probed.keyboardProtocolFlags == nil)
    }

    @Test(arguments: [0xFF, 0x20, 0x2F])
    func `a keyboard reply whose flags are not decimal digits is rejected`(byte: UInt8) throws {
        // Two digits, so the reply is long enough to reach the digit parse rather than being turned
        // away by the length check. Both ends of the range matter: an upper bound alone rejects 0xFF
        // while letting 0x20 through as a "digit" worth -16, which would become a capability.
        let connection = answering([[0x1B, 0x5B, 0x3F, byte, 0x31, 0x75], []])

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        #expect(probed.keyboardProtocolFlags == nil)
    }

    @Test func `a keyboard reply too short to hold its terminator is rejected`() throws {
        let connection = answering([[0x1B, 0x5B, 0x3F], []])

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        #expect(probed.keyboardProtocolFlags == nil)
    }

    // MARK: - Times out

    @Test func `a terminal that never answers reports unknown, not unsupported`() throws {
        let connection = silent()

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        // The point of the whole type: silence is not a "no".
        #expect(probed.keyboardProtocolFlags == nil)
        #expect(probed.synchronizedOutput == nil)
    }

    @Test func `a silent terminal still yields the size it reports`() throws {
        let connection = SilentConnection(size: TerminalSize(columns: 80, rows: 24, pixelWidth: 560, pixelHeight: 336))

        let probed = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        // `TIOCGWINSZ` needs no round trip, so it survives a terminal that answers nothing.
        #expect(probed.cellPixelSize?.width == 7)
        #expect(probed.cellPixelSize?.height == 14)
    }

    @Test func `the query is actually sent`() throws {
        let connection = answering([[0x1B, 0x5B, 0x3F, 0x31, 0x35, 0x75], []])

        _ = try TerminalProbe(connection: connection, timeout: .milliseconds(20)).probe()

        let written = connection.writtenOutput
        #expect(Self.contains(written, [0x1B, 0x5B, 0x3F, 0x75]))  // CSI ? u
        #expect(Self.contains(written, [0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x32, 0x36, 0x24, 0x70]))  // CSI ? 2026 $ p
    }

    // MARK: - Helpers

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        for start in 0 ... (haystack.count - needle.count)
        where Array(haystack[start ..< start + needle.count]) == needle { return true }
        return false
    }
}

/// A connection that never answers anything.
private final class SilentConnection: TerminalConnection, Sendable {
    let size: TerminalSize

    init(size: TerminalSize) { self.size = size }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
    func write(_ bytes: [UInt8]) throws(TerminalError) {}
    func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {}
    func enterRawMode() throws(TerminalError) {}
    func restoreMode() throws(TerminalError) {}
    func getSize() throws(TerminalError) -> TerminalSize { size }

    /// Reports "nothing is coming", which is what makes the probe's deadline the thing under test.
    func readAvailable(
        until deadline: ContinuousClock.Instant,
        into buffer: UnsafeMutableRawBufferPointer
    ) throws(TerminalError) -> Int? { 0 }
}

/// A connection that answers **each query with its own reply**, the way a real terminal does.
///
/// One shared reply was wrong: the probe's first query consumed it and the second found silence, which
/// reads as a capability failure when it is only a badly built test double.
private final class ScriptedConnection: TerminalConnection, Sendable {
    private let state = Mutex(State())

    private struct State {
        var pending: [[UInt8]] = []
        var written: [UInt8] = []
        var served = 0
    }

    private let size: TerminalSize

    /// Creates a scripted connection.
    ///
    /// - Parameters:
    ///   - replies: one entry per query, in order. An empty entry means "no answer".
    ///   - size: the window the connection reports.
    init(replies: [[UInt8]], size: TerminalSize) {
        self.size = size
        state.withLock { $0.pending = replies }
    }

    var writtenOutput: [UInt8] { state.withLock { $0.written } }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }

    func write(_ bytes: [UInt8]) throws(TerminalError) { recordQuery(ContiguousArray(bytes)) }

    func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
        recordQuery(bytes)
    }

    private func recordQuery(_ bytes: ContiguousArray<UInt8>) {
        state.withLock { state in
            state.written.append(contentsOf: bytes)
            state.served += 1
        }
    }

    func enterRawMode() throws(TerminalError) {}
    func restoreMode() throws(TerminalError) {}
    func getSize() throws(TerminalError) -> TerminalSize { size }

    /// Serves the scripted reply once, then reports that nothing more is coming.
    func readAvailable(
        until deadline: ContinuousClock.Instant,
        into buffer: UnsafeMutableRawBufferPointer
    ) throws(TerminalError) -> Int? {
        // The index advances when a query is *written*, not when a read is attempted: a probe polls
        // until its deadline, and counting polls would burn through the scripted replies before the
        // second query was ever asked.
        let payload: [UInt8] = state.withLock { state in
            guard state.served > 0, state.served <= state.pending.count else { return [] }
            return state.pending[state.served - 1]
        }
        guard !payload.isEmpty else { return 0 }
        let count = min(buffer.count, payload.count)
        buffer.copyBytes(from: payload.prefix(count))
        return count
    }
}
