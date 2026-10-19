// Roadmap 0014: who should own the render pipeline? Three designs, the same frames, under load.
//
//   IsolationProbe [seconds]
//
// Scenarios vary the composer's cost (0.1 ms is ask's; 2 ms stands for a syntax-highlighted or markdown
// transcript), the rate at which streamed lines arrive, and whether the main actor is also busy. A thread
// injects a keystroke every 50 ms. Each run reports how long a keystroke takes to be handled and to be
// shown, how many frames were drawn, and whether the final state reached the screen.
import Darwin
import Foundation

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "2") ?? 2
let designs: [any Design] = [MainActorPerEvent(), MainActorCoalescing(), RenderThread(), ShippedRenderLoop()]

struct Scenario {
    var label: String
    var cost: Cost  // composer microseconds beyond the writes
    var updatesPerSecond: Double
    var mainBusy: Bool
}

let scenarios: [Scenario] = [
    Scenario(label: "idle, cheap composer", cost: Cost(), updatesPerSecond: 0, mainBusy: false),
    Scenario(label: "500 lines/s, cheap composer", cost: Cost(), updatesPerSecond: 500, mainBusy: false),
    Scenario(label: "5000 lines/s, cheap composer", cost: Cost(), updatesPerSecond: 5_000, mainBusy: false),
    Scenario(label: "500 lines/s, 2 ms composer", cost: Cost(base: 2_000), updatesPerSecond: 500, mainBusy: false),
    Scenario(label: "5000 lines/s, 2 ms composer", cost: Cost(base: 2_000), updatesPerSecond: 5_000, mainBusy: false),
    Scenario(
        label: "500 lines/s, cheap composer, main actor 50% busy", cost: Cost(), updatesPerSecond: 500, mainBusy: true),
    Scenario(
        label: "500 lines/s, 2 ms composer, main actor 50% busy", cost: Cost(base: 2_000), updatesPerSecond: 500,
        mainBusy: true),
    Scenario(
        label: "500 lines/s, 0.1 ms composer, a 40 ms frame every 100 lines",
        cost: Cost(base: 100, spike: 40_000, spikeEvery: 100), updatesPerSecond: 500, mainBusy: false)
]

func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    return sorted[Swift.min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
}

func fmt(_ value: Double) -> String { value.isNaN ? "    -" : String(format: "%7.2f", value) }

/// Producers run on threads of their own, so they are never what is being measured.
func startProducers(_ channel: Channel, scenario: Scenario, deadline: UInt64) -> [Thread] {
    var threads: [Thread] = []
    if scenario.updatesPerSecond > 0 {
        let interval = UInt64(1e9 / scenario.updatesPerSecond)
        let thread = Thread {
            var next = nowNs()
            while nowNs() < deadline {
                channel.push(.update)
                next &+= interval
                while nowNs() < next {}
            }
        }
        thread.start()
        threads.append(thread)
    }
    let keys = Thread {
        usleep(100_000)
        while nowNs() < deadline &- 100_000_000 {
            channel.push(.key(injectedAt: nowNs()))
            usleep(50_000)
        }
    }
    keys.start()
    threads.append(keys)
    return threads
}

print("\(seconds) s per run; times in milliseconds\n")
for scenario in scenarios {
    print(scenario.label)
    print(
        "  design                          frames  handled p50   p99  shown p50     p99     max  last-line  cpu ms/s  unread"
    )
    for design in designs {
        let channel = Channel()
        let recording = Recording()
        let deadline = nowNs() &+ UInt64(seconds * 1e9)
        _ = startProducers(channel, scenario: scenario, deadline: deadline)
        let busy: Task<Void, Never>? =
            scenario.mainBusy
            ? Task { @MainActor in
                while nowNs() < deadline {
                    spin(5_000)
                    try? await Task.sleep(for: .milliseconds(5))
                }
            } : nil
        // After the deadline a last event wakes a loop that is still waiting.
        Task.detached {
            while nowNs() < deadline { usleep(2_000) }
            channel.push(.update)
        }
        let cpuBefore = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
        let finalVersion = await design.run(
            channel: channel, recording: recording, cost: scenario.cost, deadline: deadline)
        await busy?.value
        let cpu = Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) &- cpuBefore) / 1e6 / seconds
        let report = recording.report(finalVersion: finalVersion, deadline: deadline)
        let backlog = channel.pending
        print(
            "  \(design.name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(String(format: "%6d", report.frames))"
                + " \(fmt(percentile(report.handlingLatencies, 0.5))) \(fmt(percentile(report.handlingLatencies, 0.99)))"
                + "  \(fmt(percentile(report.displayLatencies, 0.5))) \(fmt(percentile(report.displayLatencies, 0.99)))"
                + " \(fmt(report.displayLatencies.max() ?? .nan))  \(fmt(report.lastUpdateToShown ?? .nan))"
                + "  \(String(format: "%8.0f", cpu))  \(String(format: "%6d", backlog))\(report.finalShown ? "" : "  FINAL NOT SHOWN")"
        )
    }
    print()
}
