enum ManagementCommand: Equatable {
    case launch
    case openVirtualMachine
    case stop
    case forceStop
    case restart
    case resetStorage
}

enum ManagementCommandPolicy {
    static func allows(
        _ command: ManagementCommand,
        while lifecycle: ManagementLifecycle
    ) -> Bool {
        switch (command, lifecycle) {
        case (.launch, .idle), (.launch, .failed):
            true
        case (.stop, .running), (.restart, .running):
            true
        case (.openVirtualMachine, .running):
            true
        case (.resetStorage, .idle), (.resetStorage, .failed):
            true
        default:
            false
        }
    }

    static func allows(_ command: ManagementCommand, in state: ManagementState) -> Bool {
        if command == .forceStop {
            return state.lifecycle == .stopping && state.forceStopAvailable
        }
        return allows(command, while: state.lifecycle)
    }
}
