internal import TerminalKitTestSupport
import Testing

/// The allocation instrument has to be trusted before it can be used to trust anything else.
///
/// What it can and cannot support was measured, and the limits are the interesting part:
///
///   * It reports the **whole process's** footprint. Any other test allocating inside a measurement
///     window is indistinguishable from the code under test allocating. With swift-testing running
///     tests in parallel, an assertion that "this body allocated nothing" failed roughly one run in
///     three, and a proportionality assertion failed every run — both cross-contamination, both
///     about the instrument rather than the body being wrong.
///   * So this suite asserts only what survives that: that a footprint is obtainable, and that real
///     growth is **detected**. Quantitative per-test ceilings need a serial run and are recorded as
///     a manual check rather than dressed up as an automated guarantee.
///
/// This is the same lesson as CAemiTestKitMalloc from the opposite direction: that instrument counts
/// one thread's allocations and misses every other thread; this one sees every thread and so cannot
/// attribute any of it. Neither is broken, and neither supports the guarantee one might assume.
@Suite("The footprint instrument tells the truth")
struct ProcessFootprintTests {
    @Test func `the kernel reports a footprint at all`() throws {
        // A nil here must surface as a missing measurement, never as a pass.
        try #require(ProcessFootprint.bytes() != nil, "no footprint available on this platform")
    }

    @Test func `the instrument detects real growth`() throws {
        // The control, and the only quantitative claim that survives parallel execution: garbage
        // held across the window must show up. The ballast is local to this test because a shared
        // mutable static mutated by two parallel tests is a data race, which aborted the debug build
        // before it was fixed.
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
/// a measurement is being taken.
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
