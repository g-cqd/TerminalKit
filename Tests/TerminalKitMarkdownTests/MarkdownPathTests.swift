import TerminalKitStyle
import Testing

@testable import TerminalKitMarkdown

/// A host's paths in prose (ask roadmap 0215): drawn as the host's shorter text over the bytes the author wrote, linked, and left alone in
/// code and in links.
@Suite("Paths in prose are drawn as the host shows them")
struct MarkdownPathTests {
    /// Finds `/repo/Sources/a.swift` and shows it as `Sources/a.swift`, linked.
    private static let links = MarkdownLinks(paths: { text in
        let bytes = Array(text.utf8)
        let needle = Array("/repo/Sources/a.swift".utf8)
        guard
            let start = (0 ... max(0, bytes.count - needle.count)).first(where: { bytes[$0...].starts(with: needle) }),
            bytes.count >= needle.count
        else { return [] }
        return [
            MarkdownPath(bytes: start ..< start + 21, shown: "Sources/a.swift", uri: "file:///repo/Sources/a.swift")
        ]
    })

    @Test func `a path shows the host's text, over the written bytes, with its link`() throws {
        let markdown = "See /repo/Sources/a.swift now."
        #expect(Rendered.rows(markdown, links: Self.links) == ["See Sources/a.swift now."])
        let path = try #require(Rendered.run("Sources/a.swift", in: markdown, links: Self.links))
        #expect(path.source == 4 ..< 25 && path.style.link == "file:///repo/Sources/a.swift")
        #expect(Rendered.run("See ", in: markdown, links: Self.links)?.source == 0 ..< 4)
        #expect(Rendered.run(" now.", in: markdown, links: Self.links)?.source == 25 ..< 30)
    }

    @Test func `code and links keep what was written`() {
        #expect(Rendered.rows("`/repo/Sources/a.swift`", links: Self.links) == ["/repo/Sources/a.swift"])
        #expect(
            Rendered.rows("[/repo/Sources/a.swift](https://x.example)", links: Self.links) == ["/repo/Sources/a.swift"]
        )
    }

    @Test func `without the hook, or with nothing found, prose is as written`() {
        #expect(Rendered.rows("See /repo/Sources/a.swift now.") == ["See /repo/Sources/a.swift now."])
        #expect(Rendered.rows("Nothing here.", links: Self.links) == ["Nothing here."])
    }

    @Test func `a path the host does not link is shown without a link`() throws {
        let plain = MarkdownLinks(paths: { _ in [MarkdownPath(bytes: 0 ..< 2, shown: "x", uri: nil)] })
        let run = try #require(Rendered.run("x", in: "ab cd", links: plain))
        #expect(run.style.link == nil && run.source == 0 ..< 2)
    }
}
