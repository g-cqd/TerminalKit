/// Just enough of a terminal to replay a pipeline's output and read back the grid: printing, CUP, DECSTBM,
/// SU, SD, ED 2, and everything else ignored. Written from the VT100 behaviour, not from the encoder, so a
/// frame that scrolls the terminal can be checked against what it should show.
struct ScreenEmulator {
    private(set) var grid: [[Character]]
    private var row = 0
    private var col = 0
    private var top = 0
    private var bottom: Int

    init(columns: Int, rows: Int) {
        grid = Array(repeating: Array(repeating: " ", count: columns), count: rows)
        bottom = rows - 1
    }

    var lines: [String] { grid.map { String($0) } }

    mutating func feed(_ bytes: [UInt8]) {
        var index = 0
        let text = Array(String(decoding: bytes, as: UTF8.self))
        while index < text.count {
            let character = text[index]
            if character == "\u{1B}", index + 1 < text.count, text[index + 1] == "[" {
                index = control(text, from: index + 2)
                continue
            }
            if row < grid.count, col < grid[row].count { grid[row][col] = character }
            col += 1
            index += 1
        }
    }

    private mutating func control(_ text: [Character], from start: Int) -> Int {
        var index = start
        var parameters = ""
        while index < text.count, let ascii = text[index].asciiValue, (0x30 ... 0x3F).contains(ascii) {
            parameters.append(text[index])
            index += 1
        }
        guard index < text.count else { return index }
        let values = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        let first = values.first.flatMap { $0 } ?? 0
        switch text[index] {
            case "H":
                row = max(1, first) - 1
                col = max(1, values.count > 1 ? values[1] ?? 1 : 1) - 1
            case "r" where !parameters.hasPrefix("?"):
                top = parameters.isEmpty ? 0 : max(1, first) - 1
                bottom =
                    parameters.isEmpty ? grid.count - 1 : (values.count > 1 ? values[1] ?? grid.count : grid.count) - 1
                (row, col) = (0, 0)
            case "S": scroll(up: max(1, first))
            case "T": scroll(up: -max(1, first))
            case "J" where first == 2:
                grid = grid.map { $0.map { _ in " " } }
            default: break
        }
        return index + 1
    }

    private mutating func scroll(up count: Int) {
        let blank = Array(repeating: Character(" "), count: grid[0].count)
        for _ in 0 ..< abs(count) {
            if count > 0 {
                grid.remove(at: top)
                grid.insert(blank, at: bottom)
            } else {
                grid.remove(at: bottom)
                grid.insert(blank, at: top)
            }
        }
    }
}
