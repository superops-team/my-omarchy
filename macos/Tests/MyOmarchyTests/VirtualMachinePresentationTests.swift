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
}
