import Foundation

enum VMResourceProfileError: LocalizedError, Equatable {
    case insufficientMemory(requiredMiB: Int, availableMiB: Int)
    case insufficientCPU(requiredGuestVCPUs: Int, reservedHostCPUs: Int, activeHostCPUs: Int)
    case customVCPUOutOfRange(minimum: Int, maximum: Int, received: Int)
    case customMemoryOutOfRange(minimumMiB: Int, maximumMiB: Int, receivedMiB: Int)
    case customMemoryMisaligned(stepMiB: Int, receivedMiB: Int)

    var errorDescription: String? {
        switch self {
        case .insufficientMemory(let requiredMiB, let availableMiB):
            "My Omarchy requires at least \(requiredMiB) MiB host memory; this Mac reports \(availableMiB) MiB."
        case .insufficientCPU(let requiredGuestVCPUs, let reservedHostCPUs, let activeHostCPUs):
            "My Omarchy requires \(requiredGuestVCPUs) guest vCPUs while reserving \(reservedHostCPUs) CPUs for macOS; this Mac reports \(activeHostCPUs) active CPUs."
        case .customVCPUOutOfRange(let minimum, let maximum, let received):
            "Custom CPU must be between \(minimum) and \(maximum) vCPUs (received \(received))."
        case .customMemoryOutOfRange(let minimumMiB, let maximumMiB, let receivedMiB):
            "Custom memory must be between \(minimumMiB) and \(maximumMiB) MiB (received \(receivedMiB))."
        case .customMemoryMisaligned(let stepMiB, let receivedMiB):
            "Custom memory must use \(stepMiB) MiB increments (received \(receivedMiB))."
        }
    }
}

struct VMResourceProfile: Equatable {
    static let schemaVersion = 1
    static let profileEnvironmentKey = "OMARCHY_QEMU_GPU_RESOURCE_PROFILE"
    static let vcpuEnvironmentKey = "OMARCHY_QEMU_GPU_VCPUS"
    static let memoryEnvironmentKey = "OMARCHY_QEMU_GPU_MEMORY_MIB"

    static let minimumMemoryMiB = 8 * 1_024
    static let minimumGuestVCPUs = 4
    static let reservedHostCPUs = 2

    let name: String
    let vcpuCount: Int
    let memoryMiB: Int

    static func automatic(
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory,
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) throws -> Self {
        let memoryMiB = Int(physicalMemoryBytes / 1_048_576)
        guard memoryMiB >= minimumMemoryMiB else {
            throw VMResourceProfileError.insufficientMemory(
                requiredMiB: minimumMemoryMiB,
                availableMiB: memoryMiB
            )
        }

        let hostAvailableForGuest = activeProcessorCount - reservedHostCPUs
        guard hostAvailableForGuest >= minimumGuestVCPUs else {
            throw VMResourceProfileError.insufficientCPU(
                requiredGuestVCPUs: minimumGuestVCPUs,
                reservedHostCPUs: reservedHostCPUs,
                activeHostCPUs: activeProcessorCount
            )
        }

        let candidate = if memoryMiB >= 24 * 1_024 {
            Self(name: "automatic-v1", vcpuCount: 6, memoryMiB: 4_096)
        } else if memoryMiB >= 16 * 1_024 {
            Self(name: "automatic-v1", vcpuCount: 4, memoryMiB: 4_096)
        } else {
            Self(name: "automatic-v1", vcpuCount: 4, memoryMiB: 2_560)
        }
        return Self(
            name: candidate.name,
            vcpuCount: min(candidate.vcpuCount, hostAvailableForGuest),
            memoryMiB: candidate.memoryMiB
        )
    }

    static func lowResource(
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory,
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) throws -> Self {
        let memoryMiB = Int(physicalMemoryBytes / 1_048_576)
        guard memoryMiB >= minimumMemoryMiB else {
            throw VMResourceProfileError.insufficientMemory(
                requiredMiB: minimumMemoryMiB,
                availableMiB: memoryMiB
            )
        }
        let hostAvailableForGuest = activeProcessorCount - reservedHostCPUs
        guard hostAvailableForGuest >= minimumGuestVCPUs else {
            throw VMResourceProfileError.insufficientCPU(
                requiredGuestVCPUs: minimumGuestVCPUs,
                reservedHostCPUs: reservedHostCPUs,
                activeHostCPUs: activeProcessorCount
            )
        }
        return Self(name: "low-resource-v1", vcpuCount: 4, memoryMiB: 2_048)
    }

    static func custom(
        vcpuCount: Int,
        memoryMiB: Int,
        limits: VMCustomResourceLimits
    ) throws -> Self {
        guard (limits.minimumVCPUCount...limits.maximumVCPUCount).contains(vcpuCount) else {
            throw VMResourceProfileError.customVCPUOutOfRange(
                minimum: limits.minimumVCPUCount,
                maximum: limits.maximumVCPUCount,
                received: vcpuCount
            )
        }
        guard (limits.minimumMemoryMiB...limits.maximumMemoryMiB).contains(memoryMiB) else {
            throw VMResourceProfileError.customMemoryOutOfRange(
                minimumMiB: limits.minimumMemoryMiB,
                maximumMiB: limits.maximumMemoryMiB,
                receivedMiB: memoryMiB
            )
        }
        guard memoryMiB.isMultiple(of: limits.memoryStepMiB) else {
            throw VMResourceProfileError.customMemoryMisaligned(
                stepMiB: limits.memoryStepMiB,
                receivedMiB: memoryMiB
            )
        }
        return Self(name: "custom-v1", vcpuCount: vcpuCount, memoryMiB: memoryMiB)
    }

    func applying(to base: [String: String]) -> [String: String] {
        var environment = base
        environment[Self.profileEnvironmentKey] = name
        environment[Self.vcpuEnvironmentKey] = String(vcpuCount)
        environment[Self.memoryEnvironmentKey] = String(memoryMiB)
        return environment
    }
}

struct VMCustomResourceLimits: Equatable {
    static let minimumVCPUCount = 4
    static let reservedHostCPUs = 4
    static let minimumMemoryMiB = 2_048
    static let memoryStepMiB = 512

    let minimumVCPUCount: Int
    let maximumVCPUCount: Int
    let minimumMemoryMiB: Int
    let maximumMemoryMiB: Int
    let memoryStepMiB: Int

    static func make(
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory,
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) throws -> Self {
        let maximumVCPUCount = activeProcessorCount - reservedHostCPUs
        guard maximumVCPUCount >= minimumVCPUCount else {
            throw VMResourceProfileError.insufficientCPU(
                requiredGuestVCPUs: minimumVCPUCount,
                reservedHostCPUs: reservedHostCPUs,
                activeHostCPUs: activeProcessorCount
            )
        }

        let hostMemoryMiB = Int(physicalMemoryBytes / 1_048_576)
        let seventyPercentMiB = hostMemoryMiB * 70 / 100
        let maximumMemoryMiB = seventyPercentMiB / memoryStepMiB * memoryStepMiB
        guard maximumMemoryMiB >= minimumMemoryMiB else {
            throw VMResourceProfileError.insufficientMemory(
                requiredMiB: minimumMemoryMiB,
                availableMiB: maximumMemoryMiB
            )
        }

        return Self(
            minimumVCPUCount: minimumVCPUCount,
            maximumVCPUCount: maximumVCPUCount,
            minimumMemoryMiB: minimumMemoryMiB,
            maximumMemoryMiB: maximumMemoryMiB,
            memoryStepMiB: memoryStepMiB
        )
    }
}

enum VMResourceProfileSelection: String, Codable, CaseIterable, Equatable, Hashable {
    case automatic
    case lowResource
    case custom
}

struct VMResourceProfilePreference: Equatable, Hashable {
    static let defaultCustomVCPUCount = 4
    static let defaultCustomMemoryMiB = 4_096

    let selection: VMResourceProfileSelection
    let customVCPUCount: Int
    let customMemoryMiB: Int

    static let automatic = Self(selection: .automatic)
    static let lowResource = Self(selection: .lowResource)

    init(
        selection: VMResourceProfileSelection,
        customVCPUCount: Int = defaultCustomVCPUCount,
        customMemoryMiB: Int = defaultCustomMemoryMiB
    ) {
        self.selection = selection
        self.customVCPUCount = customVCPUCount
        self.customMemoryMiB = customMemoryMiB
    }

    func selecting(_ selection: VMResourceProfileSelection) -> Self {
        Self(
            selection: selection,
            customVCPUCount: customVCPUCount,
            customMemoryMiB: customMemoryMiB
        )
    }
}

struct VMResourceProfilePreferenceStore {
    static let key = "vmResourceProfilePreference"
    static let schemaVersion = 2

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> VMResourceProfilePreference {
        guard let data = defaults.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .automatic
        }
        guard let selection = VMResourceProfileSelection(rawValue: payload.profile) else {
            return .automatic
        }
        switch payload.schemaVersion {
        case 1:
            guard selection != .custom else { return .automatic }
            return VMResourceProfilePreference(selection: selection)
        case Self.schemaVersion:
            guard let customVCPUCount = payload.customVCPUCount,
                  let customMemoryMiB = payload.customMemoryMiB,
                  customVCPUCount >= VMCustomResourceLimits.minimumVCPUCount,
                  customMemoryMiB >= VMCustomResourceLimits.minimumMemoryMiB,
                  customMemoryMiB.isMultiple(of: VMCustomResourceLimits.memoryStepMiB) else {
                return .automatic
            }
            return VMResourceProfilePreference(
                selection: selection,
                customVCPUCount: customVCPUCount,
                customMemoryMiB: customMemoryMiB
            )
        default:
            return .automatic
        }
    }

    func save(_ preference: VMResourceProfilePreference) {
        let payload = Payload(
            schemaVersion: Self.schemaVersion,
            profile: preference.selection.rawValue,
            customVCPUCount: preference.customVCPUCount,
            customMemoryMiB: preference.customMemoryMiB
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private struct Payload: Codable {
        let schemaVersion: Int
        let profile: String
        let customVCPUCount: Int?
        let customMemoryMiB: Int?
    }
}

struct VMResourceLaunchConfiguration: Equatable {
    let profile: VMResourceProfile?
    let environment: [String: String]
    let unavailableReason: String?

    static func make(
        baseEnvironment: [String: String],
        preference: VMResourceProfilePreference = .automatic,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory,
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Self {
        let cleaned = VMResourceLaunchConfiguration.cleaned(baseEnvironment)
        do {
            let profile = try selectedProfile(
                preference: preference,
                physicalMemoryBytes: physicalMemoryBytes,
                activeProcessorCount: activeProcessorCount
            )
            return Self(
                profile: profile,
                environment: profile.applying(to: cleaned),
                unavailableReason: nil
            )
        } catch {
            return Self(
                profile: nil,
                environment: cleaned,
                unavailableReason: error.localizedDescription
            )
        }
    }

    private static func selectedProfile(
        preference: VMResourceProfilePreference,
        physicalMemoryBytes: UInt64,
        activeProcessorCount: Int
    ) throws -> VMResourceProfile {
        switch preference.selection {
        case .automatic:
            try VMResourceProfile.automatic(
                physicalMemoryBytes: physicalMemoryBytes,
                activeProcessorCount: activeProcessorCount
            )
        case .lowResource:
            try VMResourceProfile.lowResource(
                physicalMemoryBytes: physicalMemoryBytes,
                activeProcessorCount: activeProcessorCount
            )
        case .custom:
            try VMResourceProfile.custom(
                vcpuCount: preference.customVCPUCount,
                memoryMiB: preference.customMemoryMiB,
                limits: VMCustomResourceLimits.make(
                    physicalMemoryBytes: physicalMemoryBytes,
                    activeProcessorCount: activeProcessorCount
                )
            )
        }
    }

    private static func cleaned(_ environment: [String: String]) -> [String: String] {
        var cleaned = environment
        cleaned.removeValue(forKey: VMResourceProfile.profileEnvironmentKey)
        cleaned.removeValue(forKey: VMResourceProfile.vcpuEnvironmentKey)
        cleaned.removeValue(forKey: VMResourceProfile.memoryEnvironmentKey)
        return cleaned
    }
}
