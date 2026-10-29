internal import TerminalKitStyle

extension Style {
    /// This style with what `overlay` sets: its colours other than `.default`, each attribute it turns on, and its link if it has one.
    func applying(_ overlay: Style) -> Style {
        var style = self
        if overlay.fg != .default { style.fg = overlay.fg }
        if overlay.bg != .default { style.bg = overlay.bg }
        if overlay.underlineColor != .default { style.underlineColor = overlay.underlineColor }
        if overlay.underline != .none { style.underline = overlay.underline }
        style.bold = style.bold || overlay.bold
        style.dim = style.dim || overlay.dim
        style.italic = style.italic || overlay.italic
        style.strikethrough = style.strikethrough || overlay.strikethrough
        style.inverse = style.inverse || overlay.inverse
        if let link = overlay.link { style.link = link }
        return style
    }
}
