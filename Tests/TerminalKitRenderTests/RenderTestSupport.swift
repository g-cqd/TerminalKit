import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitIO
@testable import TerminalKitRender

func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard needle.count <= haystack.count else { return false }
    for i in 0 ... (haystack.count - needle.count) where Array(haystack[i ..< (i + needle.count)]) == needle {
        return true
    }
    return false
}
