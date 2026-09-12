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
        .navigationTitle(ManagementLocalization.string("navigation.overview"))
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

                ForEach(presentation.secondaryCommands, id: \.self) { command in
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
                ManagementLocalization.string("overview.preparation.permissions"),
                systemImage: "checkmark.shield"
            )
            Label(
                ManagementLocalization.string("overview.preparation.configuration"),
                systemImage: "slider.horizontal.3"
            )
            Label(
                ManagementLocalization.string("overview.preparation.launch"),
                systemImage: "play.circle"
            )
        }
        .foregroundStyle(.secondary)
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
        }
    }
}
