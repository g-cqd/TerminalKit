internal import AemiTestKit
import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitInput

/// The ceilings describe the optimized build; an unoptimized one allocates where release does not.
private let isDebugBuild: Bool = {
    #if DEBUG
        true
    #else
        false
    #endif
}()

/// A mouse report arrives on the path from the pointer to the screen, and a drag sends dozens a second, so (ADR-0016) the ceiling
/// for recognizing one is zero. The map has 120 regions, about what a full screen of blocks and rows offers to point at.
@Suite("Pointer recognition does not allocate")
struct PointerRecognizerAllocationTests {
    struct Workload: CustomTestStringConvertible, Sendable {
        let name: String
        let events: [MouseEvent]
        var testDescription: String { name }
    }

    static let workloads: [Workload] = [
        Workload(
            name: "a click",
            events: [
                MouseEvent(button: .left, row: 20, col: 40, kind: .press),
                MouseEvent(button: .left, row: 20, col: 40, kind: .release)
            ]),
        Workload(
            name: "a drag across the screen",
            events: [
                MouseEvent(button: .left, row: 5, col: 5, kind: .press),
                MouseEvent(button: .left, row: 6, col: 9, kind: .drag),
                MouseEvent(button: .left, row: 9, col: 30, kind: .drag),
                MouseEvent(button: .left, row: 12, col: 60, kind: .drag),
                MouseEvent(button: .left, row: 12, col: 60, kind: .release)
            ]),
        Workload(name: "a wheel step", events: [MouseEvent(button: .scrollDown, row: 20, col: 40, kind: .press)]),
        Workload(name: "motion with no button", events: [MouseEvent(button: .release, row: 20, col: 40, kind: .motion)])
    ]

    @Test(.enabled(if: allocationCountingAvailable && !isDebugBuild), arguments: workloads)
    func `recognizing a report stays within its allocation ceiling`(workload: Workload) throws {
        var regions = RegionMap<Int>()
        for index in 0 ..< 120 {
            regions.add(index, at: CellRect(row: index % 40, col: (index / 40) * 26, rows: 1, cols: 26))
        }
        var recognizer = PointerRecognizer<Int>()
        var emitted = 0
        let now = ContinuousClock.now
        let rounds = 100
        for _ in 0 ..< rounds {
            for event in workload.events { recognizer.handle(event, at: now, in: regions) { _ in emitted += 1 } }
        }
        let count = try #require(
            minimumAllocations(repeats: 5) {
                for _ in 0 ..< rounds {
                    for event in workload.events {
                        recognizer.handle(event, at: now, in: regions) { _ in emitted += 1 }
                    }
                }
            })
        #expect(count == 0, "\(rounds) rounds allocated \(count) times")
        if workload.name != "motion with no button" {
            #expect(emitted > 0, "the workload produced no pointer event, so it measured nothing")
        }
    }

    @Test(.enabled(if: allocationCountingAvailable && !isDebugBuild))
    func `finding the region under a cell allocates nothing and clearing the map reuses its storage`() throws {
        var regions = RegionMap<Int>()
        for index in 0 ..< 120 {
            regions.add(index, at: CellRect(row: index % 40, col: (index / 40) * 26, rows: 1, cols: 26))
        }
        var found = 0
        let count = try #require(
            minimumAllocations(repeats: 5) {
                for row in 0 ..< 40 {
                    for col in stride(from: 0, to: 80, by: 7) where regions.hit(row: row, col: col) != nil {
                        found += 1
                    }
                }
            })
        #expect(count == 0 && found > 0)
        let rebuilt = try #require(
            minimumAllocations(repeats: 5) {
                regions.removeAll()
                for index in 0 ..< 120 {
                    regions.add(index, at: CellRect(row: index % 40, col: (index / 40) * 26, rows: 1, cols: 26))
                }
            })
        #expect(rebuilt == 0, "re-adding 120 regions after removeAll allocated \(rebuilt) times")
    }
}
