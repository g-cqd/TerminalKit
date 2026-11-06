import Testing

@testable import TerminalKitInput

/// A terminal's APC reply (`ESC _ … ESC \`), such as kitty's answer to a graphics query (`ESC _ G i=31;OK ESC \`), arrives whole as
/// one unknown event, as an OSC reply does. Read as keys, `ESC _` was Alt+_ and the rest was typed into the input.
@Suite("An APC reply is read whole, never as keys")
struct SequenceRouterAPCTests {
    /// The bytes of each event that is an unknown sequence; nil for any other event.
    private func unknowns(_ events: [InputEvent]) -> [[UInt8]?] {
        events.map { event in
            if case .unknown(let bytes) = event { return bytes }
            return nil
        }
    }

    @Test func `kitty's answer to a graphics query is one unknown event`() {
        var router = SequenceRouter()
        let reply = Array("\u{1B}_Gi=31;OK\u{1B}\\".utf8)
        #expect(unknowns(router.feedAll(reply)) == [reply])
    }

    @Test func `an error answer, and one cut across two reads, are whole too`() {
        var router = SequenceRouter()
        let reply = Array("\u{1B}_Gi=31;ENOTSUPPORTED:no\u{1B}\\".utf8)
        let first = router.feedAll(Array(reply.prefix(9)))
        let second = router.feedAll(Array(reply.dropFirst(9)))
        #expect(first.isEmpty)
        #expect(unknowns(second) == [reply])
    }

    @Test func `keys after the reply are keys again`() {
        var router = SequenceRouter()
        let events = router.feedAll(Array("\u{1B}_Gi=1;OK\u{1B}\\a".utf8))
        #expect(events.count == 2)
        #expect(unknowns(events).first == Array("\u{1B}_Gi=1;OK\u{1B}\\".utf8))
        #expect(unknowns(events).last == .some(nil), "the a is a key")
    }
}
