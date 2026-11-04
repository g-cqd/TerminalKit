/// A theme held by reference: a block's writer and its inline collector read the theme's styles and glyphs from one object, not from a copy of the theme (about
/// forty fields, a retain for each) made for every block (roadmap 0206).
final class ThemeBox: Sendable {
    let theme: MarkdownTheme

    init(_ theme: MarkdownTheme) { self.theme = theme }
}
