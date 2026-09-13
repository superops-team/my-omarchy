import Foundation
import Testing
@testable import MyOmarchy

@Suite("Management view model")
@MainActor
struct ManagementViewModelTests {
    @Test("only commands allowed by the current lifecycle reach the controller")
    func commandForwarding() {
        var performed: [ManagementCommand] = []
        let viewModel = ManagementViewModel { performed.append($0) }
        viewModel.publish(details: ManagementDetails(
            effectiveResourceProfile: VMResourceProfile(
                name: "automatic-v1",
                vcpuCount: 4,
                memoryMiB: 2_560
            )
        ))

        #expect(viewModel.send(.launch))
        #expect(performed == [.launch])

        viewModel.publish(event: .launchRequested(session: UUID()))
        #expect(!viewModel.send(.launch))
        #expect(performed == [.launch])
    }

    @Test("invalid custom resources block launch without discarding the preference")
    func invalidCustomResourcesBlockLaunch() {
        var performed: [ManagementCommand] = []
        let viewModel = ManagementViewModel { performed.append($0) }
        viewModel.publish(details: ManagementDetails(
            resourcePreference: VMResourceProfilePreference(
                selection: .custom,
                customVCPUCount: 12,
                customMemoryMiB: 32_768
            ),
            effectiveResourceProfile: nil
        ))

        #expect(!viewModel.send(.launch))
        #expect(performed.isEmpty)
        #expect(viewModel.details.resourcePreference.customVCPUCount == 12)
        #expect(viewModel.details.resourcePreference.customMemoryMiB == 32_768)
    }
}
