import Darwin
import Synchronization
import TerminalKitIO
import TerminalKitRender
import TerminalKitStyle

/// Monotonic nanoseconds, cheap enough to call per event.
@inline(__always) func nowNs() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

/// Burns CPU for `microseconds`, as a composer that does real work would.
func spin(_ microseconds: Double) {
    guard microseconds > 0 else { return }
    let end = nowNs() &+ UInt64(microseconds * 1_000)
    while nowNs() < end {}
}

enum Event: Sendable {
    /// A streamed line arrives.
    case update
    /// A keystroke, with the instant it was injected.
    case key(injectedAt: UInt64)
}

/// What the screen shows: a version that every event bumps, and the counts it displays.
struct ScreenState: Sendable {
    var version = 0
    var lines = 0
    var typed = 0
}

/// A queue the consumer awaits and the producers push to, from any thread.
final class Channel: Sendable {
    private struct Inner {
        var items: [Event] = []
        var waiter: CheckedContinuation<[Event], Never>?
    }
    private let inner = Mutex(Inner())

    func push(_ event: Event) {
        let resumption = inner.withLock { inner -> (CheckedContinuation<[Event], Never>, [Event])? in
            inner.items.append(event)
            guard let waiter = inner.waiter else { return nil }
            inner.waiter = nil
            defer { inner.items = [] }
            return (waiter, inner.items)
        }
        resumption?.0.resume(returning: resumption!.1)
    }

    /// Everything pushed since the last call, waiting if nothing has been.
    func popAll() async -> [Event] {
        await withCheckedContinuation { continuation in
            let ready = inner.withLock { inner -> [Event]? in
                if inner.items.isEmpty {
                    inner.waiter = continuation
                    return nil
                }
                defer { inner.items = [] }
                return inner.items
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    /// How many events are queued unprocessed.
    var pending: Int { inner.withLock { $0.items.count } }
}

/// What composing a frame costs beyond the writes, in microseconds: a steady `base`, and `spike` on every
/// `spikeEvery`th version (a markdown table, a long highlighted block).
struct Cost: Sendable {
    var base: Double = 0
    var spike: Double = 0
    var spikeEvery = 0

    func microseconds(for version: Int) -> Double {
        base + (spikeEvery > 0 && version % spikeEvery == 0 ? spike : 0)
    }
}

/// The screen's content for `state`, and a composer that costs `cost` more than the writes do.
func compose(_ state: ScreenState, cost: Cost, into buffer: inout ScreenBuffer) {
    spin(cost.microseconds(for: state.version))
    for row in 0 ..< buffer.rows - 1 {
        buffer.write(
            "streamed line \(state.lines - row) of a long answer that fills the row", row: row, col: 0, style: .default)
    }
    buffer.write("typed \(state.typed) v\(state.version)", row: buffer.rows - 1, col: 0, style: Style(inverse: true))
}

/// What a run measured.
final class Recording: Sendable {
    private struct Inner {
        var keys: [(version: Int, injectedAt: UInt64)] = []
        var flushes: [(version: Int, at: UInt64)] = []
        var handled: [UInt64] = []  // inject-to-applied, nanoseconds
        var lastUpdateAt: UInt64 = 0
        var lastUpdateVersion = 0
    }
    private let inner = Mutex(Inner())

    func keyApplied(version: Int, injectedAt: UInt64, appliedAt: UInt64) {
        inner.withLock {
            $0.keys.append((version, injectedAt))
            $0.handled.append(appliedAt &- injectedAt)
        }
    }
    func updateApplied(version: Int, at: UInt64) {
        inner.withLock {
            $0.lastUpdateAt = at
            $0.lastUpdateVersion = version
        }
    }
    func flushed(version: Int, at: UInt64) { inner.withLock { $0.flushes.append((version, at)) } }

    struct Report {
        var frames: Int
        var displayLatencies: [Double]  // milliseconds, censored at the deadline for keys never shown
        var handlingLatencies: [Double]
        var finalShown: Bool
        var lastUpdateToShown: Double?
    }

    func report(finalVersion: Int, deadline: UInt64) -> Report {
        inner.withLock { inner in
            var display: [Double] = []
            // Flushes arrive in version order, so the first with version >= the key's is a binary search away.
            for key in inner.keys {
                var low = 0
                var high = inner.flushes.count
                while low < high {
                    let middle = (low + high) / 2
                    if inner.flushes[middle].version >= key.version { high = middle } else { low = middle + 1 }
                }
                let shownAt = low < inner.flushes.count ? inner.flushes[low].at : deadline
                display.append(Double(shownAt &- key.injectedAt) / 1e6)
            }
            let final = inner.flushes.last?.version == finalVersion
            var lastToShown: Double?
            if let shown = inner.flushes.first(where: { $0.version >= inner.lastUpdateVersion }) {
                lastToShown = Double(shown.at &- inner.lastUpdateAt) / 1e6
            }
            return Report(
                frames: inner.flushes.count, displayLatencies: display,
                handlingLatencies: inner.handled.map { Double($0) / 1e6 }, finalShown: final,
                lastUpdateToShown: lastToShown)
        }
    }
}
