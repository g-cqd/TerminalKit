public import Foundation

public enum DocumentationLayout {
    public struct Record: Sendable, Equatable {
        public var url: URL
        public var text: String

        public var declaresStatus: Bool {
            text.split(separator: "\n", omittingEmptySubsequences: false).contains { $0.hasPrefix("status:") }
        }

        public var titleCount: Int {
            text.split(separator: "\n", omittingEmptySubsequences: false).count { $0.hasPrefix("# ") }
        }
    }

    public static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    public static func decisionRecords() throws -> [Record] {
        let dir = repositoryRoot.appending(path: "docs/adr")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }
            .sorted()
        return try names.map { name in
            let url = dir.appending(path: name)
            return Record(url: url, text: try String(contentsOf: url, encoding: .utf8))
        }
    }

    public static func repeatedNumbers(in names: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for name in names {
            let prefix = String(name.prefix(4))
            if prefix.count == 4, prefix.allSatisfy(\.isNumber) {
                counts[prefix, default: 0] += 1
            }
        }
        return counts.filter { $0.value > 1 }.map(\.key).sorted()
    }
}
