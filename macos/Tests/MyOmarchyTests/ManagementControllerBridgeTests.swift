import Foundation
import Testing
@testable import MyOmarchy

@Suite("Management controller bridge")
@MainActor
struct ManagementControllerBridgeTests {
    @Test("controller lifecycle events publish through the shared view model")
    func lifecycleEventsPublish() {
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            managementViewModel: viewModel
        )
        let session = UUID()

        #expect(controller.recordManagementEvent(.launchRequested(session: session)))
        #expect(viewModel.state.lifecycle == .launching)
        #expect(controller.recordManagementEvent(.virtualMachineReady(session: session)))
        #expect(viewModel.state.lifecycle == .running)
        #expect(controller.recordManagementEvent(.childExited(session: session, status: 0)))
        #expect(viewModel.state.lifecycle == .idle)
    }
}
