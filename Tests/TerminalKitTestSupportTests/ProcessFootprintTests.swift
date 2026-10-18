internal import TerminalKitTestSupport
import Testing

/// The allocation instrument has to be trusted before it can be used to trust anything else.
///
/// A guard that cannot fail is worse than no guard, because it produces green. So the instrument is
/// tested in both directions: it must report **zero** for work that allocates nothing, and it must
/// report **growth** for work that demonstrably allocates. Without the second half, a broken
/// instrument would pass every ceiling in the project by reporting nothing.
///
/// The zero-allocation assertion is **release-only**, and that is not a convenience. Measured: the
/// identical loop grows the footprint in a debug build, because `-Onone` code allocates for its own
/// loop machinery, boxing and optionals that the optimiser removes. Asserting zero there would be
/// asserting something false about a configuration nobody ships — the same mistake as benchmarking a
/// debug build, which this project already forbids.
@Suite("The footprint instrument tells the truth")
struct ProcessFootprintTests {
    @Test func `the kernel reports a footprint at all`() throws {
        // A nil here must be reported as missing, never as a pass.
        try #require(ProcessFootprint.bytes() != nil, "no footprint available on this platform")
    }

    @Test func `work that allocates nothing grows nothing`() throws {
        let grew = try #require(
            ProcessFootprint.growth {
                var total = 0
                for index in 0 ..< 1_000_000 { total &+= index }
                #expect(total >= 0)
            })
        #if DEBUG
            // Deliberately not asserted in debug: -Onone allocates for the loop's own sake.
            _ = grew
        #else
            #expect(grew <= 0, "a body allocating nothing grew the footprint by \(grew) bytes")
        #endif
    }

    @Test func `the instrument detects real growth`() throws {
        // The control. Held in a LOCAL, not a static: swift-testing runs tests in parallel, and a
        // shared mutable static mutated by two of them is a data race — which showed up as a debug
        // abort here before it was fixed. Shared state between tests is banned for a reason.
        let ballast = Ballast()
        let grew = try #require(
            ProcessFootprint.growth {
                ballast.fill(count: 120_000)
            })
        #expect(grew > 0, "12 MB of deliberate garbage was reported as no growth — the instrument is blind")
        ballast.release()
    }
}

/// Retains memory for as long as it is held, so the footprint it occupies cannot be collected while
/// the measurement is being taken.
private final class Ballast {
    private var blocks: [String] = []

    func fill(count: Int) {
        blocks.reserveCapacity(count)
        for _ in 0 ..< count {
            blocks.append(String(repeating: "x", count: 64))
        }
    }

    func release() { blocks.removeAll(keepingCapacity: false) }
}
