internal import Synchronization
import TerminalKitStyle

/// Every style any screen buffer has stored, numbered, for the whole process (ADR-0021).
///
/// One table for every buffer, so cells in a front and a back buffer compare by id. Ids are never reused: a
/// style keeps its number for the life of the process. Measured in practice, ask draws six styles and
/// KittyCode's colour scheme names about sixty, so the table stays small; a program that generates styles
/// without bound grows it without bound, by about one `Style` and one dictionary entry each.
///
/// Writes look a style up once per `write` call (and a buffer remembers its last one); the diff looks one up
/// only where the style changes between emitted cells.
enum StyleTable {
    private struct Storage {
        var ids: [Style: UInt32] = [.default: 0]
        var styles: [Style] = [.default]
    }

    private static let storage = Mutex(Storage())

    /// The id of `style`, numbering it if it is new. The default style is always 0.
    static func id(of style: Style) -> UInt32 {
        if style == .default { return 0 }
        return storage.withLock { storage in
            if let id = storage.ids[style] { return id }
            let id = UInt32(storage.styles.count)
            storage.styles.append(style)
            storage.ids[style] = id
            return id
        }
    }

    /// The style numbered `id`.
    /// - Precondition: `id` came from ``id(of:)``.
    static func style(_ id: UInt32) -> Style {
        if id == 0 { return .default }
        return storage.withLock { $0.styles[Int(id)] }
    }

    /// How many styles have been numbered, the default included.
    static var count: Int { storage.withLock { $0.styles.count } }
}

/// Graphemes longer than eight UTF-8 bytes, numbered for the whole process, as ``StyleTable`` numbers styles.
///
/// ZWJ emoji sequences mostly; 7 in 189 million graphemes of agent transcripts.
enum GraphemeTable {
    private struct Storage {
        // Keyed by the exact bytes: Character equality is canonical equivalence, which would merge two
        // spellings the terminal may draw differently.
        var ids: [[UInt8]: UInt32] = [:]
        var characters: [Character] = []
    }

    private static let storage = Mutex(Storage())

    static func id(of character: Character) -> UInt32 {
        let key = Array(character.utf8)
        return storage.withLock { storage in
            if let id = storage.ids[key] { return id }
            let id = UInt32(storage.characters.count)
            storage.characters.append(character)
            storage.ids[key] = id
            return id
        }
    }

    static func character(_ id: UInt32) -> Character {
        storage.withLock { $0.characters[Int(id)] }
    }
}
