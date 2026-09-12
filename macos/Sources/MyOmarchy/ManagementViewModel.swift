import Combine

@MainActor
final class ManagementViewModel: ObservableObject {
    @Published private(set) var state = ManagementState()
    @Published private(set) var details = ManagementDetails()

    private var perform: (ManagementCommand) -> Void

    init(perform: @escaping (ManagementCommand) -> Void) {
        self.perform = perform
    }

    func connect(perform: @escaping (ManagementCommand) -> Void) {
        self.perform = perform
    }

    @discardableResult
    func send(_ command: ManagementCommand) -> Bool {
        guard ManagementCommandPolicy.allows(command, in: state) else {
            return false
        }
        perform(command)
        return true
    }

    @discardableResult
    func publish(event: ManagementEvent) -> Bool {
        state.apply(event)
    }

    func publish(details: ManagementDetails) {
        self.details = details
    }
}
