internal import Foundation
public import TerminalKitCodecs
public import TerminalKitIO

/// Follows the terminal's own page: asks for its colours, and reads the answers out of the input (ask roadmap 0108, kit roadmap 0021).
///
/// The host sends ``query`` whenever it wants the colours (at start, and again when the system appearance changes), hands every
/// unrecognised input sequence to ``isAnswer(_:)``, and passes the ones that are answers to ``read(_:)``. An answer is never a key, whether
/// or not it completes a page, so the host takes it out of the input stream either way.
public struct PageFollower: Sendable {
    /// The foreground is asked for before the background, so the background's answer completes the page.
    public static let query = OSCPalette.pageQuery

    private var foreground: ColorRGB?

    public init() {}

    /// Whether `bytes` answers a colour query.
    public static func isAnswer(_ bytes: [UInt8]) -> Bool {
        switch OSCPalette.parse(bytes) {
            case .foreground, .background: true
            default: false
        }
    }

    /// The page an answer completes: the background, with the foreground that came before it. Nil for the foreground alone, which is kept
    /// for the background that follows, and for anything else.
    public mutating func read(_ bytes: [UInt8]) -> TerminalPage? {
        switch OSCPalette.parse(bytes) {
            case .foreground(let color):
                foreground = color
                return nil
            case .background(let color):
                return TerminalPage(background: color, foreground: foreground)
            default:
                return nil
        }
    }

    /// Writes ``query`` to `connection` off the caller's task, which a screen's loop never lets wait on a write. The answers arrive as input.
    /// The returned task ends when the write has; a caller may ignore it.
    @discardableResult
    public static func ask(over connection: any TerminalConnection) -> Task<Void, Never> {
        Task.detached { try? connection.write(query) }
    }
}
