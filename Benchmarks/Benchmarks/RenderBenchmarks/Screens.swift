import TerminalKitRender
import TerminalKitStyle

/// A window size, and the two full-width lines the benchmarks alternate between.
///
/// The lines are built once, here: building a `String` inside a measurement measured the benchmark's own
/// allocations (four per full-screen frame) rather than the pipeline's.
struct ScreenSize: Sendable {
    static let all = [
        ScreenSize(columns: 80, rows: 24), ScreenSize(columns: 120, rows: 40), ScreenSize(columns: 300, rows: 80)
    ]

    let columns: Int
    let rows: Int
    /// Two lines that differ in every column, so writing one over the other changes every cell.
    let first: String
    let second: String

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        first = String(String(repeating: "word ", count: columns / 5 + 1).prefix(columns))
        second = String(String(repeating: "WORD_", count: columns / 5 + 1).prefix(columns))
    }

    var label: String { "\(columns)x\(rows)" }

    /// Writes `line` into every row.
    func fill(_ buffer: inout ScreenBuffer, with line: String) {
        for row in 0 ..< rows { buffer.write(line, row: row, col: 0, style: .default) }
    }
}
