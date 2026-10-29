/// A table's cells as its events give them, until it closes: each cell as the pieces of its inlines.
struct TableBuilder {
    let columns: Int
    private(set) var rows: [(isHeader: Bool, cells: [[Piece]])] = []
    /// Each column's alignment: 0 none, 1 left, 2 center, 3 right.
    private(set) var alignments: [Int] = []

    init(columns: Int) { self.columns = columns }

    var isHeaderRow: Bool { rows.last?.isHeader == true }

    mutating func startRow(isHeader: Bool) { rows.append((isHeader, [])) }

    /// The alignment of the cell about to be added, which sets its column's.
    mutating func align(_ payload: Int) {
        let column = rows.last?.cells.count ?? 0
        while alignments.count <= column { alignments.append(0) }
        alignments[column] = payload & 3
    }

    mutating func addCell(_ pieces: [Piece]) {
        guard !rows.isEmpty else { return }
        rows[rows.count - 1].cells.append(pieces)
    }
}
