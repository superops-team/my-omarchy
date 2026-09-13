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

struct CustomResourcePresentation: Equatable {
    let vcpuRange: ClosedRange<Int>
    let memoryRange: ClosedRange<Int>
    let memoryStepMiB: Int
    let reservedHostVCPUCount: Int
    let reservedHostMemoryMiB: Int
    let clampedVCPUCount: Int
    let clampedMemoryMiB: Int
    let validationMessage: String?

    static func make(
        preference: VMResourceProfilePreference,
        limits: VMCustomResourceLimits,
        hostPhysicalMemoryMiB: Int
    ) -> Self {
        let vcpuRange = limits.minimumVCPUCount...limits.maximumVCPUCount
        let memoryRange = limits.minimumMemoryMiB...limits.maximumMemoryMiB
        let clampedVCPUCount = min(
            max(preference.customVCPUCount, limits.minimumVCPUCount),
            limits.maximumVCPUCount
        )
        let clampedMemoryMiB = min(
            max(preference.customMemoryMiB, limits.minimumMemoryMiB),
            limits.maximumMemoryMiB
        )
        let validationMessage: String?
        do {
            _ = try VMResourceProfile.custom(
                vcpuCount: preference.customVCPUCount,
                memoryMiB: preference.customMemoryMiB,
                limits: limits
            )
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
        }
        return Self(
            vcpuRange: vcpuRange,
            memoryRange: memoryRange,
            memoryStepMiB: limits.memoryStepMiB,
            reservedHostVCPUCount: VMCustomResourceLimits.reservedHostCPUs,
            reservedHostMemoryMiB: max(0, hostPhysicalMemoryMiB - preference.customMemoryMiB),
            clampedVCPUCount: clampedVCPUCount,
            clampedMemoryMiB: clampedMemoryMiB,
            validationMessage: validationMessage
        )
    }
}
