import Benchmark
import BenchmarkSupport
import TerminalKitCodecs
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

    // Pointer recognition (roadmap 0016): the time per mouse report through the recognizer, with 120 regions on screen, about what
    // a full screen of blocks and rows offers to point at. SequenceRouterAllocationTests' sibling holds the path to zero allocations.
    var regions = RegionMap<Int>()
    for index in 0 ..< 120 {
        regions.add(index, at: CellRect(row: index % 40, col: (index / 40) * 26, rows: 1, cols: 26))
    }
    let pointerWorkloads: [(name: String, events: [MouseEvent])] = [
        (
            "click",
            [
                MouseEvent(button: .left, row: 20, col: 40, kind: .press),
                MouseEvent(button: .left, row: 20, col: 40, kind: .release)
            ]
        ),
        (
            "drag",
            [
                MouseEvent(button: .left, row: 5, col: 5, kind: .press),
                MouseEvent(button: .left, row: 6, col: 9, kind: .drag),
                MouseEvent(button: .left, row: 9, col: 30, kind: .drag),
                MouseEvent(button: .left, row: 12, col: 60, kind: .drag),
                MouseEvent(button: .left, row: 12, col: 60, kind: .release)
            ]
        ),
        ("wheel", [MouseEvent(button: .scrollDown, row: 20, col: 40, kind: .press)])
    ]
    for workload in pointerWorkloads {
        var check = PointerRecognizer<Int>()
        var produced = 0
        for event in workload.events { check.handle(event, at: .now, in: regions) { _ in produced += 1 } }
        // A benchmark that recognizes nothing measures nothing.
        precondition(produced > 0, "pointer/\(workload.name): no pointer event")
        let rounds = eventsPerSample / workload.events.count

        Benchmark("pointer/\(workload.name)") { benchmark in
            var recognizer = PointerRecognizer<Int>()
            var emitted = 0
            let now = ContinuousClock.now
            benchmark.startMeasurement()
            for _ in 0 ..< rounds {
                for event in workload.events { recognizer.handle(event, at: now, in: regions) { _ in emitted &+= 1 } }
            }
            benchmark.stopMeasurement()
            blackHole(emitted)
        }
    }

    Benchmark("regions/hit (120 regions)") { benchmark in
        var found = 0
        benchmark.startMeasurement()
        for index in 0 ..< eventsPerSample where regions.hit(row: index % 40, col: (index * 7) % 80) != nil {
            found &+= 1
        }
        benchmark.stopMeasurement()
        precondition(found > 0, "no cell found a region")
        blackHole(found)
    }
}
