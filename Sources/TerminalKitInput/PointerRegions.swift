/// A position in the terminal's grid of cells. **Zero-based**: row 0, column 0 is the top left cell.
///
/// The decoded ``MouseEvent`` is one-based, as the terminal reports it; ``PointerRecognizer`` converts once, so everything
/// the host sees is zero-based.
public struct CellPosition: Sendable, Equatable {
    public var row: Int
    public var col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

/// A rectangle of cells, zero-based, `row` and `col` naming its top left cell.
public struct CellRect: Sendable, Equatable {
    public var row: Int
    public var col: Int
    public var rows: Int
    public var cols: Int

    public init(row: Int, col: Int, rows: Int, cols: Int) {
        self.row = row
        self.col = col
        self.rows = rows
        self.cols = cols
    }

    /// Whether the cell at `row`, `col` is inside the rectangle.
    public func contains(row: Int, col: Int) -> Bool {
        row >= self.row && row < self.row + rows && col >= self.col && col < self.col + cols
    }
}

/// The geometry of the regions, with no knowledge of what they are called.
///
/// It is deliberately not generic. A scan over a generic type is only fast where the generic is specialized, and across a module
/// boundary it often is not (measured: 3 µs for 120 regions unspecialized, 85 ns specialized). The scan lives here, over plain
/// integers, so it is always compiled with the package; ``RegionMap`` only turns the index it finds back into an identity.
struct RegionGeometry: Sendable {
    var rects: [CellRect] = []
    var layers: [Int] = []

    var count: Int { rects.count }

    mutating func removeAll() {
        rects.removeAll(keepingCapacity: true)
        layers.removeAll(keepingCapacity: true)
    }

    mutating func add(_ rect: CellRect, layer: Int) {
        rects.append(rect)
        layers.append(layer)
    }

    /// The index of the region on top at a cell: the highest layer, and among equals the one added last.
    func topmost(row: Int, col: Int) -> Int? {
        var best = -1
        var bestLayer = Int.min
        for index in rects.indices where layers[index] >= bestLayer && rects[index].contains(row: row, col: col) {
            best = index
            bestLayer = layers[index]
        }
        return best >= 0 ? best : nil
    }
}

/// What the host drew where, named by the host's own identity (TerminalKit ADR-0027, roadmap 0016).
///
/// The composer clears the map and adds a region for each thing it draws that can be pointed at, every frame, because what is
/// under the pointer changes with every scroll. A region is **keyed by the host's identity, never by a screen position**, so a
/// thinking block is the same target before and after it moves.
public struct RegionMap<ID: Hashable & Sendable>: Sendable {
    private var geometry = RegionGeometry()
    private var ids: [ID] = []

    public init() {}

    /// The number of regions.
    public var count: Int { ids.count }

    /// Forgets every region, keeping the storage, so a frame that re-adds them allocates nothing.
    public mutating func removeAll() {
        geometry.removeAll()
        ids.removeAll(keepingCapacity: true)
    }

    /// Adds a region. A region with no cells is ignored.
    ///
    /// - Parameters:
    ///   - id: The host's identity for what is drawn there.
    ///   - rect: The cells it covers.
    ///   - layer: Where it sits above others, such as a popup over the transcript. Higher is on top.
    public mutating func add(_ id: ID, at rect: CellRect, layer: Int = 0) {
        guard rect.rows > 0, rect.cols > 0 else { return }
        geometry.add(rect, layer: layer)
        ids.append(id)
    }

    /// The region on top at a cell: the highest layer, and among equals the one added last, so what is drawn later wins.
    ///
    /// - Complexity: O(*n*) in the number of regions, which is the number of things visible at once.
    public func hit(row: Int, col: Int) -> ID? {
        guard let index = geometry.topmost(row: row, col: col) else { return nil }
        return ids[index]
    }
}
