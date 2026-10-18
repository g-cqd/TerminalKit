internal import Darwin
internal import Foundation
internal import Synchronization

/// Delivers `SIGWINCH`, `SIGINT` and `SIGTERM` to closures, off the caller's thread.
///
/// ## Why this is not a `DispatchSource`
///
/// The previous implementation gave `DispatchSource.makeSignalSource(signal:queue:)` the `.main`
/// queue. That works until the main thread blocks — which a terminal program does permanently, sitting
/// in `read(into:)` waiting for a keystroke. The main queue then never turns, the continuation never
/// yields, and the process **stops responding to `SIGTERM` entirely**.
///
/// That is worse than having no handler, because it reads as handled. It was measured: with this
/// wired, a running `ask` was still alive four seconds after a `SIGTERM`, and had to be `SIGKILL`ed.
///
/// ## How this works instead
///
/// A `sigaction` handler may only do async-signal-safe things, so it does the least possible: it
/// writes the signal number to one byte of a pipe and returns. A dedicated thread drains that pipe.
///
/// The pipe is what removes the race — a signal arriving before the drain thread starts is buffered,
/// not lost — so `start()` can install and return without waiting, and a test can send a signal
/// immediately after without sleeping.
///
/// The drain runs on a Foundation `Thread` rather than a Swift task on purpose: parking a cooperative
/// pool thread on a blocking `read` would cost the whole pool a thread for the process's lifetime, and
/// this package is consumed by programs whose budgets are measured in single-digit milliseconds.
///
/// ## Scope
///
/// One pipe, one drain thread: the write descriptor is process-global, so two live handlers would
/// fight over it. `start()` throws rather than silently corrupting the first one.
public final class SignalHandler: Sendable {
    private let onResize: @Sendable () -> Void
    private let onShutdown: @Sendable (Int32) -> Void

    /// Creates a handler.
    ///
    /// - Parameters:
    ///   - onResize: called on the drain thread when `SIGWINCH` arrives. Carries no signal, because
    ///     there is only one that means resize.
    ///   - onShutdown: called on the drain thread when `SIGINT` or `SIGTERM` arrives, with the signal
    ///     that fired. **Report the signal to the caller**: a handler that restores a terminal and
    ///     exits needs the number to produce the shell-conventional `128 + signo` status.
    public init(
        onResize: @escaping @Sendable () -> Void,
        onShutdown: @escaping @Sendable (Int32) -> Void
    ) {
        self.onResize = onResize
        self.onShutdown = onShutdown
    }

    /// Installs the handlers and starts the drain thread.
    ///
    /// Installation is synchronous, so a signal sent the instant this returns is buffered by the pipe
    /// and delivered rather than lost.
    ///
    /// - Throws: `SignalHandlerError.alreadyRunning` when another handler still holds the pipe.
    public func start() throws {
        guard let pipe = Self.makePipe() else {
            throw SignalHandlerError.pipeUnavailable
        }
        guard Self.claimWriteDescriptor(pipe) else {
            _ = Darwin.close(pipe.read)
            _ = Darwin.close(pipe.write)
            throw SignalHandlerError.alreadyRunning
        }
        Self.install(signal: SIGWINCH)
        Self.install(signal: SIGINT)
        Self.install(signal: SIGTERM)

        let handler = self
        let thread = Thread { handler.drain(readDescriptor: pipe.read) }
        thread.name = "TerminalKit.signal-drain"
        thread.stackSize = 128 * 1024
        thread.start()
    }

    // MARK: - Delivery

    private func drain(readDescriptor: Int32) {
        var byte: UInt8 = 0
        // A blocking read on a pipe we own for the process's lifetime. It returns only on a signal,
        // on close, or on end-of-file.
        while read(readDescriptor, &byte, 1) == 1 {
            let signal = Int32(byte)
            if signal == SIGWINCH {
                onResize()
            } else {
                onShutdown(signal)
            }
        }
    }

    // MARK: - The async-signal-safe side

    /// The write end of the pipe. A C function pointer cannot capture, so this is process-global and
    /// guarded by a `Mutex` rather than by an actor — a lock may be taken in a signal handler, and
    /// `Mutex` is the one lock here that is.
    private static let descriptors = Mutex<(read: Int32, write: Int32)?>(nil)

    private static let trampoline: @convention(c) (Int32) -> Void = { signal in
        guard let pipe = descriptors.withLock({ $0 }) else { return }
        let descriptor = pipe.write
        // SAFETY: `write` is async-signal-safe, the descriptor is owned for the process's lifetime,
        // and one byte cannot tear. Nothing here allocates, locks anything else, or calls Swift.
        var byte = UInt8(truncatingIfNeeded: signal)
        _ = withUnsafeBytes(of: &byte) { raw in
            Darwin.write(descriptor, raw.baseAddress, 1)
        }
    }

    private static func install(signal: Int32) {
        var action = sigaction()
        action.__sigaction_u.__sa_handler = trampoline
        sigemptyset(&action.sa_mask)
        // No SA_RESTART: a blocked `read` should return EINTR so the program can notice.
        action.sa_flags = 0
        // SAFETY: `action` is fully initialised above. Called unqualified because `Darwin.sigaction`
        // resolves to the struct's memberwise initialiser rather than the function.
        _ = sigaction(signal, &action, nil)
    }

    private static func claimWriteDescriptor(_ pipe: (read: Int32, write: Int32)) -> Bool {
        descriptors.withLock { current in
            guard current == nil else { return false }
            current = pipe
            return true
        }
    }

    /// Stops delivery: closes the pipe, restores the default disposition, and releases the descriptor.
    ///
    /// The drain thread ends because its read descriptor closes; it is not joined, because it is parked
    /// in `read` and returns as soon as the close is observed. Safe to call when nothing is running.
    public func stop() {
        guard
            let pipe = Self.descriptors.withLock({ current in
                defer { current = nil }
                return current
            })
        else { return }
        Self.restore(signal: SIGWINCH)
        Self.restore(signal: SIGINT)
        Self.restore(signal: SIGTERM)
        _ = Darwin.close(pipe.write)
        _ = Darwin.close(pipe.read)
    }

    private static func restore(signal: Int32) {
        var action = sigaction()
        sigemptyset(&action.sa_mask)
        action.__sigaction_u.__sa_handler = SIG_DFL
        action.sa_flags = 0
        // SAFETY: `action` is fully initialised above.
        _ = sigaction(signal, &action, nil)
    }

    private static func makePipe() -> (read: Int32, write: Int32)? {
        var descriptors: [Int32] = [0, 0]
        // SAFETY: a correctly sized two-element array for `pipe`.
        let result = descriptors.withUnsafeMutableBufferPointer { buffer in
            Darwin.pipe(buffer.baseAddress!)
        }
        return result == 0 ? (descriptors[0], descriptors[1]) : nil
    }
}

/// Why `SignalHandler.start()` refused.
public enum SignalHandlerError: Error, Sendable, Equatable {
    /// `pipe(2)` failed.
    case pipeUnavailable
    /// Another `SignalHandler` already owns the process-global write descriptor.
    case alreadyRunning
}
