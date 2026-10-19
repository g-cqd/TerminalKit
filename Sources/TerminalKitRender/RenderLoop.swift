internal import Dispatch
internal import Foundation
internal import Synchronization
public import TerminalKitIO

/// What a ``RenderLoop`` calls, on its own thread, to draw one state into the pipeline's back buffer.
///
/// The composer sets the cursor (`cursorRow`, `cursorCol`) and scroll region as it likes; the loop flushes.
/// It is `Sendable` so the loop's thread can take it, and it keeps whatever it caches between frames.
public protocol FrameComposer: Sendable {
    /// A value that says everything a frame shows. Snapshots cross from the producer to the render thread.
    associatedtype State: Sendable

    /// Draws `state` into `pipeline.buffer`. Runs on the render thread, once per frame drawn.
    mutating func compose(_ state: State, into pipeline: RenderPipeline)
}

/// Owns a ``RenderPipeline`` on a thread of its own and draws the newest state it is given (roadmap 0014,
/// ADR-0026).
///
/// A producer, such as an event loop handling keys and streamed text, calls ``submit(_:)`` and moves on: it never
/// waits for a frame. If states arrive faster than frames are drawn, the ones in between are skipped, so the
/// screen is always at most one frame behind and a backlog cannot build. Frames are diffs against the last,
/// inside synchronised output, exactly as the pipeline always writes them.
public final class RenderLoop<Composer: FrameComposer>: Sendable {
    private struct Pending {
        var state: Composer.State?
        var size: (columns: Int, rows: Int)?
        var redraw = false
        var finishing = false
        var halting = false
    }

    private let pending = Mutex(Pending())
    private let wake = DispatchSemaphore(value: 0)
    private let stopped = RenderStop()
    private let failureState = Mutex<TerminalError?>(nil)

    /// Starts the render thread.
    ///
    /// - Parameters:
    ///   - connection: where frames are written.
    ///   - columns: the screen's width.
    ///   - rows: the screen's height.
    ///   - composer: draws each state.
    public init(connection: any TerminalConnection, columns: Int, rows: Int, composer: Composer) {
        let thread = Thread { [self] in
            run(connection: connection, columns: columns, rows: rows, composer: composer)
        }
        thread.name = "TerminalKit.render"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 512 * 1024
        thread.start()
    }

    /// Asks for `state` to be drawn. Returns at once. A state still waiting when another arrives is dropped.
    /// Ignored after ``finish()``.
    public func submit(_ state: Composer.State) {
        post { $0.state = state }
    }

    /// Asks for the screen to be `columns` by `rows`: the next frame redraws everything at that size, from the
    /// last state submitted if no newer one comes.
    public func resize(columns: Int, rows: Int) {
        post { $0.size = (columns, rows) }
    }

    /// Asks for the next frame to redraw everything, for a terminal whose screen is in an unknown state.
    public func redraw() {
        post { $0.redraw = true }
    }

    /// Draws the last state submitted, then stops the thread. Returns when it has stopped. Safe to call again.
    public func finish() async {
        post { $0.finishing = true }
        await stopped.wait()
    }

    /// Stops the thread without drawing what is waiting, and returns once it has stopped. A frame already being
    /// drawn completes first. For a path that must write to the terminal next and cannot have a frame
    /// interleave, a shutdown signal's handler: block-free for the caller's event loop, but this call blocks.
    public func halt() {
        beginHalt()
        stopped.waitBlocking()
    }

    /// The half of ``halt()`` that does not block: from here on, nothing waiting is drawn.
    func beginHalt() {
        post(haltsAFinish: true) {
            $0.state = nil
            $0.halting = true
            $0.finishing = true
        }
    }

    /// The write error that ended the loop, or nil while it runs and after a normal finish.
    public var failure: TerminalError? { failureState.withLock { $0 } }

    private func post(haltsAFinish: Bool = false, _ change: (inout Pending) -> Void) {
        let shouldWake = pending.withLock { pending -> Bool in
            // A finishing loop takes nothing more, except a halt, which turns the finish into a stop.
            guard !pending.finishing || haltsAFinish else { return false }
            let wasIdle = pending.state == nil && pending.size == nil && !pending.redraw
            change(&pending)
            return wasIdle || pending.finishing
        }
        if shouldWake { wake.signal() }
    }

    private func run(connection: any TerminalConnection, columns: Int, rows: Int, composer: Composer) {
        var composer = composer
        let pipeline = RenderPipeline(connection: connection, columns: columns, rows: rows)
        var lastState: Composer.State?
        defer { stopped.open() }
        while true {
            wake.wait()
            let work = pending.withLock { pending -> Pending in
                defer {
                    let finishing = pending.finishing
                    pending = Pending()
                    pending.finishing = finishing
                }
                return pending
            }
            if work.halting { return }
            var full = work.redraw
            if let size = work.size {
                pipeline.resize(columns: size.columns, rows: size.rows)
                full = true
            }
            if let state = work.state ?? (full ? lastState : nil) {
                lastState = state
                pipeline.beginFrame()
                composer.compose(state, into: pipeline)
                do {
                    if full { try pipeline.forceRedraw() } else { try pipeline.flush() }
                } catch {
                    failureState.withLock { $0 = error }
                    return
                }
            }
            if work.finishing { return }
        }
    }
}

/// Opens once, from the render thread; waiters resume when it has.
private final class RenderStop: Sendable {
    private let state = Mutex<(isOpen: Bool, waiters: [CheckedContinuation<Void, Never>])>((false, []))
    private let gate = DispatchSemaphore(value: 0)

    /// Blocks the calling thread until the loop has stopped. Not for async code.
    func waitBlocking() {
        gate.wait()
        gate.signal()  // so any later waiter passes too
    }

    func open() {
        gate.signal()
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let opened = state.withLock { state -> Bool in
                if !state.isOpen { state.waiters.append(continuation) }
                return state.isOpen
            }
            if opened { continuation.resume() }
        }
    }
}
