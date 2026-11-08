extension SequenceRouter {
    /// `ESC [ Z`, back-tab: what Shift+Tab sends where the kitty keyboard protocol is off (xterm, Terminal.app, iTerm2, tmux).
    static let backTab: UInt8 = 0x5A

    /// The key a legacy CSI sequence ending in `terminator` names: the arrows, Home, End, and F1 to F4 as SS3 names them.
    static func csiKeyCode(for terminator: UInt8) -> UInt32? {
        switch terminator {
            case 0x41: FunctionalKeyCode.up
            case 0x42: FunctionalKeyCode.down
            case 0x43: FunctionalKeyCode.right
            case 0x44: FunctionalKeyCode.left
            case 0x46: FunctionalKeyCode.end
            case 0x48: FunctionalKeyCode.home
            default: ss3KeyCode(for: terminator)
        }
    }

    static func csiTildeKeyCode(for parameter: Int) -> UInt32? {
        switch parameter {
            case 2: FunctionalKeyCode.insert
            case 3: FunctionalKeyCode.delete
            case 5: FunctionalKeyCode.pageUp
            case 6: FunctionalKeyCode.pageDown
            default: nil
        }
    }

    static func ss3KeyCode(for terminator: UInt8) -> UInt32? {
        switch terminator {
            case 0x50: FunctionalKeyCode.f1
            case 0x51: FunctionalKeyCode.f2
            case 0x52: FunctionalKeyCode.f3
            case 0x53: FunctionalKeyCode.f4
            default: nil
        }
    }
}
