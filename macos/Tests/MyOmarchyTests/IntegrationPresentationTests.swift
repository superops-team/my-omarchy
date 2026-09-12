import Testing
@testable import MyOmarchy

@Suite("Integration presentation")
struct IntegrationPresentationTests {
    @Test("shared folder and ports distinguish configuration from running state")
    func configuredState() {
        var details = ManagementDetails()
        details.sharedFolder = SharedFolderMenuState(
            path: "/Users/test/Shared",
            displayPath: "~/Shared",
            isEnabled: true,
            problem: nil
        )
        details.portMappings = [.init(hostPort: 2222, guestPort: 22, protocol: .tcp)]

        let stopped = IntegrationPresentation.make(details: details, lifecycle: .idle)
        #expect(stopped.sharedFolderStatusKey == "integration.status.configured_next_launch")
        #expect(stopped.portStatusKey == "integration.status.configured_next_launch")

        details.activeSharedFolderPath = "/Users/test/Shared"
        details.activePortMappings = details.portMappings
        let running = IntegrationPresentation.make(details: details, lifecycle: .running)
        #expect(running.sharedFolderStatusKey == "integration.status.running")
        #expect(running.portStatusKey == "integration.status.running")

        details.portMappings = [.init(hostPort: 8080, guestPort: 80, protocol: .tcp)]
        let changed = IntegrationPresentation.make(details: details, lifecycle: .running)
        #expect(changed.portStatusKey == "integration.status.configured_next_launch")
    }
}
