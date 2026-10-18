internal import AemiTestKit
import Foundation
internal import TerminalKitCodecs
import Testing

/// The decoder is on the input hot path: one call per keystroke byte, on the thread that must
/// respond before the user sees anything. An allocation here is an allocation per keystroke, so the
/// budget is not "a few" but zero.
///
/// ## Why this test is opt-in
///
/// Aemi's counter observes the thread that opened the window, but a thread that *starts* inside it
/// can still contribute. Measured: in isolation this test observes 0 allocations, and inside the
/// full suite — where other suites run in parallel — it observes about 101 per 1,000 keystrokes, all
/// of them other tests' allocations. A ceiling judged against that number would be a ceiling on the
/// test runner, not on the decoder.
///
/// So the measurement only means something in a quiet process. This test is therefore opt-in through
/// `TERMINALKIT_ALLOC=1`, and CI runs it in a job of its own so nothing else is in that process.
/// The alternative — a limit generous enough to absorb the noise — would not catch the regression
/// this test exists to catch.
///
/// Missing instrumentation fails the test rather than passing it: `try #require` throws when the
/// counter is unavailable, so an unmeasurable platform is a red build, never a green one.
@Suite("The decoder's hot path does not allocate", .serialized)
struct KeyboardDecoderAllocationTests {
    /// A keystroke is one byte fed to a decoder in its ground state.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TERMINALKIT_ALLOC"] == "1"))
    func `decoding plain keystrokes does not allocate`() throws {
        var decoder = KeyboardDecoder()
        // Warm up so one-time lazy initialisation is not counted as the hot path's cost.
        for _ in 0 ..< 1_000 { _ = decoder.feed(UInt8(ascii: "a")) }

        let count = try #require(
            minimumAllocations(repeats: 5) {
                for _ in 0 ..< 1_000 { _ = decoder.feed(UInt8(ascii: "a")) }
            })
        #expect(count == 0, "1,000 keystrokes allocated \(count) times")
    }

    /// The control: the instrument must SEE an allocation, or every ceiling here is decorative.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TERMINALKIT_ALLOC"] == "1"))
    func `the instrument detects an allocation in the same configuration`() throws {
        var ballast: [String] = []
        for _ in 0 ..< 100 { ballast.append(String(repeating: "x", count: 64)) }
        ballast.removeAll()

        let count = try #require(
            minimumAllocations(repeats: 5) {
                for _ in 0 ..< 100 { ballast.append(String(repeating: "x", count: 64)) }
            })
        #expect(count >= 100, "the instrument reported \(count) allocations for 100 strings")
    }
}
