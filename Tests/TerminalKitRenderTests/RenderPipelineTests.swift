import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitIO
@testable import TerminalKitRender

@Suite
struct RenderPipelineTests {
    @Test
    @MainActor
    func `Flush writes to connection`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 10, rows: 3)
        pipeline.buffer[0, 0] = Cell(character: "X", style: .default)
        try pipeline.flush()
        #expect(!mock.writtenOutput.isEmpty)
        // Should contain sync markers
        #expect(mock.writtenOutput.starts(with: EscapeSequences.beginSyncUpdate))
    }
}
