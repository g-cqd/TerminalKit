import Benchmark
import BenchmarkSupport
import TerminalKitText

// Selection (roadmap 0017): a cell to a place in the content on every mouse move of a drag, and the highlight of a whole screen on
// every frame while a selection exists. The screen is 40 rows of 80 columns over 12 blocks, about what a transcript shows.
private struct Content: SelectableContent {
    var blocks: [[String]]
    var blockCount: Int { blocks.count }
    func ordinal(of block: Int) -> Int? { block < blocks.count ? block : nil }
    func blockID(at ordinal: Int) -> Int { ordinal }
    func lineCount(ofBlockAt ordinal: Int) -> Int { blocks[ordinal].count }
    func line(_ line: Int, ofBlockAt ordinal: Int) -> String { blocks[ordinal][line] }
}

private let screenRows = 40
private let plain = "The quick brown fox jumps over the lazy dog, and reads a long answer that wraps at spaces."
private let wide = "日本語のテキストは二列で表示されます。English words too, mixed with 漢字仮名交じり文 here."

private func screen(_ text: String) -> (content: Content, map: RowMap<Int>) {
    let blocks = (0 ..< 12).map { _ in (0 ..< 4).map { _ in String(text.prefix(78)) } }
    var map = RowMap<Int>()
    map.reset(rowCount: screenRows)
    var row = 0
    for (ordinal, lines) in blocks.enumerated() {
        for (line, content) in lines.enumerated() where row < screenRows {
            map.set(
                row: row,
                to: RowProvenance(block: ordinal, ordinal: ordinal, line: line, firstOffset: 0, col: 2, text: content))
            row += 1
        }
        row += 1
    }
    return (Content(blocks: blocks), map)
}

func registerSelectionBenchmarks() {
    let perSample = 1_000
    let scaled = Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal], scalingFactor: .kilo, maxDuration: .seconds(1),
        maxIterations: 1_000, thresholds: Thresholds.perSuite)
    let once = Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal], scalingFactor: .one, maxDuration: .seconds(1),
        maxIterations: 1_000, thresholds: Thresholds.perSuite)

    for (name, text) in [("ASCII", plain), ("CJK", wide)] {
        let (content, map) = screen(text)
        Benchmark("selection/position \(name)", configuration: scaled) { benchmark in
            var found = 0
            benchmark.startMeasurement()
            for index in 0 ..< perSample
            where map.position(row: index % 36, col: 2 + (index * 7) % 76, edge: .trailing) != nil {
                found &+= 1
            }
            benchmark.stopMeasurement()
            // A benchmark that finds nothing measures nothing.
            precondition(found > 0, "no cell mapped to content")
            blackHole(found)
        }

        let selection = ContentSelection(
            anchor: ContentPosition(block: 1, line: 2, offset: 10), head: ContentPosition(block: 9, line: 1, offset: 40)
        )
        precondition(
            !map.highlights(of: selection, in: content).isEmpty, "selection/highlights \(name) highlights nothing")
        Benchmark("selection/highlights \(name), 40 rows", configuration: once) { benchmark in
            benchmark.startMeasurement()
            blackHole(map.highlights(of: selection, in: content))
            benchmark.stopMeasurement()
        }
        Benchmark("selection/text \(name), 8 blocks", configuration: once) { benchmark in
            benchmark.startMeasurement()
            blackHole(selection.text(in: content))
            benchmark.stopMeasurement()
        }
    }
}
