import Foundation
import Testing
@testable import MyOmarchy

@Suite("VM resource profile")
struct VMResourceProfileTests {
    @Test("custom limits reserve four CPUs and cap memory at aligned seventy percent")
    func customLimits() throws {
        #expect(try VMCustomResourceLimits.make(
            physicalMemoryBytes: gibibytes(36),
            activeProcessorCount: 12
        ) == VMCustomResourceLimits(
            minimumVCPUCount: 4,
            maximumVCPUCount: 8,
            minimumMemoryMiB: 2_048,
            maximumMemoryMiB: 25_600,
            memoryStepMiB: 512
        ))

        #expect(try VMCustomResourceLimits.make(
            physicalMemoryBytes: gibibytes(8),
            activeProcessorCount: 8
        ).maximumVCPUCount == 4)

        #expect(throws: VMResourceProfileError.self) {
            try VMCustomResourceLimits.make(
                physicalMemoryBytes: gibibytes(16),
                activeProcessorCount: 7
            )
        }
    }

    @Test("custom profile publishes only values inside the host-safe range")
    func customProfileValidation() throws {
        let limits = try VMCustomResourceLimits.make(
            physicalMemoryBytes: gibibytes(36),
            activeProcessorCount: 12
        )
        #expect(try VMResourceProfile.custom(
            vcpuCount: 8,
            memoryMiB: 25_600,
            limits: limits
        ) == VMResourceProfile(
            name: "custom-v1",
            vcpuCount: 8,
            memoryMiB: 25_600
        ))

        for invalid in [
            (3, 2_048),
            (9, 2_048),
            (4, 1_536),
            (4, 25_601),
            (4, 2_304),
        ] {
            #expect(throws: VMResourceProfileError.self) {
                try VMResourceProfile.custom(
                    vcpuCount: invalid.0,
                    memoryMiB: invalid.1,
                    limits: limits
                )
            }
        }
    }

    @Test("automatic profile scales RAM by host memory tiers without using 8 vCPUs")
    func automaticMemoryTiers() throws {
        #expect(try VMResourceProfile.automatic(
            physicalMemoryBytes: gibibytes(8),
            activeProcessorCount: 8
        ) == VMResourceProfile(name: "automatic-v1", vcpuCount: 4, memoryMiB: 2_560))

        #expect(try VMResourceProfile.automatic(
            physicalMemoryBytes: gibibytes(16),
            activeProcessorCount: 8
        ) == VMResourceProfile(name: "automatic-v1", vcpuCount: 4, memoryMiB: 4_096))

        #expect(try VMResourceProfile.automatic(
            physicalMemoryBytes: gibibytes(24),
            activeProcessorCount: 10
        ) == VMResourceProfile(name: "automatic-v1", vcpuCount: 6, memoryMiB: 4_096))
    }

    @Test("automatic profile reserves host CPUs before clipping guest vCPUs")
    func reservesHostCPUs() throws {
        #expect(try VMResourceProfile.automatic(
            physicalMemoryBytes: gibibytes(24),
            activeProcessorCount: 6
        ) == VMResourceProfile(name: "automatic-v1", vcpuCount: 4, memoryMiB: 4_096))

        #expect(throws: VMResourceProfileError.insufficientCPU(
            requiredGuestVCPUs: 4,
            reservedHostCPUs: 2,
            activeHostCPUs: 5
        )) {
            try VMResourceProfile.automatic(
                physicalMemoryBytes: gibibytes(16),
                activeProcessorCount: 5
            )
        }
    }

    @Test("automatic profile fails below the supported memory floor")
    func rejectsTooLittleMemory() {
        #expect(throws: VMResourceProfileError.insufficientMemory(
            requiredMiB: 8_192,
            availableMiB: 7_168
        )) {
            try VMResourceProfile.automatic(
                physicalMemoryBytes: UInt64(7_168) * 1_048_576,
                activeProcessorCount: 8
            )
        }
    }

    @Test("low resource profile keeps the recovery floor explicit")
    func lowResourceProfile() throws {
        #expect(try VMResourceProfile.lowResource(
            physicalMemoryBytes: gibibytes(8),
            activeProcessorCount: 8
        )
            == VMResourceProfile(name: "low-resource-v1", vcpuCount: 4, memoryMiB: 2_048))

        #expect(throws: VMResourceProfileError.insufficientMemory(
            requiredMiB: 8_192,
            availableMiB: 7_168
        )) {
            try VMResourceProfile.lowResource(
                physicalMemoryBytes: UInt64(7_168) * 1_048_576,
                activeProcessorCount: 8
            )
        }
    }

    @Test("launch configuration overwrites inherited resource variables")
    func launchEnvironmentPublishesProfile() throws {
        let inherited = [
            "KEEP_ME": "yes",
            VMResourceProfile.profileEnvironmentKey: "old",
            VMResourceProfile.vcpuEnvironmentKey: "8",
            VMResourceProfile.memoryEnvironmentKey: "4096",
        ]

        let configuration = VMResourceLaunchConfiguration.make(
            baseEnvironment: inherited,
            physicalMemoryBytes: gibibytes(8),
            activeProcessorCount: 8
        )

        #expect(configuration.profile == VMResourceProfile(
            name: "automatic-v1",
            vcpuCount: 4,
            memoryMiB: 2_560
        ))
        #expect(configuration.environment["KEEP_ME"] == "yes")
        #expect(configuration.environment[VMResourceProfile.profileEnvironmentKey] == "automatic-v1")
        #expect(configuration.environment[VMResourceProfile.vcpuEnvironmentKey] == "4")
        #expect(configuration.environment[VMResourceProfile.memoryEnvironmentKey] == "2560")
        #expect(configuration.unavailableReason == nil)
    }

    @Test("launch configuration can publish the low resource profile")
    func launchEnvironmentPublishesLowResourceProfile() throws {
        let configuration = VMResourceLaunchConfiguration.make(
            baseEnvironment: ["KEEP_ME": "yes"],
            preference: .lowResource,
            physicalMemoryBytes: gibibytes(16),
            activeProcessorCount: 8
        )

        #expect(configuration.profile == VMResourceProfile(
            name: "low-resource-v1",
            vcpuCount: 4,
            memoryMiB: 2_048
        ))
        #expect(configuration.environment["KEEP_ME"] == "yes")
        #expect(configuration.environment[VMResourceProfile.profileEnvironmentKey] == "low-resource-v1")
        #expect(configuration.environment[VMResourceProfile.vcpuEnvironmentKey] == "4")
        #expect(configuration.environment[VMResourceProfile.memoryEnvironmentKey] == "2048")
        #expect(configuration.unavailableReason == nil)
    }

    @Test("launch configuration publishes a valid custom profile")
    func launchEnvironmentPublishesCustomProfile() {
        let preference = VMResourceProfilePreference(
            selection: .custom,
            customVCPUCount: 8,
            customMemoryMiB: 12_288
        )
        let configuration = VMResourceLaunchConfiguration.make(
            baseEnvironment: ["KEEP_ME": "yes"],
            preference: preference,
            physicalMemoryBytes: gibibytes(36),
            activeProcessorCount: 12
        )

        #expect(configuration.profile == VMResourceProfile(
            name: "custom-v1",
            vcpuCount: 8,
            memoryMiB: 12_288
        ))
        #expect(configuration.environment[VMResourceProfile.profileEnvironmentKey] == "custom-v1")
        #expect(configuration.environment[VMResourceProfile.vcpuEnvironmentKey] == "8")
        #expect(configuration.environment[VMResourceProfile.memoryEnvironmentKey] == "12288")
        #expect(configuration.unavailableReason == nil)
    }

    @Test("a custom profile that exceeds a smaller host fails without changing the preference")
    func customProfileFailsOnSmallerHost() {
        let preference = VMResourceProfilePreference(
            selection: .custom,
            customVCPUCount: 8,
            customMemoryMiB: 12_288
        )
        let configuration = VMResourceLaunchConfiguration.make(
            baseEnvironment: [:],
            preference: preference,
            physicalMemoryBytes: gibibytes(16),
            activeProcessorCount: 10
        )

        #expect(configuration.profile == nil)
        #expect(configuration.environment[VMResourceProfile.profileEnvironmentKey] == nil)
        #expect(configuration.unavailableReason?.contains("between 4 and 6 vCPUs") == true)
        #expect(preference.customVCPUCount == 8)
        #expect(preference.customMemoryMiB == 12_288)
    }

    @Test("launch configuration fails closed without publishing partial resources")
    func launchEnvironmentFailsClosed() {
        let configuration = VMResourceLaunchConfiguration.make(
            baseEnvironment: [
                VMResourceProfile.profileEnvironmentKey: "old",
                VMResourceProfile.vcpuEnvironmentKey: "8",
                VMResourceProfile.memoryEnvironmentKey: "4096",
            ],
            physicalMemoryBytes: gibibytes(4),
            activeProcessorCount: 8
        )

        #expect(configuration.profile == nil)
        #expect(configuration.environment[VMResourceProfile.profileEnvironmentKey] == nil)
        #expect(configuration.environment[VMResourceProfile.vcpuEnvironmentKey] == nil)
        #expect(configuration.environment[VMResourceProfile.memoryEnvironmentKey] == nil)
        #expect(configuration.unavailableReason?.contains("requires at least 8192 MiB") == true)
    }

    @Test("resource profile preference defaults and invalid payloads fail safely")
    func resourceProfilePreferenceStore() throws {
        let fixture = DefaultsFixture()

        #expect(fixture.store.load() == .automatic)

        fixture.store.save(VMResourceProfilePreference(
            selection: .custom,
            customVCPUCount: 8,
            customMemoryMiB: 12_288
        ))
        #expect(VMResourceProfilePreferenceStore(defaults: fixture.defaults).load()
            == VMResourceProfilePreference(
                selection: .custom,
                customVCPUCount: 8,
                customMemoryMiB: 12_288
            ))

        fixture.store.save(VMResourceProfilePreference(
            selection: .lowResource,
            customVCPUCount: 8,
            customMemoryMiB: 12_288
        ))
        #expect(VMResourceProfilePreferenceStore(defaults: fixture.defaults).load().selection
            == .lowResource)
        #expect(fixture.store.load().customVCPUCount == 8)
        #expect(fixture.store.load().customMemoryMiB == 12_288)

        let legacy = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "profile": "lowResource",
        ])
        fixture.defaults.set(legacy, forKey: VMResourceProfilePreferenceStore.key)
        #expect(fixture.store.load() == .lowResource)
        #expect(fixture.store.load().customVCPUCount == 4)
        #expect(fixture.store.load().customMemoryMiB == 4_096)

        fixture.defaults.set(Data("junk".utf8), forKey: VMResourceProfilePreferenceStore.key)
        #expect(fixture.store.load() == .automatic)

        let future = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": VMResourceProfilePreferenceStore.schemaVersion + 1,
            "profile": VMResourceProfileSelection.lowResource.rawValue,
        ])
        fixture.defaults.set(future, forKey: VMResourceProfilePreferenceStore.key)
        #expect(fixture.store.load() == .automatic)

        let unknown = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": VMResourceProfilePreferenceStore.schemaVersion,
            "profile": "future-profile",
            "customVCPUCount": 4,
            "customMemoryMiB": 4_096,
        ])
        fixture.defaults.set(unknown, forKey: VMResourceProfilePreferenceStore.key)
        #expect(fixture.store.load() == .automatic)

        for invalid in [
            (3, 4_096),
            (4, 1_536),
            (4, 2_304),
        ] {
            let invalidCustom = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": VMResourceProfilePreferenceStore.schemaVersion,
                "profile": VMResourceProfileSelection.custom.rawValue,
                "customVCPUCount": invalid.0,
                "customMemoryMiB": invalid.1,
            ])
            fixture.defaults.set(invalidCustom, forKey: VMResourceProfilePreferenceStore.key)
            #expect(fixture.store.load() == .automatic)
        }
    }

    private func gibibytes(_ value: UInt64) -> UInt64 {
        value * 1_073_741_824
    }

    private final class DefaultsFixture {
        let suiteName = "VMResourceProfileTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: VMResourceProfilePreferenceStore

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            store = VMResourceProfilePreferenceStore(defaults: defaults)
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
