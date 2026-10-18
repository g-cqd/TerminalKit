internal import AemiTestKit
internal import TerminalKitCodecs
import Testing

/// The ceiling describes the optimized decoder; an unoptimized build allocates where release does not.
private let isDebugBuild: Bool = {
    #if DEBUG
        true
    #else
        false
    #endif
}()

/// The decoder is on the input hot path: one call per keystroke byte, on the thread that must
/// respond before the user sees anything. An allocation here is an allocation per keystroke, so the
/// budget is not "a few" but zero.
///
/// Aemi's counter counts only the measuring thread (Aemi ADR-0010). Before that, other suites'
/// threads leaked into the window: this measurement read about 101 per 1,000 keystrokes in the full
/// suite and 0 alone, so it ran opt-in, in a CI job of its own. It now runs in every release suite.
///
/// Missing instrumentation fails the test rather than passing it: `try #require` throws when the
/// counter is unavailable, so an unmeasurable platform is a red build, never a green one.
@Suite("The decoder's hot path does not allocate", .serialized)
struct KeyboardDecoderAllocationTests {
    /// A keystroke is one byte fed to a decoder in its ground state.
    @Test(.disabled(if: isDebugBuild, "the ceiling describes the optimized decoder"))
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
    @Test(.disabled(if: isDebugBuild, "the ceiling describes the optimized decoder"))
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
