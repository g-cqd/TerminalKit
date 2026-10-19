import Darwin
import Foundation
import Synchronization
import TerminalKitCodecs
public import TerminalKitIO

/// Async stream of input events from a terminal connection.
public final class InputSource: Sendable {
    /// The most bytes one read takes from the terminal.
    static let readSize = 4096

    private let connection: any TerminalConnection
    /// Shared with the read loop, which captures it rather than `self`.
    private let unambiguousEscape: AtomicFlag
    /// Set by ``stop()``; the loop checks it after every wait.
    private let stopped = AtomicFlag(false)
    /// The wake-up of every loop started, so ``stop()`` can interrupt them.
    private let wakers = Mutex<[InputWaker]>([])

    /// Whether the terminal sends the Escape key as `CSI 27 u` (``TerminalSession/escapeIsUnambiguous``).
    /// Then a lone `ESC` at the end of a read is the start of a sequence split across reads, and waits for its
    /// rest; otherwise it is read as the Escape key, the only reading available to a legacy terminal. It may
    /// change while reading, when a probe reply arrives; each read uses the value it finds.
    public var escapeIsUnambiguous: Bool {
        get { unambiguousEscape.value }
        set { unambiguousEscape.value = newValue }
    }
    private let _events: AsyncStream<InputEvent>
    private let continuation: AsyncStream<InputEvent>.Continuation

    public var events: AsyncStream<InputEvent> { _events }

    /// - Parameters:
    ///   - connection: the terminal to read.
    ///   - escapeIsUnambiguous: the initial ``escapeIsUnambiguous``.
    public init(connection: any TerminalConnection, escapeIsUnambiguous: Bool = false) {
        self.connection = connection
        self.unambiguousEscape = AtomicFlag(escapeIsUnambiguous)
        // Unbounded: every keystroke must arrive in order, even from a fast paste under load.
        let (stream, cont) = AsyncStream<InputEvent>
            .makeStream(
                bufferingPolicy: .unbounded)
        self._events = stream
        self.continuation = cont
    }

    /// Starts reading on a thread of its own and returns a task that ends when reading does.
    ///
    /// The thread waits in `poll` on the terminal and on a wake-up pipe, so it never holds a thread of Swift's
    /// cooperative pool, and ``stop()``, cancelling the task, or a consumer that stops iterating ``events`` ends
    /// it even while no byte arrives (roadmap 0009). Connections without a pollable descriptor are read directly.
    @discardableResult
    public func start() -> Task<Void, Never> {
        let completion = InputCompletion()
        if let waker = InputWaker() {
            let loop = InputLoop(
                connection: connection, continuation: continuation, unambiguousEscape: unambiguousEscape,
                stopped: stopped, waker: waker)
            let thread = Thread {
                loop.run()
                completion.finish()
            }
            thread.name = "TerminalKit.input"
            thread.stackSize = 256 * 1024
            wakers.withLock { $0.append(waker) }
            thread.start()
        } else {
            continuation.finish()
            completion.finish()
        }
        continuation.onTermination = { [weak self] _ in self?.stop() }
        return Task {
            await withTaskCancellationHandler {
                await completion.wait()
            } onCancel: { [weak self] in
                self?.stop()
            }
        }
    }

    /// Inject an event into the stream from outside the read loop (e.g., from a signal handler).
    public func inject(_ event: InputEvent) {
        continuation.yield(event)
    }

    /// Stops reading: the thread leaves its wait and exits, and ``events`` finishes.
    public func stop() {
        stopped.value = true
        for waker in wakers.withLock({ $0 }) { waker.wake() }
        continuation.finish()
    }
}
