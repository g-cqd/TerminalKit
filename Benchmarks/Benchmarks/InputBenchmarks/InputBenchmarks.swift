import Benchmark
import BenchmarkSupport
import TerminalKitInput

// Decoding cost per input event, through the router's public entry point.
//
// Each sample decodes a stream of 1,000 events of one kind in one `feedAll` call, and the kilo scaling
// factor reports the time per event: one event alone is close to the clock's own resolution. The public
// entry returns a fresh array, so its growth (about ten reallocations per sample) is in the number; the
// ceilings in SequenceRouterAllocationTests hold the internal path to zero.
private let eventsPerSample = 1_000

private struct Workload {
    let name: String
    let event: [UInt8]
}

private let paste = "\u{1b}[200~" + String(repeating: "pasted text ", count: 85) + "\u{1b}[201~"

private let workloads = [
    Workload(name: "text", event: Array("a".utf8)),
    Workload(name: "escape (arrow key)", event: Array("\u{1b}[A".utf8)),
    Workload(name: "kitty key", event: Array("\u{1b}[97;5u".utf8)),
    Workload(name: "SGR mouse", event: Array("\u{1b}[<0;10;5M".utf8)),
    Workload(name: "1 KiB bracketed paste", event: Array(paste.utf8))
]

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .mallocCountTotal],
        scalingFactor: .kilo,
        maxDuration: .seconds(1),
        maxIterations: 1_000,
        thresholds: Thresholds.perSuite
    )

    for workload in workloads {
        let stream = Array(repeating: workload.event, count: eventsPerSample).flatMap(\.self)
        // A benchmark that decodes something other than what its name says measures nothing.
        var check = SequenceRouter()
        let decoded = check.feedAll(stream).count
        precondition(decoded == eventsPerSample, "\(workload.name): \(decoded) events, not \(eventsPerSample)")

        Benchmark("decode/\(workload.name)") { benchmark in
            var router = SequenceRouter()
            benchmark.startMeasurement()
            blackHole(router.feedAll(stream))
            benchmark.stopMeasurement()
        }
    }
}
