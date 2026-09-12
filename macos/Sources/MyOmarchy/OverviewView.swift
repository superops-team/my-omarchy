import SwiftUI

struct OverviewView: View {
    @ObservedObject var viewModel: ManagementViewModel
    @State private var confirmsForceStop = false

    private var presentation: OverviewPresentation {
        OverviewPresentation.make(from: viewModel.state)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader
                statusCard
                preparationSection
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(32)
        }
        .confirmationDialog(
            ManagementLocalization.string("overview.force_stop.title"),
            isPresented: $confirmsForceStop,
            titleVisibility: .visible
        ) {
            Button(
                ManagementLocalization.string("command.force_stop"),
                role: .destructive
            ) {
                _ = viewModel.send(.forceStop)
            }
            Button(ManagementLocalization.string("command.cancel"), role: .cancel) {}
        } message: {
            Text(ManagementLocalization.string("overview.force_stop.message"))
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ManagementLocalization.string("overview.title"))
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(ManagementLocalization.string("overview.subtitle"))
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)
                    Text(ManagementLocalization.string(presentation.statusKey))
                        .font(.title2.weight(.semibold))
                    Spacer()
                    if presentation.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(ManagementLocalization.string(presentation.statusKey))
                    }
                }

                if let stageKey = presentation.stageKey {
                    Text(ManagementLocalization.string(stageKey))
                        .foregroundStyle(.secondary)
                }

                if let exitStatus = presentation.lastExitStatus {
                    Text(String(
                        format: ManagementLocalization.string("overview.failure.exit_status"),
                        exitStatus
                    ))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }

                if let readyDate = viewModel.details.readyDate {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(
                            ManagementLocalization.string("overview.runtime")
                                + " "
                                + runtimeDescription(from: readyDate, to: context.date)
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                actionRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionRow: some View {
        if presentation.primaryCommand != nil || !presentation.secondaryCommands.isEmpty {
            HStack {
                if let primary = presentation.primaryCommand {
                    Button(primary.title) {
                        _ = viewModel.send(primary)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }

                ForEach(
                    Array(presentation.secondaryCommands.enumerated()),
                    id: \.offset
                ) { _, command in
                    Button(command.title) {
                        if command == .forceStop {
                            confirmsForceStop = true
                        } else {
                            _ = viewModel.send(command)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var preparationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ManagementLocalization.string("overview.preparation.title"))
                .font(.headline)
            Label(
                preparationPermissionsText,
                systemImage: permissionsReady ? "checkmark.shield.fill" : "exclamationmark.shield"
            )
            Label(
                ManagementLocalization.string("overview.preparation.configuration"),
                systemImage: configurationReady ? "checkmark.circle.fill" : "exclamationmark.circle"
            )
            Label(
                launchPreparationText,
                systemImage: viewModel.state.startupStage == .qemuReady
                    ? "checkmark.circle.fill"
                    : "play.circle"
            )
        }
        .foregroundStyle(.secondary)
    }

    private var permissionsReady: Bool {
        viewModel.details.accessibility == .authorized
            && viewModel.details.microphone != .restricted
            && viewModel.details.camera != .restricted
    }

    private var configurationReady: Bool {
        viewModel.details.storage.problem == nil
            && viewModel.details.effectiveResourceProfile != nil
    }

    private var preparationPermissionsText: String {
        permissionsReady
            ? ManagementLocalization.string("overview.preparation.permissions_ready")
            : ManagementLocalization.string("overview.preparation.permissions_limited")
    }

    private var launchPreparationText: String {
        switch viewModel.state.startupStage {
        case .none: ManagementLocalization.string("overview.preparation.launch_waiting")
        case .preflight: ManagementLocalization.string("overview.stage.preflight")
        case .launcherRunning: ManagementLocalization.string("overview.stage.launcher_running")
        case .qemuReady: ManagementLocalization.string("overview.stage.qemu_ready")
        case .exited: ManagementLocalization.string("overview.stage.exited")
        }
    }

    private func runtimeDescription(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private var statusSymbol: String {
        switch viewModel.state.lifecycle {
        case .idle: "checkmark.circle.fill"
        case .launching, .restarting: "arrow.triangle.2.circlepath"
        case .running: "play.circle.fill"
        case .stopping: "stop.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch viewModel.state.lifecycle {
        case .running, .idle: .accentColor
        case .failed: .red
        case .launching, .stopping, .restarting: .secondary
        }
    }
}

private extension ManagementCommand {
    var title: String {
        switch self {
        case .launch: ManagementLocalization.string("command.launch")
        case .openVirtualMachine: ManagementLocalization.string("command.open_virtual_machine")
        case .stop: ManagementLocalization.string("command.stop")
        case .forceStop: ManagementLocalization.string("command.force_stop")
        case .restart: ManagementLocalization.string("command.restart")
        case .resetStorage: ManagementLocalization.string("command.reset_storage")
        case .setImmersive, .setResourceProfile, .chooseStorageLocation,
             .useDefaultStorageLocation, .openStorageLocation, .chooseSharedFolder,
             .setSharedFolderEnabled, .editPortForwarding, .requestAccessibility,
             .requestMicrophone, .requestCamera, .openMicrophoneSettings,
             .openCameraSettings, .openDiagnosticsLog, .copyDiagnosticSummary:
            ""
        }
    }
}
