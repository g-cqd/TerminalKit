// UnicodeWidth's answers for the corpus real terminals are asked about (roadmap 0013), and the frames the
// pipeline writes for contested graphemes.
//
//   WidthProbe <corpus>            JSON: grapheme (hex code points) -> UnicodeWidth's columns
//   WidthProbe <corpus> --frames   JSON: grapheme -> hex of the bytes DiffRenderer writes for "<grapheme>Z"
import Foundation
import TerminalKitRender
import TerminalKitStyle
import TerminalKitText

let arguments = Array(CommandLine.arguments.dropFirst())
let path = arguments.first ?? "Scripts/unicode-width-corpus.txt"
let frames = arguments.contains("--frames")
let corpus = try String(contentsOfFile: path, encoding: .utf8)
var result: [String: Any] = [:]
for line in corpus.split(separator: "\n") {
    let hexes = line.split(separator: "#").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    guard !hexes.isEmpty else { continue }
    var text = ""
    for hex in hexes.split(separator: " ") {
        guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else { continue }
        text.unicodeScalars.append(scalar)
    }
    guard let grapheme = text.first, text.count == 1 else {
        result[hexes] = frames ? "" : -1  // not one grapheme in Swift's segmentation
        continue
    }
    if frames {
        var back = ScreenBuffer(columns: 20, rows: 2)
        back.write(String(grapheme) + "Z", row: 1, col: 0, style: .default)
        let bytes = DiffRenderer.render(front: ScreenBuffer(columns: 20, rows: 2), back: back)
        result[hexes] = bytes.map { String(format: "%02x", $0) }.joined()
    } else {
        result[hexes] = UnicodeWidth.displayWidth(of: grapheme)
    }
}
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
