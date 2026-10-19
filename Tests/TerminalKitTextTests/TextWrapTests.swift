import Testing

@testable import TerminalKitText

@Suite("Text wraps to a display width")
struct TextWrapTests {
    @Test func `text wraps at spaces, and inside a word only when it must`() {
        #expect(TextWrap.lines("the quick brown fox", width: 10) == ["the quick", "brown fox"])
        #expect(TextWrap.lines("abcdefghij", width: 4) == ["abcd", "efgh", "ij"])
        #expect(TextWrap.lines("a\n\nb", width: 10) == ["a", "", "b"])
        #expect(TextWrap.lines("", width: 10) == [""])
    }

    @Test func `a line that is exactly full when a space arrives breaks at that space, gluing nothing`() {
        #expect(TextWrap.lines("one two three four five", width: 10) == ["one two", "three four", "five"])
        #expect(TextWrap.lines("three four five", width: 10) == ["three four", "five"])
    }

    @Test func `wide characters count as two columns`() {
        #expect(TextWrap.lines("日本語テキスト", width: 6) == ["日本語", "テキス", "ト"])
        #expect(TextWrap.lines("ab 日本", width: 4) == ["ab", "日本"])
    }

    @Test func `a wide character that does not fit moves to the next line whole`() {
        #expect(TextWrap.lines("abc日", width: 4) == ["abc", "日"])
    }

    @Test func `tabs become four spaces`() {
        #expect(TextWrap.lines("a\tb", width: 20) == ["a    b"])
    }

    @Test func `a width below one is one`() {
        #expect(TextWrap.lines("abc", width: 0) == ["a", "b", "c"])
        #expect(TextWrap.lines("abc", width: -3) == ["a", "b", "c"])
    }

    @Test func `a grapheme cluster is never split`() {
        // e + combining acute is one column; a ZWJ family is one grapheme.
        #expect(TextWrap.lines("e\u{301}e\u{301}e\u{301}", width: 2) == ["e\u{301}e\u{301}", "e\u{301}"])
    }

    @Test func `spaces are the break and are dropped from the line they end`() {
        #expect(TextWrap.lines("aaaa bbbb", width: 6) == ["aaaa", "bbbb"])
    }
}
