import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitInput

/// The modifier parameter of a legacy CSI key, `ESC [ 1 ; 2 C`, is one-based: 1 is none, 2 is Shift. Reading it as a number that
/// starts at one and has digits appended to it makes `2` into `12`, which is Shift, Alt and Super at once.
@Suite("A CSI key's modifier parameter is read as the number it is")
struct SequenceRouterModifierTests {
    private func key(_ text: String) throws -> KeyEvent {
        var router = SequenceRouter()
        return try requireKeyEvent(router.feedAll(Array(text.utf8)))
    }

    struct Arrow: Sendable {
        let sequence: String
        let keyCode: UInt32
        let modifiers: KeyModifiers
    }

    static let arrows: [Arrow] = [
        Arrow(sequence: "\u{1B}[A", keyCode: Key.up.rawValue, modifiers: []),
        Arrow(sequence: "\u{1B}[1;2A", keyCode: Key.up.rawValue, modifiers: .shift),
        Arrow(sequence: "\u{1B}[1;3D", keyCode: Key.left.rawValue, modifiers: .alt),
        Arrow(sequence: "\u{1B}[1;5C", keyCode: Key.right.rawValue, modifiers: .ctrl),
        Arrow(sequence: "\u{1B}[1;6B", keyCode: Key.down.rawValue, modifiers: [.shift, .ctrl]),
        Arrow(sequence: "\u{1B}[1;9H", keyCode: Key.home.rawValue, modifiers: .super),
        Arrow(sequence: "\u{1B}[1;10F", keyCode: Key.end.rawValue, modifiers: [.shift, .super]),
        Arrow(sequence: "\u{1B}[1;C", keyCode: Key.right.rawValue, modifiers: [])
    ]

    @Test(arguments: arrows)
    func `an arrow carries exactly the modifiers it was sent with`(arrow: Arrow) throws {
        let event = try key(arrow.sequence)
        #expect(event.keyCode == arrow.keyCode)
        #expect(event.modifiers == arrow.modifiers, "\(arrow.sequence.debugDescription)")
    }

    @Test(arguments: [
        ("\u{1B}[3;5~", KeyModifiers.ctrl), ("\u{1B}[5;2~", KeyModifiers.shift), ("\u{1B}[6;3~", KeyModifiers.alt)
    ])
    func `a tilde key does too`(sequence: String, modifiers: KeyModifiers) throws {
        #expect(try key(sequence).modifiers == modifiers, "\(sequence.debugDescription)")
    }

    @Test func `the event type after the modifier is still read`() throws {
        let release = try key("\u{1B}[1;2:3C")
        #expect(release.modifiers == .shift && release.eventType == .release)
        let repeated = try key("\u{1B}[1;5:2A")
        #expect(repeated.modifiers == .ctrl && repeated.eventType == .repeat)
    }
}
