import Testing
@testable import MyOmarchy

@Suite("VM resource profile")
struct VMResourceProfileTests {
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

    private func gibibytes(_ value: UInt64) -> UInt64 {
        value * 1_073_741_824
    }
}
