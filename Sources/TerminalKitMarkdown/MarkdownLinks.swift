/// What a link becomes: a terminal hyperlink (OSC 8) when its target is one the host allows, and its target written after its text when the
/// text could mislead.
///
/// A model's answer is untrusted text, and so are its links (ask roadmap 0065): only an allowed scheme becomes a hyperlink, a target that is not
/// printable ASCII never does (`Style.isSafeLink`), and `[https://bank.example](https://evil.example)` shows where it goes.
public struct MarkdownLinks: Sendable {
    /// When a link's target is written after its text.
    public enum Targets: Sendable, Equatable {
        /// Never: the text alone, styled as a link.
        case never
        /// When the text names a host and the target goes to another one.
        case whenMisleading
        /// When the text is not the target itself.
        case whenDifferent
        /// Always, except for an autolink, whose text is its target.
        case always
    }

    /// When the target is written; `whenMisleading` by default.
    public var targets: Targets
    /// The schemes a target may have to become a hyperlink, lowercase.
    public var schemes: Set<String>
    /// Turns a target the schemes do not allow, such as a path, into a URI the host wants as a hyperlink, or nil for none; nil for no such
    /// mapping. Its result must still be printable ASCII.
    public var resolve: (@Sendable (String) -> String?)?

    /// A policy of `targets`, `schemes` and `resolve`.
    public init(
        targets: Targets = .whenMisleading, schemes: Set<String> = ["http", "https", "mailto"],
        resolve: (@Sendable (String) -> String?)? = nil
    ) {
        self.targets = targets
        self.schemes = schemes
        self.resolve = resolve
    }

    /// The URI a cell of a link to `target` carries, or nil when it is not a hyperlink.
    func uri(for target: String) -> String? {
        let uri: String? = LinkText.scheme(of: target).map { schemes.contains($0) } == true ? target : resolve?(target)
        guard let uri, Self.isPrintableASCII(uri) else { return nil }
        return uri
    }

    /// Whether a link whose text reads `text` shows `target` after it.
    func showsTarget(_ target: String, text: String) -> Bool {
        switch targets {
            case .never: false
            case .always: !target.isEmpty
            case .whenDifferent: !target.isEmpty && text != target && "mailto:" + text != target
            case .whenMisleading:
                if let named = LinkText.host(named: text), let real = LinkText.host(of: target) {
                    named != real
                } else {
                    false
                }
        }
    }

    private static func isPrintableASCII(_ uri: String) -> Bool {
        !uri.isEmpty && uri.utf8.allSatisfy { $0 > 0x20 && $0 < 0x7F }
    }
}
