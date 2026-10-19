import Darwin
import TerminalKitCodecs
public import TerminalKitIO

/// Async stream of input events from a terminal connection.
public final class InputSource: Sendable {
    /// The most bytes one read takes from the terminal.
    static let readSize = 4096

    private let connection: any TerminalConnection
    private let escapeIsUnambiguous: Bool
    private let _events: AsyncStream<InputEvent>
    private let continuation: AsyncStream<InputEvent>.Continuation

    public var events: AsyncStream<InputEvent> { _events }

    /// - Parameters:
    ///   - connection: the terminal to read.
    ///   - escapeIsUnambiguous: whether the terminal sends the Escape key as `CSI 27 u`
    ///     (``TerminalSession/escapeIsUnambiguous``). Then a lone `ESC` at the end of a read is the start of a
    ///     sequence split across reads, and waits for its rest. Otherwise it is read as the Escape key, the
    ///     only reading available to a legacy terminal.
    public init(connection: any TerminalConnection, escapeIsUnambiguous: Bool = false) {
        self.connection = connection
        self.escapeIsUnambiguous = escapeIsUnambiguous
        // Unbounded: every keystroke must arrive in order, even from a fast paste under load.
        let (stream, cont) = AsyncStream<InputEvent>
            .makeStream(
                bufferingPolicy: .unbounded)
        self._events = stream
        self.continuation = cont
    }

    /// Starts the read loop in a new task and returns it. The stream finishes however the loop ends, and a consumer
    /// that stops iterating cancels the loop; a blocked read can't be interrupted, so cancellation lands when the read
    /// returns.
    @discardableResult
    public func start() -> Task<Void, Never> {
        let task = Task { [connection, continuation, escapeIsUnambiguous] in
            var router = SequenceRouter()
            var routedEvents: [InputEvent] = []
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: Self.readSize, alignment: 1)
            defer {
                buffer.deallocate()
                continuation.finish()
            }

            while !Task.isCancelled {
                do {
                    let count = try connection.read(into: buffer)
                    if Task.isCancelled { return }
                    let raw = UnsafeRawBufferPointer(start: buffer.baseAddress, count: count)
                    let span: Span<UInt8> = raw.bytes._unsafeView(as: UInt8.self)
                    router.feedAll(span, into: &routedEvents)
                    // A full read may have cut a sequence short; any other ends where the terminal's writes did,
                    // unless Escape is unambiguous, when a trailing ESC can only begin a sequence.
                    if count < Self.readSize, !escapeIsUnambiguous {
                        router.flushPendingEscape(into: &routedEvents)
                    }
                    for event in routedEvents {
                        if Task.isCancelled { return }
                        continuation.yield(event)
                    }
                } catch TerminalError.readFailed(let code) where code == EINTR {
                    continue
                } catch {
                    break
                }
            }
        }
        let producerTask = task
        continuation.onTermination = { @Sendable _ in
            producerTask.cancel()
        }
        return task
    }

    /// Inject an event into the stream from outside the read loop (e.g., from a signal handler).
    public func inject(_ event: InputEvent) {
        continuation.yield(event)
    }

    public func stop() {
        continuation.finish()
    }
}
