internal import AemiMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

extension BlockWriter {
    /// A table: its columns as wide as their longest cells when that fits; else each at least as wide as its longest word, sharing what is left
    /// in proportion to what each would take, with cells wrapped inside; else, when even that does not fit, each row as `header: value` rows.
    mutating func emitTable(_ table: TableBuilder) {
        let count = Swift.max(table.columns, table.rows.map(\.cells.count).max() ?? 0)
        guard count > 0, !table.rows.isEmpty else { return }
        let wraps = table.rows.map { row in (0 ..< count).map { RowWrap($0 < row.cells.count ? row.cells[$0] : []) } }
        var natural = [Int](repeating: 0, count: count)
        var least = [Int](repeating: 0, count: count)
        for row in wraps {
            for (column, wrap) in row.enumerated() {
                let measure = wrap.measure
                natural[column] = Swift.max(natural[column], measure.natural)
                least[column] = Swift.max(least[column], measure.longestWord)
            }
        }
        let separator = StyledLine([StyledRun(theme.tableColumnSeparator, style: .default)]).width
        let available = contentWidth - separator * (count - 1)
        if natural.reduce(0, +) <= available {
            emitGrid(table, wraps, widths: natural)
        } else if least.reduce(0, +) <= available {
            emitGrid(table, wraps, widths: Self.share(available, least: least, natural: natural))
        } else {
            emitRecords(table, count: count)
        }
    }

    /// Widths of at least `least` and at most `natural` that add up to `available`, the spare columns shared in proportion to what each
    /// column still wants.
    static func share(_ available: Int, least: [Int], natural: [Int]) -> [Int] {
        let wants = zip(natural, least).map { $0 - $1 }
        let wanted = wants.reduce(0, +)
        let spare = available - least.reduce(0, +)
        guard wanted > 0, spare > 0 else { return least }
        var widths = least.indices.map { least[$0] + Swift.min(wants[$0], spare * wants[$0] / wanted) }
        var left = available - widths.reduce(0, +)
        for column in widths.indices where left > 0 && widths[column] < natural[column] {
            widths[column] += 1
            left -= 1
        }
        return widths
    }

    private mutating func emitGrid(_ table: TableBuilder, _ wraps: [[RowWrap]], widths: [Int]) {
        let separator = StyledRun(theme.tableColumnSeparator, style: theme.tableBorder)
        let separatorWidth = StyledLine([separator]).width
        for (index, row) in wraps.enumerated() {
            let cells = row.enumerated().map { $1.rows(width: Swift.max(1, widths[$0])) }
            for line in 0 ..< (cells.map(\.count).max() ?? 1) {
                var runs: [StyledRun] = []
                for (column, cell) in cells.enumerated() {
                    if column > 0 { runs.append(separator) }
                    let content = line < cell.count ? cell[line] : []
                    let alignment = column < table.alignments.count ? table.alignments[column] : 0
                    runs += Self.padded(content, to: widths[column], alignment: alignment)
                }
                emit(runs)
            }
            guard table.rows[index].isHeader else { continue }
            let junction =
                StyledLine([StyledRun(theme.tableRuleJunction, style: .default)]).width == separatorWidth
                ? theme.tableRuleJunction : String(repeating: theme.tableRuleGlyph, count: separatorWidth)
            let rule = widths.map { String(repeating: theme.tableRuleGlyph, count: $0) }.joined(separator: junction)
            emit([StyledRun(rule, style: theme.tableBorder)])
        }
    }

    /// Each body row as rows of `header: value`, a blank row between records: a table too wide for its words, which a grid would cut.
    private mutating func emitRecords(_ table: TableBuilder, count: Int) {
        let header = table.rows.first { $0.isHeader }?.cells ?? []
        let body = table.rows.filter { !$0.isHeader }
        if body.isEmpty {
            for cell in header { emitWrapped(cell) }
            return
        }
        for (index, row) in body.enumerated() {
            if index > 0 { emitBlank() }
            for column in 0 ..< count {
                var pieces = column < header.count ? header[column] : []
                pieces.append(
                    Piece(text: ": ", style: theme.text.applying(theme.tableHeader), source: nil, isVerbatim: false))
                pieces += column < row.cells.count ? row.cells[column] : []
                emitWrapped(pieces)
            }
        }
    }

    /// `content` with spaces around it to fill `width` columns as `alignment` says (2 centres, 3 aligns right, else left).
    static func padded(_ content: [StyledRun], to width: Int, alignment: Int) -> [StyledRun] {
        let spare = Swift.max(0, width - StyledLine(content).width)
        guard spare > 0 else { return content }
        let before = alignment == 3 ? spare : alignment == 2 ? spare / 2 : 0
        var runs: [StyledRun] = before > 0 ? [spaces(before)] : []
        runs += content
        if spare - before > 0 { runs.append(spaces(spare - before)) }
        return runs
    }
}
