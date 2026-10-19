// Streams lines through the real RenderPipeline with a scroll region, inside a real terminal, so a reader
// outside can check the screen (Scripts/verify-scroll-region.sh, roadmap 0011).
//
//   StreamProbe <marker-file>
//
// Draws a transcript of numbered lines over every row but the last, a status line in the last, then streams
// 25 more lines one frame each, every frame inside synchronised output as the pipeline always writes. Then it
// writes the expected screen to <marker-file> and waits, so the reader sees the final frame.
import Darwin
import TerminalKitIO
import TerminalKitInput
import TerminalKitRender
import TerminalKitStyle

let marker = CommandLine.arguments.dropFirst().first ?? "/tmp/tk-stream-probe.txt"
let connection = POSIXTerminalConnection()
let size = try connection.getSize()
let session = TerminalSession(
    connection: connection, modes: TerminalModes(alternateScreen: true, hiddenCursor: true),
    keyboardProtocol: .unsupported)
try session.enter()

let pipeline = MainActor.assumeIsolated {
    RenderPipeline(connection: connection, columns: size.columns, rows: size.rows)
}
let transcriptRows = size.rows - 1

func line(_ number: Int) -> String {
    String(String(repeating: "line \(number) ", count: size.columns).prefix(size.columns - 1))
}

@MainActor func draw(firstLine first: Int) throws {
    pipeline.beginFrame()
    for row in 0 ..< transcriptRows { pipeline.buffer.write(line(first + row), row: row, col: 0, style: .default) }
    pipeline.buffer.write("STATUS stays put", row: transcriptRows, col: 0, style: Style(inverse: true))
    try pipeline.flush()
}

try MainActor.assumeIsolated {
    pipeline.scrollRegion = 0 ..< transcriptRows
    try draw(firstLine: 0)
    for first in 1 ... 25 {
        try draw(firstLine: first)
        usleep(20_000)
    }
}
let expected = (0 ..< transcriptRows).map { line(25 + $0) } + ["STATUS stays put"]
let file = fopen(marker, "w")
for text in expected { fputs(text + "\n", file) }
fclose(file)
sleep(20)
session.leave()
