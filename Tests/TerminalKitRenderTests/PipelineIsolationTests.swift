internal import Foundation
import TerminalKitIO
import TerminalKitStyle
import Testing

@testable import TerminalKitRender

/// Roadmap 0014: the pipeline belongs to no actor. Whoever owns it, a dedicated thread or an actor of the
/// app's own, may build it, draw into it and flush it; it is not `Sendable`, so it cannot be shared.
@Suite("The render pipeline is not tied to the main actor")
struct PipelineIsolationTests {
    @Test func `a pipeline is built and flushed on a plain thread`() {
        let connection = MockTerminalConnection()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let pipeline = RenderPipeline(connection: connection, columns: 10, rows: 2)
            pipeline.beginFrame()
            pipeline.buffer.write("off main", row: 0, col: 0, style: .default)
            try? pipeline.flush()
            done.signal()
        }
        thread.start()
        done.wait()

        #expect(String(decoding: connection.writtenOutput, as: UTF8.self).contains("off main"))
    }

    @Test func `a pipeline is owned by an actor of the app's own`() async throws {
        actor Renderer {
            private let pipeline: RenderPipeline

            init(connection: MockTerminalConnection) {
                pipeline = RenderPipeline(connection: connection, columns: 10, rows: 2)
            }

            func draw(_ text: String) throws {
                pipeline.beginFrame()
                pipeline.buffer.write(text, row: 1, col: 0, style: .default)
                try pipeline.flush()
            }
        }
        let connection = MockTerminalConnection()

        try await Renderer(connection: connection).draw("in actor")

        #expect(String(decoding: connection.writtenOutput, as: UTF8.self).contains("in actor"))
    }
}
