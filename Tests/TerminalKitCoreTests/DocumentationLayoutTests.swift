import Foundation
import Testing

@Suite("Architecture decision records")
struct DocumentationLayoutTests {
    @Test func `decision records exist and declare status`() throws {
        let records = try DocumentationLayout.decisionRecords()
        #expect(!records.isEmpty)
        for record in records {
            #expect(record.declaresStatus, "\(record.url.lastPathComponent) must declare a status")
            #expect(record.titleCount == 1, "\(record.url.lastPathComponent) must contain one record")
        }
    }

    @Test func `no two decision records share a number`() throws {
        let names = try DocumentationLayout.decisionRecords().map(\.url.lastPathComponent)
        #expect(DocumentationLayout.repeatedNumbers(in: names).isEmpty, "repeated ADR numbers")
    }
}
