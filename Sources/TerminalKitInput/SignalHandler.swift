internal import CTerminalSignals
internal import Darwin
internal import Foundation
internal import Synchronization
internal import TerminalKitIO

/// Delivers resize and shutdown signals on a dedicated thread, even during a blocking terminal read.
///
/// OS signal callbacks run entirely in C: lock-free atomics and a nonblocking pipe write only. Swift
/// callbacks and their synchronization execute on the reader thread, never in the signal context.
/// One process-lifetime reader and two close-on-exec descriptors are reused across start/stop cycles.
public final class SignalHandler: Sendable {
    private let onResize: @Sendable () -> Void
    private let onShutdown: @Sendable (Int32) -> Void
    private static let registry = Mutex(Registry())

    private struct Registry {
        var owner: SignalHandler?
        var generation: UInt32 = 0
        var readerStarted = false
    }

    /// Creates an inactive handler. Call `start()` to install it and `stop()` to release ownership.
    /// - Parameters:
    ///   - onResize: receives SIGWINCH on the reader thread.
    ///   - onShutdown: receives SIGINT or SIGTERM, preserving the signal number.
    public init(
        onResize: @escaping @Sendable () -> Void,
        onShutdown: @escaping @Sendable (Int32) -> Void
    ) {
        self.onResize = onResize
        self.onShutdown = onShutdown
    }

    /// Installs delivery synchronously; signals sent after return are buffered or coalesced.
    /// - Throws: `SignalHandlerError` on ownership conflicts or POSIX setup failure.
    public func start() throws(SignalHandlerError) {
        try Self.registry.withLock { (state: inout Registry) throws(SignalHandlerError) in
            guard state.owner == nil else { throw .alreadyRunning }
            guard state.generation < UInt32.max else { throw .generationExhausted }
            let prepared = tk_signal_prepare()
            guard prepared == 0 else { throw .systemCall(prepared) }
            let generation = state.generation + 1
            let installed = tk_signal_begin(generation)
            guard installed == 0 else { throw .systemCall(installed) }
            state.generation = generation
            state.owner = self
            if !state.readerStarted {
                state.readerStarted = true
                let reader = Thread { Self.drain() }
                reader.name = "TerminalKit.signal-drain"
                reader.stackSize = 128 * 1024
                reader.start()
            }
        }
    }

    /// Stops only this owner's delivery and restores the dispositions saved by `start()`.
    ///
    /// Idempotent. Does not close descriptors under an in-flight OS handler or spawn another reader.
    /// A Swift callback already dispatched before `stop()` may finish afterwards. Callbacks may call
    /// `stop()` themselves: no registry lock is held while invoking them.
    public func stop() {
        let error = Self.registry.withLock { state -> Int32 in
            guard state.owner === self else { return 0 }
            let result = tk_signal_end()
            state.owner = nil
            return result
        }
        if error != 0 {
            TerminalLogger.fault(public: "SignalHandler: failed to restore a signal disposition")
        }
    }

    private static func drain() {
        while true {
            let event = tk_signal_wait()
            guard event.error == 0 else {
                TerminalLogger.fault(public: "SignalHandler: signal pipe read failed")
                return
            }
            let owner = registry.withLock { state -> SignalHandler? in
                guard state.generation == event.generation else { return nil }
                return state.owner
            }
            guard let owner else { continue }
            if event.pending & 4 != 0 { owner.onShutdown(SIGTERM) }
            if event.pending & 2 != 0 { owner.onShutdown(SIGINT) }
            if event.pending & 1 != 0 { owner.onResize() }
        }
    }
}

/// Failure to install signal delivery.
public enum SignalHandlerError: Error, Sendable, Equatable {
    /// Retained for compatibility with callers naming the earlier error.
    case pipeUnavailable
    /// Another handler already owns delivery.
    case alreadyRunning
    /// A POSIX operation failed with this errno.
    case systemCall(Int32)
    /// Generation identifiers cannot be reused while old signals may still be queued.
    case generationExhausted
}
