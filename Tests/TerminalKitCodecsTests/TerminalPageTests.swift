import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitStyle

/// A page's tints keep the terminal's own contrast (ask roadmap 0108, kit roadmap 0021).
@Suite("A terminal page mixes tints and secondary text from its own colours")
struct TerminalPageTests {
    /// Real profiles: Apple Terminal's Basic in light and dark mode, Solarized both ways, and a light theme with grey text.
    static let pages: [(String, TerminalPage)] = [
        ("Terminal Basic light", .init(background: SIMD3(255, 255, 255), foreground: SIMD3(0, 0, 0))),
        ("Terminal Basic dark", .init(background: SIMD3(30, 30, 30), foreground: SIMD3(255, 255, 255))),
        ("Solarized light", .init(background: SIMD3(253, 246, 227), foreground: SIMD3(101, 123, 131))),
        ("Solarized dark", .init(background: SIMD3(0, 43, 54), foreground: SIMD3(131, 148, 150))),
        ("One Light", .init(background: SIMD3(250, 250, 250), foreground: SIMD3(56, 58, 66)))
    ]

    private func channels(_ color: Color) throws -> SIMD3<Double> {
        guard case .rgb(let r, let g, let b) = color else { throw NotRGB() }
        return SIMD3(Double(r), Double(g), Double(b))
    }

    private struct NotRGB: Error {}

    @Test func `luminance and contrast follow WCAG 2 at the extremes`() {
        #expect(TerminalPage.luminance(.zero) == 0)
        #expect(abs(TerminalPage.luminance(SIMD3(repeating: 255)) - 1) < 1e-9)
        #expect(abs(TerminalPage.contrast(.zero, SIMD3(repeating: 255)) - 21) < 1e-9)
        #expect(TerminalPage.contrast(SIMD3(9, 9, 9), SIMD3(9, 9, 9)) == 1)
    }

    @Test func `a missing foreground is black on a light page and white on a dark one`() {
        #expect(TerminalPage(background: SIMD3(253, 246, 227)).foreground == .zero)
        #expect(TerminalPage(background: SIMD3(0, 43, 54)).foreground == SIMD3(repeating: 255))
        #expect(TerminalPage.light.isLight && !TerminalPage.dark.isLight)
    }

    @Test func `a page is made from the colours a terminal answered with`() {
        let page = TerminalPage(
            background: ColorRGB(r: 255, g: 255, b: 255), foreground: ColorRGB(r: 0, g: 0, b: 0))
        #expect(page == TerminalPage(background: SIMD3(255, 255, 255), foreground: .zero))
        #expect(
            TerminalPage(background: ColorRGB(r: 30, g: 30, b: 30), foreground: nil).foreground == SIMD3(repeating: 255)
        )
    }

    @Test func `a tint is the page moved a share of the way, rounded and clamped`() {
        #expect(TerminalPage.light.tint(toward: .zero, share: 0.5) == .rgb(r: 128, g: 128, b: 128))
        #expect(TerminalPage.light.tint(toward: .zero, share: 0) == .rgb(r: 255, g: 255, b: 255))
        #expect(TerminalPage.dark.tint(toward: SIMD3(repeating: 400), share: 1) == .rgb(r: 255, g: 255, b: 255))
    }

    @Test func `a tint of a few percent keeps most of the page's own contrast`() throws {
        for (name, page) in Self.pages {
            let own = TerminalPage.contrast(page.foreground, page.background)
            let tint = try channels(page.tint(toward: page.foreground, share: 0.06))
            #expect(TerminalPage.contrast(page.foreground, tint) / own >= 0.8, "\(name)")
            #expect(TerminalPage.contrast(tint, page.background) > 1.04, "\(name): visible")
        }
    }

    @Test func `secondary text reads at 4.5:1, or as well as the theme's own text, and differs where the page allows`()
        throws
    {
        for (name, page) in Self.pages {
            let own = TerminalPage.contrast(page.foreground, page.background)
            let grey = page.secondaryText == .default ? page.foreground : try channels(page.secondaryText)
            #expect(TerminalPage.contrast(grey, page.background) >= Swift.min(4.5, own - 0.01), "\(name)")
            if own >= 7 { #expect(page.secondaryText != .default, "\(name): a contrasted page gets a grey") }
        }
        let solarized = TerminalPage(background: SIMD3(0, 43, 54), foreground: SIMD3(131, 148, 150))
        #expect(solarized.secondaryText == .default, "a low-contrast theme keeps its text colour")
    }
}
