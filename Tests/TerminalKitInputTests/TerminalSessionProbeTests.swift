internal import TerminalKitIO
internal import TerminalKitTestSupport
import Testing

@testable import TerminalKitInput

/// Deciding kitty keyboard support without blocking startup (ADR-0014, ADR-0020).
///
/// The session asks `CSI ? u` followed by `CSI c` (primary device attributes) in its entry write and pushes
/// no flags. Every terminal probed answers device attributes, so the order of the replies decides: the
/// keyboard reply first means supported, device attributes alone means not. The replies arrive through the
/// application's input like any other bytes, and the application hands them to `observe(_:)`.
@Suite("Keyboard support is probed without waiting")
struct TerminalSessionProbeTests {
    private let modes = TerminalModes(alternateScreen: true, kittyKeyboardFlags: KittyKeyboardFlags.disambiguate)
    private let keyboardQuery: [UInt8] = Array("\u{1b}[?u\u{1b}[c".utf8)

    private func events(_ text: String) -> [InputEvent] {
        var router = SequenceRouter()
        return router.feedAll(Array(text.utf8))
    }

    private func probing() throws -> (RecordingConnection, TerminalSession) {
        let connection = RecordingConnection()
        let session = TerminalSession(connection: connection, modes: modes, keyboardProtocol: .probe)
        try session.enter()
        return (connection, session)
    }

    @Test func `entering asks the questions and pushes nothing`() throws {
        let (connection, session) = try probing()

        #expect(connection.written.suffix(keyboardQuery.count).elementsEqual(keyboardQuery))
        #expect(TerminalStateModel.after(connection.written).hasNoKeyboardModesPushed)
        #expect(!session.escapeIsUnambiguous)
    }

    @Test func `a keyboard reply before device attributes pushes the flags`() throws {
        let (connection, session) = try probing()

        for event in events("\u{1b}[?0u\u{1b}[?62;52c") { #expect(session.observe(event)) }

        #expect(session.escapeIsUnambiguous)
        #expect(TerminalStateModel.after(connection.written).alternateScreenKeyboardModes == [1])
    }

    @Test func `device attributes alone mean the protocol is unsupported`() throws {
        // Terminal.app's answer, measured: `CSI ? 1 ; 2 c` and no keyboard reply.
        let (connection, session) = try probing()

        for event in events("\u{1b}[?1;2c") { #expect(session.observe(event)) }

        #expect(!session.escapeIsUnambiguous)
        #expect(TerminalStateModel.after(connection.written).hasNoKeyboardModesPushed)
    }

    @Test func `other input is not taken for a reply`() throws {
        let (_, session) = try probing()

        for event in events("a\u{1b}[A") { #expect(!session.observe(event)) }
    }

    @Test func `replies are not consumed when nothing was asked`() throws {
        let connection = RecordingConnection()
        let session = TerminalSession(connection: connection, modes: modes, keyboardProtocol: .unsupported)
        try session.enter()

        for event in events("\u{1b}[?0u") { #expect(!session.observe(event)) }
    }

    @Test func `leaving pops the flags a reply pushed`() throws {
        let (connection, session) = try probing()
        for event in events("\u{1b}[?0u\u{1b}[?62;52c") { _ = session.observe(event) }

        session.leave()

        #expect(TerminalStateModel.after(connection.written).hasNoKeyboardModesPushed)
    }

    @Test func `leaving before any reply pops nothing`() throws {
        // Popping an empty stack does nothing in the protocol, but it would pop a stack another program owns
        // on a terminal whose reply arrives after the program left.
        let (connection, session) = try probing()

        session.leave()

        #expect(!connection.written.windows(ofCount: 4).contains { $0.elementsEqual(Array("\u{1b}[<u".utf8)) })
    }

    @Test func `a reply after leaving pushes nothing`() throws {
        let (connection, session) = try probing()
        session.leave()

        for event in events("\u{1b}[?0u") { _ = session.observe(event) }

        #expect(TerminalStateModel.after(connection.written).hasNoKeyboardModesPushed)
    }
}

extension TerminalStateModel {
    static func after(_ bytes: [UInt8]) -> TerminalStateModel {
        var model = TerminalStateModel()
        model.consume(bytes)
        return model
    }
}

extension Array {
    fileprivate func windows(ofCount count: Int) -> [ArraySlice<Element>] {
        guard self.count >= count else { return [] }
        return (0 ... self.count - count).map { self[$0 ..< $0 + count] }
    }
}
