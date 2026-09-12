import AppKit
import Testing
@testable import MyOmarchy

@Suite("Management application lifecycle", .serialized)
@MainActor
struct ManagementApplicationLifecycleTests {
    @Test("launch and reopen keep one persistent management window")
    func persistentManagementWindow() {
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            bundledMetrics: nil
        )

        controller.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let originalWindow = controller.managementWindow
        #expect(originalWindow?.window.isVisible == true)
        originalWindow?.window.orderOut(nil)

        #expect(controller.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        #expect(controller.managementWindow === originalWindow)
        #expect(originalWindow?.window.isVisible == true)
    }

    @Test("the application menu action restores the same management window")
    func menuActionRestoresWindow() {
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            bundledMetrics: nil
        )
        controller.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let originalWindow = controller.managementWindow
        originalWindow?.window.orderOut(nil)

        controller.openManagementWindow(nil)

        #expect(controller.managementWindow === originalWindow)
        #expect(originalWindow?.window.isVisible == true)
    }

    @Test("a virtual machine exit leaves the management app open")
    func virtualMachineExitKeepsManagementOpen() throws {
        let supervisor = LifecycleProcessSupervisor()
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            baseEnvironment: [:],
            supervisor: supervisor,
            bundledMetrics: nil,
            managementViewModel: viewModel
        )
        controller.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let window = controller.managementWindow?.window
        let session = UUID()

        try controller.launchPreparedVirtualMachine(session: session)
        _ = controller.recordManagementEvent(.virtualMachineReady(session: session))
        supervisor.complete(status: 0)

        #expect(viewModel.state.lifecycle == .idle)
        #expect(window?.isVisible == true)
        #expect(controller.exitStatus == 0)
    }

    @Test("an initial reset request is consumed only once across window restores")
    func initialResetIsOneShot() {
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [QEMUGPUStorageOption.resetStorageOnly.rawValue],
            bundledMetrics: nil,
            managementViewModel: viewModel
        )
        var resetCommands = 0
        viewModel.connect { command in
            if command == .resetStorage { resetCommands += 1 }
        }

        controller.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        controller.openManagementWindow(nil)

        #expect(resetCommands == 1)
    }
}

private final class LifecycleProcessSupervisor: QEMUGPUProcessSupervising, @unchecked Sendable {
    private var completion: (@MainActor @Sendable (Int32) -> Void)?
    var recentStandardError = ""
    var recentDiagnosticsLogPath: String?

    func start(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        launchEvent: @escaping @MainActor @Sendable (QEMUGPUProcessSupervisor.LaunchEvent) -> Void,
        completion: @escaping @MainActor @Sendable (Int32) -> Void
    ) throws {
        self.completion = completion
    }

    func forward(signal: Int32) {}

    @MainActor
    func complete(status: Int32) {
        let completion = self.completion
        self.completion = nil
        completion?(status)
    }
}
