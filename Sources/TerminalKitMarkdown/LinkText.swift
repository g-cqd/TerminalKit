/// Reading hosts and schemes out of link texts and targets, for ``MarkdownLinks``.
enum LinkText {
    /// The lowercase scheme `target` starts with (`https` in `https://…`, `mailto` in `mailto:…`), or nil.
    static func scheme(of target: String) -> String? {
        guard let colon = target.firstIndex(of: ":"), colon > target.startIndex else { return nil }
        let scheme = target[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
            scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") })
        else { return nil }
        return scheme.lowercased()
    }

    /// The host of a target with an authority (`https://host/…`), lowercase and without a leading `www.`, or nil.
    static func host(of target: String) -> String? {
        guard let rest = after(schemeSeparatorIn: target[...]) else { return nil }
        return host(in: rest)
    }

    /// The host a link's text names: the whole text is a URL, or a domain such as `www.example.com` or `example.com/path`. Nil for prose.
    static func host(named text: String) -> String? {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if let rest = after(schemeSeparatorIn: text[...]) { return host(in: rest) }
        guard let host = host(in: text[...]), host.contains("."), host.last?.isLetter == true else { return nil }
        return host
    }

    /// What follows the first `://` in `text`, or nil.
    private static func after(schemeSeparatorIn text: Substring) -> Substring? {
        var index = text.startIndex
        while let colon = text[index...].firstIndex(of: ":") {
            let rest = text[text.index(after: colon)...]
            if rest.hasPrefix("//") { return rest.dropFirst(2) }
            index = text.index(after: colon)
        }
        return nil
    }

    private static func host(in rest: Substring) -> String? {
        var host = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" }
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        var lower = host.lowercased()
        if lower.hasPrefix("www.") { lower.removeFirst(4) }
        return lower.isEmpty ? nil : lower
    }
}
