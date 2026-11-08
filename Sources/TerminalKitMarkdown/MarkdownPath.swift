/// A path a host found in a run of prose (`MarkdownLinks/paths`): the bytes of the run it covers, the text to show in their place, and
/// the URI it opens, or nil to show it without a link.
public struct MarkdownPath: Sendable, Equatable {
    public var bytes: Range<Int>
    public var shown: String
    public var uri: String?

    public init(bytes: Range<Int>, shown: String, uri: String?) {
        self.bytes = bytes
        self.shown = shown
        self.uri = uri
    }
}
