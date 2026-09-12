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

        #expect(viewModel.send(.launch))
        #expect(performed == [.launch])

        viewModel.publish(event: .launchRequested(session: UUID()))
        #expect(!viewModel.send(.launch))
        #expect(performed == [.launch])
    }
}
