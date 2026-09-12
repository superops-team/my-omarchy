enum ManagementCommand: Equatable {
    case launch
    case stop
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
        case (.resetStorage, .idle), (.resetStorage, .failed):
            true
        default:
            false
        }
    }
}
