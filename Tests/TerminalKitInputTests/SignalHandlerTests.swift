internal import AemiTestKit
internal import Darwin
internal import Foundation
internal import Testing

@testable import TerminalKitInput

/// The bug this suite exists for.
///
/// `SignalHandler` used to deliver through a `DispatchSource` bound to `.main`. A terminal program
/// blocks its main thread in `read(into:)` waiting for a keystroke, so the main queue never turned,
/// the continuation never yielded, and the process **stopped responding to `SIGTERM` entirely** —
/// worse than having no handler, because it reads as handled.
///
/// Measured: with the old handler wired, a running `ask` was still alive four seconds after a
/// `SIGTERM` and had to be `SIGKILL`ed.
///
/// ## Determinism
///
/// Every wait is event-driven, through Aemi's `AsyncEventProbe`: it ends the instant the handler
/// records the signal. No `Task.sleep`, no `Task.yield`, no polling, no wall-clock assertion.
///
/// `AsyncEventProbe` also takes an injectable clock, and a `TestClock` here would make the wait end
/// *only* on the signal — maximum determinism, and a hang forever if delivery ever broke again. That
/// trade is wrong for an OS signal: a hang in CI is indistinguishable from a busy machine and
/// diagnoses nothing. So the deadline is real and generous, and a broken handler fails with a named
/// `AsyncEventProbeTimeoutError` instead of wedging the suite.
@Suite("Signals reach the handler without a run loop", .serialized)
struct SignalHandlerTests {
    /// A generous real-time deadline, for a reason stated below.
    ///
    /// The wait is event-driven: it ends the instant the handler records, which is microseconds after
    /// the signal. The deadline never fires in practice. It exists so that a *broken* handler fails
    /// with `AsyncEventProbeTimeoutError` — naming the signal it was waiting for — instead of hanging
    /// forever, which is the only failure mode a never-advancing `TestClock` can offer here. A hang
    /// in CI is indistinguishable from a busy machine and diagnoses nothing.
    private static let deadline = Duration.seconds(5)

    private func makeProbe() -> AsyncEventProbe<Int32> { AsyncEventProbe<Int32>() }

    @Test func `SIGINT reaches the shutdown closure with no run loop turning`() async throws {
        let probe = makeProbe()
        let handler = SignalHandler(onResize: {}, onShutdown: { probe.record($0) })
        try handler.start()
        defer { handler.stop() }

        kill(getpid(), SIGINT)

        let events = try await probe.wait(forAtLeast: 1, timeout: Self.deadline)
        #expect(events == [SIGINT])
    }

    @Test func `SIGTERM reaches the shutdown closure with no run loop turning`() async throws {
        let probe = makeProbe()
        let handler = SignalHandler(onResize: {}, onShutdown: { probe.record($0) })
        try handler.start()
        defer { handler.stop() }

        kill(getpid(), SIGTERM)

        let events = try await probe.wait(forAtLeast: 1, timeout: Self.deadline)
        #expect(events == [SIGTERM])
    }

    @Test func `the handler reports which signal fired`() async throws {
        // The identity matters: a handler that restores a terminal and then exits needs the number to
        // produce the shell-conventional `128 + signo` status.
        let probe = makeProbe()
        // `onResize` takes no argument by design — there is only one signal that means resize — so the probe
        // records that constant rather than a received value.
        let handler = SignalHandler(onResize: { probe.record(SIGWINCH) }, onShutdown: { probe.record($0) })
        try handler.start()
        defer { handler.stop() }

        // SIGWINCH first: its default disposition is *ignore*, so it proves delivery is live before
        // anything with a lethal default action is sent at this process.
        kill(getpid(), SIGWINCH)
        _ = try await probe.wait(forAtLeast: 1, timeout: Self.deadline)

        kill(getpid(), SIGTERM)
        let events = try await probe.wait(forAtLeast: 2, timeout: Self.deadline)
        #expect(events == [SIGWINCH, SIGTERM])
    }

    @Test func `SIGWINCH reaches the resize closure`() async throws {
        let arrived = AsyncEventProbe<Int32>()
        let handler = SignalHandler(onResize: { arrived.record(SIGWINCH) }, onShutdown: { _ in })
        try handler.start()
        defer { handler.stop() }

        kill(getpid(), SIGWINCH)

        _ = try await arrived.wait(forAtLeast: 1, timeout: Self.deadline)
    }

    @Test func `a second handler reports a conflict rather than fighting over the pipe`() throws {
        let first = SignalHandler(onResize: {}, onShutdown: { _ in })
        try first.start()
        defer { first.stop() }

        let second = SignalHandler(onResize: {}, onShutdown: { _ in })
        #expect(throws: SignalHandlerError.alreadyRunning) { try second.start() }
    }

    @Test func `stopping releases the pipe so another handler may start`() throws {
        let first = SignalHandler(onResize: {}, onShutdown: { _ in })
        try first.start()
        first.stop()

        let second = SignalHandler(onResize: {}, onShutdown: { _ in })
        try second.start()
        second.stop()
    }
}
