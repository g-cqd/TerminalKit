/// A terminal's answer to the keyboard query a ``TerminalSession`` sends when probing.
///
/// The router delivers both answers as ``InputEvent/unknown(_:)``, since they are private control sequences
/// it has no key for.
enum ProbeReply: Equatable {
    /// `CSI ? flags u`: the terminal speaks the kitty keyboard protocol.
    case keyboardFlags
    /// `CSI ? … c`: primary device attributes, which every probed terminal answers, after any keyboard reply.
    case deviceAttributes

    /// `CSI ? u` then `CSI c`: the keyboard flags, then the primary device attributes as a sentinel.
    static let query: [UInt8] = [0x1B, 0x5B, 0x3F, 0x75, 0x1B, 0x5B, 0x63]

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= 4, bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x3F,
            bytes[3 ..< bytes.count - 1].allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x3B })
        else { return nil }
        switch bytes[bytes.count - 1] {
            case 0x75: self = .keyboardFlags
            case 0x63: self = .deviceAttributes
            default: return nil
        }
    }
}
