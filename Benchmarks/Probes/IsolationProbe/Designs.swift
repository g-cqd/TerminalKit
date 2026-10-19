import Darwin
import Dispatch
import Foundation
import Synchronization
import TerminalKitIO
import TerminalKitRender

/// One screen, one way of owning the pipeline. All of them draw the same frames through the same code.
protocol Design: Sendable {
    var name: String { get }
    /// Runs until `deadline`, consuming `channel`, and returns the version of the last event applied.
    func run(channel: Channel, recording: Recording, cost: Cost, deadline: UInt64) async -> Int
}

func apply(_ event: Event, to state: inout ScreenState, _ recording: Recording) {
    state.version += 1
    switch event {
        case .update:
            state.lines += 1
            recording.updateApplied(version: state.version, at: nowNs())
        case .key(let injectedAt):
            state.typed += 1
            recording.keyApplied(version: state.version, injectedAt: injectedAt, appliedAt: nowNs())
    }
}

private func makePipeline() -> RenderPipeline {
    RenderPipeline(connection: DiscardingConnection(size: TerminalSize(columns: 120, rows: 40)), columns: 120, rows: 40)
}

private func draw(_ pipeline: RenderPipeline, _ state: ScreenState, cost: Cost, _ recording: Recording) {
    pipeline.beginFrame()
    compose(state, cost: cost, into: &pipeline.buffer)
    try? pipeline.flush()
    recording.flushed(version: state.version, at: nowNs())
}

/// A. ask today: the loop and the pipeline on the main actor, one frame per event.
struct MainActorPerEvent: Design {
    let name = "A  main actor, frame per event"
    func run(channel: Channel, recording: Recording, cost: Cost, deadline: UInt64) async -> Int {
        await Self.loop(channel, recording, cost, deadline)
    }

    @MainActor private static func loop(_ channel: Channel, _ recording: Recording, _ cost: Cost, _ deadline: UInt64)
        async -> Int
    {
        let pipeline = makePipeline()
        var state = ScreenState()
        while nowNs() < deadline {
            let events = await channel.popAll()
            for event in events {
                apply(event, to: &state, recording)
                draw(pipeline, state, cost: cost, recording)
                if nowNs() >= deadline { return state.version }
            }
        }
        return state.version
    }
}

/// A'. The same, but every event already waiting is applied before one frame.
struct MainActorCoalescing: Design {
    let name = "A' main actor, frame per batch"
    func run(channel: Channel, recording: Recording, cost: Cost, deadline: UInt64) async -> Int {
        await Self.loop(channel, recording, cost, deadline)
    }

    @MainActor private static func loop(_ channel: Channel, _ recording: Recording, _ cost: Cost, _ deadline: UInt64)
        async -> Int
    {
        let pipeline = makePipeline()
        var state = ScreenState()
        while nowNs() < deadline {
            for event in await channel.popAll() { apply(event, to: &state, recording) }
            draw(pipeline, state, cost: cost, recording)
        }
        return state.version
    }
}

/// B. Events are applied off the main actor; a dedicated thread owns the pipeline and draws the latest state,
/// skipping the ones it was too slow for.
struct RenderThread: Design {
    let name = "B  render thread, latest state"

    /// The newest state, and whether the render thread has been told.
    private final class Latest: Sendable {
        private let slot = Mutex<ScreenState?>(nil)
        let wake = DispatchSemaphore(value: 0)

        func publish(_ state: ScreenState) {
            let wasEmpty = slot.withLock { slot -> Bool in
                defer { slot = state }
                return slot == nil
            }
            if wasEmpty { wake.signal() }
        }

        func take() -> ScreenState? {
            slot.withLock { slot in
                defer { slot = nil }
                return slot
            }
        }
    }

    func run(channel: Channel, recording: Recording, cost: Cost, deadline: UInt64) async -> Int {
        let latest = Latest()
        let renderStopped = Latch()
        let eventsDone = Latch.Flag()
        let thread = Thread {
            let pipeline = makePipeline()
            // Until the events have stopped and the last state is shown.
            while true {
                if latest.wake.wait(timeout: .now() + .milliseconds(2)) == .timedOut {
                    if eventsDone.isSet, let state = latest.take() { draw(pipeline, state, cost: cost, recording) }
                    if eventsDone.isSet { break }
                    continue
                }
                guard let state = latest.take() else { continue }
                draw(pipeline, state, cost: cost, recording)
            }
            renderStopped.open()
        }
        thread.name = "render"
        thread.start()
        let version =
            await Task.detached {
                var state = ScreenState()
                while nowNs() < deadline {
                    for event in await channel.popAll() { apply(event, to: &state, recording) }
                    latest.publish(state)
                }
                eventsDone.set()
                return state.version
            }
            .value
        await renderStopped.wait()
        return version
    }
}

/// Opens once, from any thread; waiters resume when it has.
private final class Latch: Sendable {
    /// A flag one thread sets and another reads.
    final class Flag: Sendable {
        private let value = Atomic<Bool>(false)
        func set() { value.store(true, ordering: .releasing) }
        var isSet: Bool { value.load(ordering: .acquiring) }
    }

    private let state = Mutex<(isOpen: Bool, waiter: CheckedContinuation<Void, Never>?)>((false, nil))

    func open() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isOpen = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let opened = state.withLock { state -> Bool in
                if !state.isOpen { state.waiter = continuation }
                return state.isOpen
            }
            if opened { continuation.resume() }
        }
    }
}

/// C. B as the library ships it: a `RenderLoop` owns the pipeline. The frame is timed when it is composed, not
/// when it is flushed, so it reads a few microseconds faster than the others.
struct ShippedRenderLoop: Design {
    let name = "C  RenderLoop (shipped)"

    private struct Composer: FrameComposer {
        let cost: Cost
        let recording: Recording

        mutating func compose(_ state: ScreenState, into pipeline: RenderPipeline) {
            IsolationProbe.compose(state, cost: cost, into: &pipeline.buffer)
            recording.flushed(version: state.version, at: nowNs())
        }
    }

    func run(channel: Channel, recording: Recording, cost: Cost, deadline: UInt64) async -> Int {
        let loop = RenderLoop(
            connection: DiscardingConnection(size: TerminalSize(columns: 120, rows: 40)), columns: 120, rows: 40,
            composer: Composer(cost: cost, recording: recording))
        let version =
            await Task.detached {
                var state = ScreenState()
                while nowNs() < deadline {
                    for event in await channel.popAll() { apply(event, to: &state, recording) }
                    loop.submit(state)
                }
                return state.version
            }
            .value
        await loop.finish()
        return version
    }
}
