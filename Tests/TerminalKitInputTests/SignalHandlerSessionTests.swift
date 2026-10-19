internal import AemiTestKit
internal import Darwin
internal import TerminalKitIO
internal import TerminalKitTestSupport
internal import Testing

@testable import TerminalKitInput

// In the signal suite's own type, so it runs serialized with the other tests that install the process's
// one signal handler.
extension SignalHandlerTests {
    @Test func `SIGTERM leaves the terminal session from the signal thread`() async throws {
        let connection = RecordingConnection()
        let session = TerminalSession(
            connection: connection, modes: .fullScreen, keyboardProtocol: .supported)
        try session.enter()
        let probe = AsyncEventProbe<Int32>()
        let handler = SignalHandler(
            onResize: {},
            onShutdown: { signal in
                session.leave()
                probe.record(signal)
            })
        try handler.start()
        defer { handler.stop() }

        kill(getpid(), SIGTERM)
        _ = try await probe.wait(forAtLeast: 1, timeout: .seconds(5))
        session.leave()  // the normal path, after the signal path already left

        var terminal = TerminalStateModel()
        terminal.consume(connection.written)
        #expect(terminal.hasNoPrivateModesEnabled)
        #expect(terminal.hasNoKeyboardModesPushed)
        #expect(terminal.isCursorVisible)
        #expect(connection.calls.filter { $0 == .restoreMode }.count == 1)
    }
}
