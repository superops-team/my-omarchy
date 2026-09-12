import Darwin
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

    @Test("view model commands are handled by the application controller")
    func viewModelCommandsReachController() {
        var activated: [Int32] = []
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            managementViewModel: viewModel,
            windowActivator: VirtualMachineWindowActivator(
                processExists: { $0 == 4242 },
                activate: { activated.append($0); return true }
            )
        )
        let session = UUID()
        _ = controller.recordManagementEvent(.launchRequested(session: session))
        _ = controller.connectManagementRuntime(
            qmpSocketPath: "/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock",
            processIdentifier: 4242
        )
        _ = controller.recordManagementEvent(.virtualMachineReady(session: session))

        #expect(viewModel.send(.openVirtualMachine))
        #expect(activated == [4242])
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

    @Test("safe stop keeps the management app alive and exposes force stop only after timeout")
    func safeStopStaysInManagementApp() throws {
        let supervisor = RecordingProcessSupervisor()
        let timeout = LockedTimeoutAction()
        let viewModel = ManagementViewModel { _ in }
        let controller = VMApplicationController(
            launcherURL: URL(fileURLWithPath: "/usr/bin/false"),
            initialArguments: [],
            baseEnvironment: [:],
            supervisor: supervisor,
            managementViewModel: viewModel,
            runtimeControllerFactory: { _ in VMRuntimeController { _ in } },
            scheduleGracefulStopTimeout: { timeout.set($0) }
        )
        let session = UUID()
        try controller.launchPreparedVirtualMachine(session: session)
        _ = controller.connectManagementRuntime(
            qmpSocketPath: "/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock",
            processIdentifier: 4242
        )
        _ = controller.recordManagementEvent(.virtualMachineReady(session: session))

        #expect(try controller.requestGracefulStop())
        #expect(!viewModel.state.forceStopAvailable)
        timeout.run()
        #expect(viewModel.state.forceStopAvailable)
        #expect(viewModel.send(.forceStop))
        #expect(supervisor.forwardedSignals == [SIGKILL])

        supervisor.completeCurrentLaunch(status: 137)
        #expect(viewModel.state.lifecycle == .idle)
        #expect(controller.exitStatus == 0)
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
        #expect(viewModel.state.startupStage == .launcherRunning)
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

private final class LockedTimeoutAction: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@MainActor @Sendable () -> Void)?

    func set(_ action: @escaping @MainActor @Sendable () -> Void) {
        lock.lock()
        self.action = action
        lock.unlock()
    }

    @MainActor
    func run() {
        lock.lock()
        let action = self.action
        lock.unlock()
        action?()
    }
}

private final class RecordingProcessSupervisor: QEMUGPUProcessSupervising, @unchecked Sendable {
    private(set) var startCount = 0
    private var completion: (@MainActor @Sendable (Int32) -> Void)?
    private(set) var forwardedSignals: [Int32] = []

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

    func forward(signal: Int32) {
        forwardedSignals.append(signal)
    }

    @MainActor
    func completeCurrentLaunch(status: Int32) {
        let completion = self.completion
        self.completion = nil
        completion?(status)
    }
}
