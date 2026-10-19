internal import TerminalKitIO
internal import TerminalKitTestSupport
import Testing

@testable import TerminalKitInput

/// Roadmap 0010: the modes a program runs in are entered in one write and left in one write, and the
/// terminal model (an independent reading of the sequences) agrees that leaving restores every one.
@Suite("Terminal modes are entered and left as a unit")
struct TerminalSessionTests {
    private let everything = TerminalModes(
        alternateScreen: true, hiddenCursor: true, bracketedPaste: true, focusEvents: true, mouse: true,
        kittyKeyboardFlags: KittyKeyboardFlags.disambiguate)

    private func model(after bytes: [UInt8]) -> TerminalStateModel {
        var model = TerminalStateModel()
        model.consume(bytes)
        return model
    }

    @Test func `entering takes raw mode, then one write`() throws {
        let connection = RecordingConnection()
        let session = TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: true)

        try session.enter()

        #expect(connection.calls.first == .enterRawMode)
        #expect(connection.writeCount == 1)
    }

    @Test func `entering puts the terminal in every requested mode`() throws {
        let connection = RecordingConnection()
        try TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: true).enter()

        let terminal = model(after: connection.written)
        #expect(terminal.isAlternateScreen)
        #expect(terminal.isBracketedPasteEnabled)
        #expect(terminal.enabledPrivateModes.isSuperset(of: [1000, 1002, 1004, 1006]))
        #expect(!terminal.isCursorVisible)
        #expect(terminal.alternateScreenKeyboardModes == [1])
    }

    @Test func `leaving returns the terminal to its defaults in one write`() throws {
        let connection = RecordingConnection()
        let session = TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: true)
        try session.enter()

        session.leave()

        let terminal = model(after: connection.written)
        #expect(terminal.hasNoPrivateModesEnabled, "left on: \(terminal.enabledPrivateModes)")
        #expect(terminal.isCursorVisible)
        #expect(terminal.hasNoKeyboardModesPushed)
        #expect(terminal.isAtDefaultGraphicRendition)
        #expect(connection.writeCount == 2)
        #expect(connection.calls.last == .restoreMode)
    }

    @Test func `the keyboard flags are popped on the screen they were pushed on`() throws {
        // One stack per screen: popping after leaving the alternate screen would pop the main screen's
        // stack, which this program never pushed, and leave its own entry behind for the next program.
        let connection = RecordingConnection()
        let session = TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: true)
        try session.enter()

        session.leave()

        let terminal = model(after: connection.written)
        #expect(terminal.alternateScreenKeyboardModes.isEmpty)
        #expect(terminal.mainScreenKeyboardModes.isEmpty)
    }

    @Test func `leaving ends a synchronized update the program left open`() throws {
        let connection = RecordingConnection()
        let session = TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: true)
        try session.enter()
        try connection.write(Array("\u{1b}[?2026h".utf8))  // a frame that never finished

        session.leave()

        #expect(!model(after: connection.written).enabledPrivateModes.contains(2026))
    }

    @Test func `leaving twice writes and restores once`() throws {
        // The signal path and the normal path can both ask; the terminal must see one exit.
        let connection = RecordingConnection()
        let session = TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: true)
        try session.enter()

        session.leave()
        session.leave()

        #expect(connection.writeCount == 2)
        #expect(connection.calls.filter { $0 == .restoreMode }.count == 1)
    }

    @Test func `leaving a session that never entered touches nothing`() {
        let connection = RecordingConnection()
        TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: true).leave()

        #expect(connection.calls.isEmpty)
    }

    @Test func `a terminal without the keyboard protocol is sent no keyboard flags`() throws {
        let connection = RecordingConnection()
        let session = TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: false)

        try session.enter()

        #expect(model(after: connection.written).hasNoKeyboardModesPushed)
        #expect(session.modes.kittyKeyboardFlags == 0)
        #expect(!session.escapeIsUnambiguous)
    }

    @Test func `Escape is unambiguous only when disambiguation was pushed`() {
        let pushed = TerminalSession(
            connection: RecordingConnection(), modes: everything, keyboardProtocolSupported: true)
        let legacy = TerminalSession(
            connection: RecordingConnection(), modes: TerminalModes(alternateScreen: true),
            keyboardProtocolSupported: true)

        #expect(pushed.escapeIsUnambiguous)
        #expect(!legacy.escapeIsUnambiguous)
    }

    @Test func `a failed entry leaves raw mode again`() {
        let connection = RecordingConnection(failWrites: true)
        let session = TerminalSession(connection: connection, modes: everything, keyboardProtocolSupported: true)

        #expect(throws: TerminalError.writeFailed(5)) { try session.enter() }
        #expect(connection.calls.last == .restoreMode)
    }

    @Test func `run leaves every mode when its body returns`() async throws {
        let connection = RecordingConnection()

        let value = try await TerminalSession.run(on: connection, modes: everything, keyboardProtocolSupported: true) {
            _ in 42
        }

        #expect(value == 42)
        #expect(model(after: connection.written).hasNoPrivateModesEnabled)
        #expect(connection.calls.last == .restoreMode)
    }

    @Test func `run leaves every mode when its body throws`() async {
        struct Failure: Error {}
        let connection = RecordingConnection()

        await #expect(throws: Failure.self) {
            try await TerminalSession.run(on: connection, modes: everything, keyboardProtocolSupported: true) { _ in
                throw Failure()
            }
        }

        let terminal = model(after: connection.written)
        #expect(terminal.hasNoPrivateModesEnabled)
        #expect(terminal.hasNoKeyboardModesPushed)
        #expect(connection.calls.last == .restoreMode)
    }
}
