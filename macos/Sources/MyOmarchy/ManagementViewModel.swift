import Combine

@MainActor
final class ManagementViewModel: ObservableObject {
    @Published private(set) var state = ManagementState()

    private let perform: (ManagementCommand) -> Void

    init(perform: @escaping (ManagementCommand) -> Void) {
        self.perform = perform
    }

    @discardableResult
    func send(_ command: ManagementCommand) -> Bool {
        guard ManagementCommandPolicy.allows(command, while: state.lifecycle) else {
            return false
        }
        perform(command)
        return true
    }

    @discardableResult
    func publish(event: ManagementEvent) -> Bool {
        state.apply(event)
    }
}
