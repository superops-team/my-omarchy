import Foundation
import Testing
@testable import MyOmarchy

@Suite("Management controller bridge")
@MainActor
struct ManagementControllerBridgeTests {
    @Test("controller lifecycle events publish through the shared view model")
    func lifecycleEventsPublish() {
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            managementViewModel: viewModel
        )
        let session = UUID()

        #expect(controller.recordManagementEvent(.launchRequested(session: session)))
        #expect(viewModel.state.lifecycle == .launching)
        #expect(controller.recordManagementEvent(.virtualMachineReady(session: session)))
        #expect(viewModel.state.lifecycle == .running)
        #expect(controller.recordManagementEvent(.childExited(session: session, status: 0)))
        #expect(viewModel.state.lifecycle == .idle)
    }

    @Test("ready identity enables window activation and graceful shutdown")
    func readyIdentityEnablesControls() throws {
        var activated: [Int32] = []
        var commands: [String] = []
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            managementViewModel: viewModel,
            runtimeControllerFactory: { _ in
                VMRuntimeController { commands.append($0) }
            },
            windowActivator: VirtualMachineWindowActivator(
                processExists: { $0 == 4242 },
                activate: { activated.append($0); return true }
            )
        )
        let session = UUID()
        _ = controller.recordManagementEvent(.launchRequested(session: session))

        #expect(controller.connectManagementRuntime(
            qmpSocketPath: "/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock",
            processIdentifier: 4242
        ))
        _ = controller.recordManagementEvent(.virtualMachineReady(session: session))
        #expect(controller.openVirtualMachineWindow())
        #expect(activated == [4242])
        #expect(try controller.requestGracefulStop())
        #expect(commands == ["system_powerdown"])
        #expect(viewModel.state.lifecycle == .stopping)
    }

    @Test("failed graceful shutdown leaves the VM running")
    func failedGracefulShutdownDoesNotAdvanceState() {
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            managementViewModel: viewModel,
            runtimeControllerFactory: { _ in
                VMRuntimeController { _ in throw ControlError.expected }
            }
        )
        let session = UUID()
        _ = controller.recordManagementEvent(.launchRequested(session: session))
        _ = controller.connectManagementRuntime(
            qmpSocketPath: "/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock",
            processIdentifier: 4242
        )
        _ = controller.recordManagementEvent(.virtualMachineReady(session: session))

        #expect(throws: ControlError.self) {
            try controller.requestGracefulStop()
        }
        #expect(viewModel.state.lifecycle == .running)
    }

    @Test("restart enters restarting before the child exits")
    func restartWaitsForExit() throws {
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            managementViewModel: viewModel,
            runtimeControllerFactory: { _ in VMRuntimeController { _ in } }
        )
        let session = UUID()
        let nextSession = UUID()
        _ = controller.recordManagementEvent(.launchRequested(session: session))
        _ = controller.connectManagementRuntime(
            qmpSocketPath: "/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock",
            processIdentifier: 4242
        )
        _ = controller.recordManagementEvent(.virtualMachineReady(session: session))

        #expect(try controller.requestGracefulRestart(nextSession: nextSession))
        #expect(viewModel.state.lifecycle == .restarting)
        #expect(viewModel.state.sessionID == session)
        _ = controller.recordManagementEvent(.childExited(session: session, status: 0))
        #expect(viewModel.state.lifecycle == .launching)
        #expect(viewModel.state.sessionID == nextSession)
    }

    @Test("restart launches the reserved session only after the old child exits")
    func restartLaunchesAfterChildExit() throws {
        let supervisor = RecordingProcessSupervisor()
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            baseEnvironment: [:],
            supervisor: supervisor,
            managementViewModel: viewModel,
            runtimeControllerFactory: { _ in VMRuntimeController { _ in } }
        )
        let session = UUID()
        let nextSession = UUID()

        try controller.launchPreparedVirtualMachine(session: session)
        #expect(supervisor.startCount == 1)
        _ = controller.connectManagementRuntime(
            qmpSocketPath: "/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock",
            processIdentifier: 4242
        )
        _ = controller.recordManagementEvent(.virtualMachineReady(session: session))

        #expect(try controller.requestGracefulRestart(nextSession: nextSession))
        #expect(supervisor.startCount == 1)

        supervisor.completeCurrentLaunch(status: 0)

        #expect(supervisor.startCount == 2)
        #expect(viewModel.state.lifecycle == .launching)
        #expect(viewModel.state.sessionID == nextSession)
    }

    private enum ControlError: Error {
        case expected
    }
}

private final class RecordingProcessSupervisor: QEMUGPUProcessSupervising, @unchecked Sendable {
    private(set) var startCount = 0
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
        startCount += 1
        self.completion = completion
    }

    func forward(signal: Int32) {}

    @MainActor
    func completeCurrentLaunch(status: Int32) {
        let completion = self.completion
        self.completion = nil
        completion?(status)
    }
}
