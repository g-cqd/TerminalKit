import Foundation
import TerminalKitStyle

/// The colours of a terminal's page: its background and the colour its text is drawn in, each channel 0 to 255.
///
/// A terminal has no alpha, so "a little off the page" has to be a colour mixed from the page itself. A tint mixed from the terminal's real
/// background, moved a few percent toward its foreground or toward a hue, keeps the contrast the person chose for their terminal, light or
/// dark, where a fixed colour suits only the page it was picked on (ask roadmaps 0074 and 0108, moved here by TerminalKit roadmap 0021).
public struct TerminalPage: Sendable, Equatable {
    public var background: SIMD3<Double>
    public var foreground: SIMD3<Double>

    /// A page of `background` and `foreground`. Without a foreground, the text is taken as black on a light page and white on a dark one.
    public init(background: SIMD3<Double>, foreground: SIMD3<Double>? = nil) {
        self.background = background
        self.foreground = foreground ?? (Self.luminance(background) > 0.4 ? .zero : SIMD3(repeating: 255))
    }

    /// The page a terminal answered with: the background read with OSC 11 and, when it came first, the foreground read with OSC 10.
    public init(background: ColorRGB, foreground: ColorRGB?) {
        self.init(background: Self.channels(background), foreground: foreground.map(Self.channels))
    }

    /// A light page: white, as Apple Terminal's default profile in light mode.
    public static let light = TerminalPage(background: SIMD3(255, 255, 255))
    /// A dark page: Apple Terminal's default profile in dark mode is close to this grey.
    public static let dark = TerminalPage(background: SIMD3(30, 30, 30))

    /// Whether text on this page is dark, which is what makes a page light.
    public var isLight: Bool { Self.luminance(background) > Self.luminance(foreground) }

    /// The page moved `share` (0 to 1) of the way from its background toward `color`, as a colour to draw a block's background in.
    public func tint(toward color: SIMD3<Double>, share: Double) -> Color {
        let value = background + (color - background) * share
        return .rgb(r: Self.byte(value.x), g: Self.byte(value.y), b: Self.byte(value.z))
    }

    /// The colour for secondary text: a grey four fifths of the way from the page to its text, or ``Color/default`` (the text colour
    /// itself) when that grey would read below 4.5:1, as on low-contrast themes such as Solarized.
    public var secondaryText: Color {
        let grey = background + (foreground - background) * 0.8
        return Self.contrast(grey, background) >= 4.5 ? tint(toward: foreground, share: 0.8) : .default
    }

    /// Relative luminance (WCAG 2), 0 for black to 1 for white.
    public static func luminance(_ color: SIMD3<Double>) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = channel / 255
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.x) + 0.7152 * linear(color.y) + 0.0722 * linear(color.z)
    }

    /// The WCAG 2 contrast ratio between two colours, 1 to 21.
    public static func contrast(_ one: SIMD3<Double>, _ other: SIMD3<Double>) -> Double {
        let (a, b) = (luminance(one), luminance(other))
        return (Swift.max(a, b) + 0.05) / (Swift.min(a, b) + 0.05)
    }

    private static func channels(_ color: ColorRGB) -> SIMD3<Double> {
        SIMD3(Double(color.r), Double(color.g), Double(color.b))
    }

    private static func byte(_ value: Double) -> UInt8 { UInt8(Swift.max(0, Swift.min(255, value.rounded()))) }
}
