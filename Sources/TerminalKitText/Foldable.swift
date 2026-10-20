/// What stands in for a folded block: a short line of text that says what is inside.
///
/// A foldable block cannot be made without one (TerminalKit ADR-0027, point 4): folding must never leave nothing in its place, so there
/// is always something to read and a way to unfold it.
public struct FoldPlaceholder: Sendable, Equatable {
    /// The line that stands in for the block, such as `swift, 142 lines` or `image 1280x720`.
    public var text: String
    /// Said at the end of the line when there is room, such as `ctrl+t to expand`. Optional, since a host may show its own.
    public var hint: String?

    public init(text: String, hint: String? = nil) {
        self.text = text
        self.hint = hint
    }
}

/// A block that can be folded to its placeholder.
public struct FoldableBlock<ID: Hashable & Sendable>: Sendable, Equatable {
    public var id: ID
    public var lines: [String]
    /// Required: there is no way to make a foldable block that has nothing to show when folded.
    public var placeholder: FoldPlaceholder

    public init(id: ID, lines: [String], placeholder: FoldPlaceholder) {
        self.id = id
        self.lines = lines
        self.placeholder = placeholder
    }

    /// What the block draws: its lines, or the one placeholder line when folded.
    public func visibleLines(folded: Bool) -> [String] {
        folded ? [placeholder.text] : lines
    }

    /// How many rows the block takes in each state, before any wrapping.
    public func height(folded: Bool) -> Int {
        folded ? 1 : max(1, lines.count)
    }
}

/// Which blocks are folded: a default, and a per-block choice that overrides it.
///
/// Visibility is **per block, with a default** (the shape Pi uses, and the one ask's roadmap 0051 proposes), so one block can be
/// opened without opening all, and a change of the default reaches every block the user has not chosen for.
public struct FoldStore<ID: Hashable & Sendable>: Sendable, Equatable {
    private var choices: [ID: Bool] = [:]

    public init() {}

    /// How many blocks the user has chosen for.
    public var chosenCount: Int { choices.count }

    /// Whether a block is folded: the user's choice if there is one, else the default the host gives for that kind of block.
    public func isFolded(_ id: ID, default defaultFolded: Bool) -> Bool {
        choices[id] ?? defaultFolded
    }

    /// Flips a block from what it is now, and remembers that choice.
    @discardableResult
    public mutating func toggle(_ id: ID, default defaultFolded: Bool) -> Bool {
        let now = !isFolded(id, default: defaultFolded)
        choices[id] = now
        return now
    }

    public mutating func set(_ id: ID, folded: Bool) {
        choices[id] = folded
    }

    /// Forgets the user's choice for a block, so it follows the default again.
    public mutating func clearChoice(for id: ID) {
        choices[id] = nil
    }

    /// Forgets every choice, so everything follows the defaults, such as when the setting that sets them changes.
    public mutating func clearChoices() {
        choices.removeAll(keepingCapacity: true)
    }
}
