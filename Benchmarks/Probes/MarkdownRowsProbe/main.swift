// The cost of laying a Markdown document out as rows (roadmap 0206): every block of each public document of the AemiMarkdown corpus, by size of document, in
// the thread's CPU time, instructions and allocations. The corpus is the cache that AemiMarkdown's Benchmarks/Corpus/fetch.py setup fills.
//
//   MarkdownRowsProbe [--width N] [--rounds N] [--max-bytes N] [--one-block]
import AemiMarkdown
import AemiMetrics
import CAemiTestKitMalloc
import Foundation
import TerminalKitMarkdown

let arguments = CommandLine.arguments
func option(_ name: String) -> String? {
    arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
}
let width = option("--width").flatMap(Int.init) ?? 80
let rounds = option("--rounds").flatMap(Int.init) ?? 5
let maxBytes = option("--max-bytes").flatMap(Int.init) ?? 400_000
let cache =
    ProcessInfo.processInfo.environment["AEMI_MARKDOWN_CORPUS"]
    ?? NSString(string: "~/Library/Caches/AemiMarkdownCorpus").expandingTildeInPath
guard let names = try? FileManager.default.contentsOfDirectory(atPath: cache + "/files"), !names.isEmpty else {
    FileHandle.standardError.write(
        Data("no corpus in \(cache): run Benchmarks/Corpus/fetch.py setup in AemiMarkdown\n".utf8)
    )
    exit(2)
}
var documents: [MarkdownDocument] = []
var sizes: [Int] = []
for name in names.sorted() {
    guard let data = FileManager.default.contents(atPath: cache + "/files/" + name), data.count <= maxBytes else {
        continue
    }
    documents.append(MarkdownParser.parse(Array(data)))
    sizes.append(data.count)
}
let bins: [(String, Range<Int>)] = [
    ("under 2 KB", 0 ..< 2_000), ("2 to 5 KB", 2_000 ..< 5_000), ("5 to 20 KB", 5_000 ..< 20_000),
    ("20 to 100 KB", 20_000 ..< 100_000), ("100 to 400 KB", 100_000 ..< 400_000)
]
var load = [Double](repeating: 0, count: 3)
getloadavg(&load, 3)
print("rows at width \(width): \(documents.count) documents; load average \(String(format: "%.1f", load[0]))")
print("bin             docs        bytes   rows   µs/KB   instr/byte   allocs/KB   µs per doc p50")
var renderer = MarkdownRenderer()
for (name, range) in bins {
    let members = documents.indices.filter { range.contains(sizes[$0]) }
    guard !members.isEmpty else { continue }
    var nanos = 0.0
    var instructions = 0.0
    var bytes = 0
    var rows = 0
    var allocations: UInt64 = 0
    var perDocument: [Double] = []
    for index in members {
        let document = documents[index]
        var best = Double.infinity
        var bestInstructions = 0.0
        for _ in 0 ..< rounds {
            let begin = ProcessProbe.snapshot()
            var count = 0
            for block in document.topLevelBlocks {
                count += renderer.lines(of: block, in: document, width: width).count
            }
            let delta = ProcessProbe.delta(from: begin, to: ProcessProbe.snapshot())
            rows = count
            if Double(delta.threadCPUNanos) < best {
                best = Double(delta.threadCPUNanos)
                bestInstructions = Double(delta.instructions)
            }
        }
        adtk_malloc_count_begin()
        for block in document.topLevelBlocks { _ = renderer.lines(of: block, in: document, width: width) }
        allocations += adtk_malloc_count_end()
        nanos += best
        instructions += bestInstructions
        bytes += sizes[index]
        perDocument.append(best / 1e3)
    }
    perDocument.sort()
    print(
        String(
            format: "%-14@ %5d %12d %6d %7.1f %12.1f %11.1f %12.1f",
            name as NSString,
            members.count,
            bytes,
            rows,
            nanos / 1e3 / (Double(bytes) / 1024),
            instructions / Double(bytes),
            Double(allocations) / (Double(bytes) / 1024),
            perDocument[perDocument.count / 2]
        )
    )
}
