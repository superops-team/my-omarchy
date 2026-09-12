struct OverviewPresentation: Equatable {
    let statusKey: String
    let stageKey: String?
    let primaryCommand: ManagementCommand?
    let secondaryCommands: [ManagementCommand]
    let isBusy: Bool
    let lastExitStatus: Int32?

    static func make(from state: ManagementState) -> Self {
        switch state.lifecycle {
        case .idle:
            Self(
                statusKey: "overview.status.ready",
                stageKey: stageKey(for: state.startupStage),
                primaryCommand: .launch,
                secondaryCommands: [],
                isBusy: false,
                lastExitStatus: nil
            )
        case .launching:
            Self(
                statusKey: "overview.status.launching",
                stageKey: stageKey(for: state.startupStage),
                primaryCommand: nil,
                secondaryCommands: [],
                isBusy: true,
                lastExitStatus: nil
            )
        case .running:
            Self(
                statusKey: "overview.status.running",
                stageKey: stageKey(for: state.startupStage),
                primaryCommand: .openVirtualMachine,
                secondaryCommands: [.stop, .restart],
                isBusy: false,
                lastExitStatus: nil
            )
        case .stopping:
            Self(
                statusKey: "overview.status.stopping",
                stageKey: stageKey(for: state.startupStage),
                primaryCommand: nil,
                secondaryCommands: state.forceStopAvailable ? [.forceStop] : [],
                isBusy: true,
                lastExitStatus: nil
            )
        case .restarting:
            Self(
                statusKey: "overview.status.restarting",
                stageKey: stageKey(for: state.startupStage),
                primaryCommand: nil,
                secondaryCommands: state.forceStopAvailable ? [.forceStop] : [],
                isBusy: true,
                lastExitStatus: nil
            )
        case .failed:
            Self(
                statusKey: "overview.status.failed",
                stageKey: stageKey(for: state.startupStage),
                primaryCommand: .launch,
                secondaryCommands: [],
                isBusy: false,
                lastExitStatus: state.lastExitStatus
            )
        }
    }

    private static func stageKey(for stage: ManagementStartupStage) -> String? {
        switch stage {
        case .none: nil
        case .preflight: "overview.stage.preflight"
        case .launcherRunning: "overview.stage.launcher_running"
        case .qemuReady: "overview.stage.qemu_ready"
        case .exited: "overview.stage.exited"
        }
    }
}
