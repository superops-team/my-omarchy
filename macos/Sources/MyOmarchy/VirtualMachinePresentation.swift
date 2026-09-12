enum SettingApplicationTiming: Equatable {
    case immediate
    case nextLaunch
    case requiresStoppedVM
}

enum VirtualMachineSetting {
    case launchMode
    case resources
    case storage
    case factoryReset

    var applicationTiming: SettingApplicationTiming {
        switch self {
        case .launchMode, .resources: .nextLaunch
        case .storage, .factoryReset: .requiresStoppedVM
        }
    }
}

struct VirtualMachinePresentation: Equatable {
    let canEditLaunchMode: Bool
    let canEditResources: Bool
    let canEditStorage: Bool
    let canResetStorage: Bool

    static func make(lifecycle: ManagementLifecycle) -> Self {
        let isStopped = lifecycle == .idle || lifecycle == .failed
        return Self(
            canEditLaunchMode: isStopped,
            canEditResources: isStopped,
            canEditStorage: isStopped,
            canResetStorage: isStopped
        )
    }
}
