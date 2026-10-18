internal import AemiTestKit
import Testing

@testable import TerminalKitInput

/// The ceilings describe the optimized router; an unoptimized build allocates where release does not.
private let isDebugBuild: Bool = {
    #if DEBUG
        true
    #else
        false
    #endif
}()

/// The router runs once per terminal read, on the path from a keypress to the screen. An allocation
/// here is paid for every key, so the ceiling for every kind of key is zero. A paste may allocate
/// once: its text becomes a `String` the application receives.
///
/// Aemi's counter counts only the measuring thread (Aemi ADR-0010), so these ceilings hold in the
/// full suite alongside other tests.
@Suite("The input router's hot path does not allocate")
struct SequenceRouterAllocationTests {
    struct Workload: CustomTestStringConvertible, Sendable {
        let name: String
        let read: [UInt8]
        let allowedPerRead: Int
        var testDescription: String { name }
    }

    static let workloads: [Workload] = [
        Workload(
            name: "a 64-byte run of text", read: Array(String(repeating: "typing! ", count: 8).utf8), allowedPerRead: 0),
        Workload(name: "a single keystroke", read: [UInt8(ascii: "a")], allowedPerRead: 0),
        Workload(name: "the Escape key", read: [0x1b], allowedPerRead: 0),
        Workload(name: "an arrow key", read: [0x1b, 0x5b, 0x41], allowedPerRead: 0),
        Workload(name: "a kitty keyboard key", read: Array("\u{1b}[97;5u".utf8), allowedPerRead: 0),
        Workload(name: "an SGR mouse click", read: Array("\u{1b}[<0;10;5M".utf8), allowedPerRead: 0),
        Workload(name: "a two-byte UTF-8 character", read: Array("é".utf8), allowedPerRead: 0),
        Workload(
            name: "a 1 KiB bracketed paste",
            read: Array("\u{1b}[200~".utf8) + Array(repeating: UInt8(ascii: "x"), count: 1024)
                + Array("\u{1b}[201~".utf8),
            allowedPerRead: 1)
    ]

    @Test(.enabled(if: allocationCountingAvailable && !isDebugBuild), arguments: workloads)
    func `routing a terminal read stays within its allocation ceiling`(workload: Workload) throws {
        let reads = 100
        var router = SequenceRouter()
        var events: [InputEvent] = []
        // Warm up: the router's buffers and the event array reach their working capacity.
        for _ in 0 ..< reads { route(workload.read, through: &router, into: &events) }

        let count = try #require(
            minimumAllocations(repeats: 5) {
                for _ in 0 ..< reads { route(workload.read, through: &router, into: &events) }
            })
        #expect(count <= workload.allowedPerRead * reads, "\(reads) reads allocated \(count) times")
        #expect(!events.isEmpty, "the workload produced no event, so it measured nothing")
    }

    /// Routes one read as `InputSource` does: a short read ends any pending Escape.
    private func route(_ read: [UInt8], through router: inout SequenceRouter, into events: inout [InputEvent]) {
        read.withUnsafeBytes { router.feedAll($0, into: &events) }
        router.flushPendingEscape(into: &events)
    }
}
