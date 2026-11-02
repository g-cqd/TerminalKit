import TerminalKitTestSupport
import Testing

@testable import TerminalKitInput

/// Motion reports with no button held (`?1003`), for hover: asked for only with the mouse, and left off by default.
@Suite("Mouse motion is reported only when asked for, and turned off on the way out")
struct TerminalSessionMotionTests {
    private func model(after bytes: [UInt8]) -> TerminalStateModel {
        var model = TerminalStateModel()
        model.consume(bytes)
        return model
    }

    @Test func `with mouse and motion, entering turns on 1003, and leaving turns it off`() throws {
        let connection = RecordingConnection()
        let session = TerminalSession(
            connection: connection,
            modes: TerminalModes(mouse: true, mouseMotion: true),
            keyboardProtocol: .unsupported
        )
        try session.enter()
        #expect(model(after: connection.written).enabledPrivateModes.isSuperset(of: [1000, 1002, 1003, 1006]))
        session.leave()
        #expect(model(after: connection.written).hasNoPrivateModesEnabled)
    }

    @Test func `motion without the mouse, or the mouse alone, asks for no motion`() throws {
        for modes in [TerminalModes(mouseMotion: true), TerminalModes(mouse: true)] {
            let connection = RecordingConnection()
            try TerminalSession(connection: connection, modes: modes, keyboardProtocol: .unsupported).enter()
            #expect(!model(after: connection.written).enabledPrivateModes.contains(1003))
        }
    }
}
