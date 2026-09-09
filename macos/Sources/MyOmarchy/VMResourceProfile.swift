import Foundation

enum VMResourceProfileError: LocalizedError, Equatable {
    case insufficientMemory(requiredMiB: Int, availableMiB: Int)
    case insufficientCPU(requiredGuestVCPUs: Int, reservedHostCPUs: Int, activeHostCPUs: Int)

    var errorDescription: String? {
        switch self {
        case .insufficientMemory(let requiredMiB, let availableMiB):
            "My Omarchy requires at least \(requiredMiB) MiB host memory; this Mac reports \(availableMiB) MiB."
        case .insufficientCPU(let requiredGuestVCPUs, let reservedHostCPUs, let activeHostCPUs):
            "My Omarchy requires \(requiredGuestVCPUs) guest vCPUs while reserving \(reservedHostCPUs) CPUs for macOS; this Mac reports \(activeHostCPUs) active CPUs."
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

    func applying(to base: [String: String]) -> [String: String] {
        var environment = base
        environment[Self.profileEnvironmentKey] = name
        environment[Self.vcpuEnvironmentKey] = String(vcpuCount)
        environment[Self.memoryEnvironmentKey] = String(memoryMiB)
        return environment
    }
}

enum VMResourceProfilePreference: String, Codable, Equatable {
    case automatic
    case lowResource
}

struct VMResourceProfilePreferenceStore {
    static let key = "vmResourceProfilePreference"
    static let schemaVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> VMResourceProfilePreference {
        guard let data = defaults.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == Self.schemaVersion,
              let preference = VMResourceProfilePreference(rawValue: payload.profile) else {
            return .automatic
        }
        return preference
    }

    func save(_ preference: VMResourceProfilePreference) {
        let payload = Payload(
            schemaVersion: Self.schemaVersion,
            profile: preference.rawValue
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private struct Payload: Codable {
        let schemaVersion: Int
        let profile: String
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
        switch preference {
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
