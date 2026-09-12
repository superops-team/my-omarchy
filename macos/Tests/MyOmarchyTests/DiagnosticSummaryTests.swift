import Testing
@testable import MyOmarchy

@Suite("Safe diagnostic summary")
struct DiagnosticSummaryTests {
    @Test("summary redacts secrets, home paths, and the configured shared folder")
    func redaction() {
        let summary = DiagnosticSummary.make(
            lifecycle: .failed,
            startupStage: .exited,
            rawError: "OPENAI_API_KEY=sk-testsecretvalue1234567890 at /Users/alice/Shared/file.txt",
            homeDirectory: "/Users/alice",
            sharedFolderPath: "/Users/alice/Shared"
        )

        #expect(summary.contains("Lifecycle: failed"))
        #expect(summary.contains("OPENAI_API_KEY=<redacted>"))
        #expect(summary.contains("~/Shared"))
        #expect(!summary.contains("sk-testsecretvalue1234567890"))
        #expect(!summary.contains("/Users/alice"))
    }
}
