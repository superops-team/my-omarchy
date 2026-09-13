import Testing
@testable import MyOmarchy

@Suite("Virtual machine settings presentation")
struct VirtualMachinePresentationTests {
    @Test("cold settings stay readable but editable only while stopped")
    func coldSettingAvailability() {
        for lifecycle in [ManagementLifecycle.idle, .failed] {
            let presentation = VirtualMachinePresentation.make(lifecycle: lifecycle)
            #expect(presentation.canEditLaunchMode)
            #expect(presentation.canEditResources)
            #expect(presentation.canEditStorage)
            #expect(presentation.canResetStorage)
        }

        for lifecycle in [
            ManagementLifecycle.launching, .running, .stopping, .restarting,
        ] {
            let presentation = VirtualMachinePresentation.make(lifecycle: lifecycle)
            #expect(!presentation.canEditLaunchMode)
            #expect(!presentation.canEditResources)
            #expect(!presentation.canEditStorage)
            #expect(!presentation.canResetStorage)
        }
    }

    @Test("settings expose their actual application timing")
    func applicationTiming() {
        #expect(VirtualMachineSetting.launchMode.applicationTiming == .nextLaunch)
        #expect(VirtualMachineSetting.resources.applicationTiming == .nextLaunch)
        #expect(VirtualMachineSetting.storage.applicationTiming == .requiresStoppedVM)
        #expect(VirtualMachineSetting.factoryReset.applicationTiming == .requiresStoppedVM)
    }

    @Test("custom resources expose host ranges and explain invalid history")
    func customResources() throws {
        let limits = try VMCustomResourceLimits.make(
            physicalMemoryBytes: 36 * 1_073_741_824,
            activeProcessorCount: 12
        )
        let valid = CustomResourcePresentation.make(
            preference: VMResourceProfilePreference(
                selection: .custom,
                customVCPUCount: 8,
                customMemoryMiB: 25_600
            ),
            limits: limits,
            hostPhysicalMemoryMiB: 36 * 1_024
        )
        #expect(valid.vcpuRange == 4...8)
        #expect(valid.memoryRange == 2_048...25_600)
        #expect(valid.reservedHostVCPUCount == 4)
        #expect(valid.reservedHostMemoryMiB == 11_264)
        #expect(valid.validationMessage == nil)

        let invalid = CustomResourcePresentation.make(
            preference: VMResourceProfilePreference(
                selection: .custom,
                customVCPUCount: 10,
                customMemoryMiB: 26_112
            ),
            limits: limits,
            hostPhysicalMemoryMiB: 36 * 1_024
        )
        #expect(invalid.validationMessage != nil)
        #expect(invalid.clampedVCPUCount == 8)
        #expect(invalid.clampedMemoryMiB == 25_600)
    }
}
