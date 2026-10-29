import TerminalKitStyle
import Testing

@testable import TerminalKitMarkdown

@Suite("Inlines take their styles, and links become hyperlinks only when the policy allows")
struct MarkdownInlineTests {
    @Test func `emphasis, strong, strikethrough and code stack over the block's style`() {
        let theme = MarkdownTheme.standard
        let markdown = "# h *e*\n\n**s *se*** ~~x~~ `c`"
        #expect(Rendered.run("h ", in: markdown, theme: theme)?.style == theme.heading(1))
        #expect(Rendered.run("e", in: markdown, theme: theme)?.style == theme.heading(1).applying(Style(italic: true)))
        #expect(Rendered.run("s ", in: markdown, theme: theme)?.style == Style(bold: true))
        #expect(Rendered.run("se", in: markdown, theme: theme)?.style == Style(bold: true, italic: true))
        #expect(Rendered.run("x", in: markdown, theme: theme)?.style == Style(strikethrough: true))
        #expect(Rendered.run("c", in: markdown, theme: theme)?.style == Style(fg: .indexed(6)))
    }

    @Test func `a run shows its source bytes, and an entity shows its decoded character over the entity's bytes`() {
        let markdown = "ab &amp; cd"
        #expect(Rendered.run("ab ", in: markdown)?.source == 0 ..< 3)
        #expect(Rendered.run("&", in: markdown)?.source == 3 ..< 8)
        #expect(Rendered.run(" cd", in: markdown)?.source == 8 ..< 11)
    }

    @Test func `a link of an allowed scheme is a hyperlink; others are not, unless resolved`() {
        #expect(Rendered.run("site", in: "[site](https://example.com)")?.style.link == "https://example.com")
        #expect(Rendered.run("run", in: "[run](javascript:alert(1))")?.style.link == nil)
        #expect(Rendered.run("file", in: "[file](Sources/a.swift)")?.style.link == nil)
        let resolving = MarkdownLinks(resolve: { "file:///repo/" + $0 })
        #expect(
            Rendered.run("file", in: "[file](Sources/a.swift)", links: resolving)?.style.link
                == "file:///repo/Sources/a.swift")
        let unsafe = MarkdownLinks(resolve: { _ in "file:///a b" })
        #expect(Rendered.run("file", in: "[file](x)", links: unsafe)?.style.link == nil)
    }

    @Test func `a link's target shows after it when its text names another host, or as the policy says`() {
        #expect(
            Rendered.rows("[https://bank.example](https://evil.example/login)") == [
                "https://bank.example (https://evil.example/login)"
            ])
        #expect(Rendered.rows("[www.bank.example](https://bank.example/a)") == ["www.bank.example"])
        #expect(Rendered.rows("[the docs](https://evil.example)") == ["the docs"])
        let different = MarkdownLinks(targets: .whenDifferent)
        #expect(Rendered.rows("[the docs](https://a.example)", links: different) == ["the docs (https://a.example)"])
        #expect(Rendered.rows("[https://a.example](https://a.example)", links: different) == ["https://a.example"])
        let never = MarkdownLinks(targets: .never)
        #expect(Rendered.rows("[https://bank.example](https://evil.example)", links: never) == ["https://bank.example"])
        let target = Rendered.run(
            "https://evil.example/login", in: "[https://bank.example](https://evil.example/login)")
        #expect(target?.source == nil)
    }

    @Test func `an autolink is its own target: a bare www gets http and an address mailto`() {
        #expect(Rendered.run("www.example.com", in: "see www.example.com now")?.style.link == "http://www.example.com")
        #expect(Rendered.run("a@b.example", in: "mail a@b.example now")?.style.link == "mailto:a@b.example")
        #expect(Rendered.run("https://x.example", in: "<https://x.example>")?.style.link == "https://x.example")
        #expect(
            Rendered.rows("see www.example.com now", links: MarkdownLinks(targets: .always)) == [
                "see www.example.com now"
            ])
    }

    @Test func `an image shows its alt text in brackets`() {
        #expect(Rendered.rows("![a cat](cat.png)") == ["[a cat]"])
    }

    @Test func `control characters are not drawn, raw HTML is, and a tab in prose is a space`() {
        let rows = Rendered.rows("a\u{1B}[31mb <b>c</b>\td")
        #expect(rows == ["a[31mb <b>c</b> d"])
        #expect(Rendered.run("<b>", in: "x <b>y", theme: .standard)?.style == Style(dim: true))
    }
}
