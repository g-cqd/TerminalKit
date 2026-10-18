internal import Darwin
internal import Synchronization

/// Asks the terminal what it supports, instead of reading environment variables and guessing.
///
/// ## Why this exists
///
/// `TerminalCapabilities.init(environment:size:)` decided whether a terminal spoke the kitty graphics
/// protocol by testing `KITTY_WINDOW_ID != nil || …`. Measured failure: an `ask` session running inside
/// kitty exported `KITTY_WINDOW_ID=4`, every terminal the test launcher started inherited it, and
/// **Terminal.app reported `supportsKittyGraphics: true`** — for a protocol it does not speak. Probing
/// confirmed it, by watching Terminal.app draw the APC introducer and the base64 payload as visible
/// text while kitty consumed the same bytes and replied `ESC _ G i=1;OK ESC \`.
///
/// An environment variable is a hint. It is also, as that case showed, a value the parent can leak into
/// a process that has nothing to do with it.
///
/// ## What is actually knowable
///
/// | Capability | How it is established |
/// |---|---|
/// | Cell pixel size | `TIOCGWINSZ`, through the connection. No round trip. |
/// | Synchronised output (DEC 2026) | DECRQM: `CSI ? 2026 $ p` |
/// | Kitty keyboard protocol | `CSI ? u`, answered with the flags |
/// | Kitty graphics protocol | **not queryable** — no terminal defines a query for it |
///
/// The last row is the honest part. Anything this type says about graphics is a **hint**, kept in
/// ``TerminalCapabilities/hintedGraphicsSupport(environment:)`` and never in the probed result, because
/// presenting a guess beside a measurement is how the two get confused.
///
/// ## Silence is not "unsupported"
///
/// A terminal that does not answer a query has not told us it lacks the feature — it has told us
/// nothing. That distinction is the whole point of the type: every probed value is optional, and
/// `nil` means *unknown*, which callers must handle rather than read as `false`.
public struct TerminalProbe: Sendable {
    /// How long to wait for a terminal to answer a single query.
    ///
    /// **Measured, and the number is the point.** On a PTY whose far end never replies — a terminal
    /// that ignores both queries, which is what Terminal.app does — two queries at 250 ms each cost
    /// **520 ms**. A terminal that *does* answer costs microseconds, because `poll` returns as soon as
    /// the reply lands.
    ///
    /// So the cost is entirely the terminal's refusal to answer, and it is not small: against `ask`'s
    /// 25 ms cold-start budget, a blocking probe is the single most expensive thing a terminal program
    /// could do at launch.
    ///
    /// Callers on a latency budget must therefore either use a much shorter deadline, or — better —
    /// probe **off** the startup path and keep conservative defaults until the answers arrive. The
    /// capability is for improving behaviour once running, not for gating the first frame.
    public static let defaultTimeout = Duration.milliseconds(250)

    private let connection: any TerminalConnection
    private let timeout: Duration

    public init(connection: any TerminalConnection, timeout: Duration = TerminalProbe.defaultTimeout) {
        self.connection = connection
        self.timeout = timeout
    }

    /// Asks the terminal, and reports only what it answered.
    ///
    /// Each query is written, then the reply is collected under a deadline. A reply that does not parse
    /// is discarded rather than guessed at: a terminal that answers `CSI ? u` with something else has
    /// not told us it supports the keyboard protocol.
    ///
    /// - Returns: the probed capabilities, with `nil` for anything the terminal did not answer.
    /// - Complexity: O(1) — a fixed number of queries, each bounded by `timeout`.
    public func probe() throws(TerminalError) -> ProbedCapabilities {
        var result = ProbedCapabilities()

        result.cellPixelSize = TerminalCapabilities.cellPixelSize(of: try connection.getSize())

        // Keyboard protocol first: it is a bare sequence with a distinctive reply, so a stray escape
        // in the input stream cannot be mistaken for an answer to it.
        if let flags = try askKeyboardProtocol() {
            result.keyboardProtocolFlags = flags
        }
        if let synchronized = try askSynchronizedOutput() {
            result.synchronizedOutput = synchronized
        }
        return result
    }

    // MARK: - Queries

    /// `CSI ? u` — the kitty keyboard protocol reports its supported flags in reply.
    ///
    /// A terminal without the protocol either ignores the query or answers `CSI ? 0 u`, which means
    /// "none", and is recorded as an answer of `0` rather than as silence.
    private func askKeyboardProtocol() throws(TerminalError) -> Int? {
        try connection.writeContiguous(ContiguousArray([0x1B, 0x5B, 0x3F, 0x75]))
        guard let reply = try readReply(matching: KeyboardReply.self) else { return nil }
        return reply.flags
    }

    /// `CSI ? 2026 $ p` — DECRQM reports whether a mode is set, reset, or unknown.
    private func askSynchronizedOutput() throws(TerminalError) -> Bool? {
        try connection.writeContiguous(ContiguousArray(Self.decrqm2026))
        guard let reply = try readReply(matching: DecrqmReply.self) else { return nil }
        return reply.state == 1
    }

    /// Collects bytes until a reply of `Reply` parses, or the deadline passes.
    ///
    /// - Returns: the parsed reply, or nil when the terminal said nothing or said something else.
    private func readReply<Reply: TerminalReply>(matching: Reply.Type) throws(TerminalError) -> Reply? {
        var buffer: [UInt8] = []
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            guard let chunk = try readAvailable(until: deadline) else { continue }
            if chunk.isEmpty { continue }
            buffer.append(contentsOf: chunk)
            if let reply = Reply(bytes: buffer) { return reply }
            // A reply that cannot begin with these bytes is unrelated input; do not keep growing on it.
            if buffer.count > Self.maximumReplyLength { return nil }
        }
        return nil
    }

    /// Bytes available before `deadline`, or nil when the connection cannot answer with a deadline.
    private func readAvailable(until deadline: ContinuousClock.Instant) throws(TerminalError) -> [UInt8]? {
        var scratch = ContiguousArray<UInt8>(repeating: 0, count: 512)
        var readError: TerminalError?
        let count: Int? = scratch.withUnsafeMutableBytes { raw in
            // `withUnsafeMutableBytes` widens the thrown type, so the typed error is carried out and
            // rethrown rather than erased.
            do { return try connection.readAvailable(until: deadline, into: raw) } catch let error as TerminalError {
                readError = error
                return nil
            } catch {
                readError = .readFailed(-1)
                return nil
            }
        }
        if let readError { throw readError }
        // nil: the connection cannot say. The probe records nothing, rather than "no".
        guard let count, count > 0 else { return nil }
        return Array(scratch.prefix(count))
    }

    /// `CSI ? 2026 $ p`.
    private static let decrqm2026: [UInt8] = [0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x32, 0x36, 0x24, 0x70]
    private static let maximumReplyLength = 64
}

// MARK: - Results

/// What the terminal actually answered. Every field is optional because a query can go unanswered.
public struct ProbedCapabilities: Sendable, Equatable {
    /// The cell size the window reports, when the terminal reports pixel dimensions at all.
    public var cellPixelSize: TerminalCapabilities.CellPixelSize?

    /// The kitty keyboard protocol flags the terminal reported; nil when it did not answer.
    public var keyboardProtocolFlags: Int?

    /// Whether DEC 2026 synchronised output is supported; nil when the terminal did not answer.
    public var synchronizedOutput: Bool?

    public init(
        cellPixelSize: TerminalCapabilities.CellPixelSize? = nil,
        keyboardProtocolFlags: Int? = nil,
        synchronizedOutput: Bool? = nil
    ) {
        self.cellPixelSize = cellPixelSize
        self.keyboardProtocolFlags = keyboardProtocolFlags
        self.synchronizedOutput = synchronizedOutput
    }

    /// Whether pixel chrome can be drawn, as far as a measurement can say.
    ///
    /// Deliberately says nothing about the graphics protocol: that is not queryable, so a "yes" here
    /// would be a guess wearing a measured value's clothes. See ``TerminalProbe``.
    public var canDrawPixelChrome: Bool { cellPixelSize?.isDrawable == true }
}

// MARK: - Replies

/// A reply the terminal sent, parsed strictly.
protocol TerminalReply {
    /// Parses a reply from everything read so far, or returns nil if these bytes cannot be one.
    init?(bytes: [UInt8])

    /// Parses ASCII decimal digits, rejecting anything else.
    ///
    /// Written out rather than leaning on `Int.init`: a reply is untrusted input from a process we do
    /// not control, and a permissive parse would turn a malformed answer into a capability.
    static func decimal(_ bytes: [UInt8]) -> Int?
}

extension TerminalReply {
    static func decimal(_ bytes: [UInt8]) -> Int? {
        guard !bytes.isEmpty else { return nil }
        var value = 0
        for byte in bytes {
            guard byte >= 0x30, byte <= 0x39 else { return nil }
            let digit = Int(byte - 0x30)
            guard value <= (Int.max - digit) / 10 else { return nil }
            value = value * 10 + digit
        }
        return value
    }
}

/// `CSI ? <flags> u`
struct KeyboardReply: TerminalReply, Equatable {
    let flags: Int

    init?(bytes: [UInt8]) {
        guard bytes.count >= 6,
            bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x3F,
            bytes.last == 0x75
        else { return nil }
        // The last byte is the terminator; the digits sit between `?` and it.
        guard let flags = Self.decimal(Array(bytes[3 ..< (bytes.count - 1)])) else { return nil }
        self.flags = flags
    }
}

/// `CSI ? 2026 ; <state> $ y`
struct DecrqmReply: TerminalReply, Equatable {
    /// 1 set, 2 reset, 0 unknown — DECRQM's three answers.
    let state: Int

    init?(bytes: [UInt8]) {
        guard bytes.count >= 11,
            bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x3F,
            bytes[bytes.count - 2] == 0x24, bytes[bytes.count - 1] == 0x79
        else { return nil }
        // `?2026;` then the state digits.
        let body = Array(bytes[3 ..< (bytes.count - 2)])
        guard body.count > 5, body[4] == 0x3B, let state = Self.decimal(Array(body[5...])) else {
            return nil
        }
        self.state = state
    }
}
