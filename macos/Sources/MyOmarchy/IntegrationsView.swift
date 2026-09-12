import SwiftUI

struct IntegrationsView: View {
    @ObservedObject var viewModel: ManagementViewModel

    private var presentation: IntegrationPresentation {
        .make(details: viewModel.details, lifecycle: viewModel.state.lifecycle)
    }

    var body: some View {
        Form {
            Section(ManagementLocalization.string("integrations.files.title")) {
                LabeledContent(ManagementLocalization.string("integrations.shared_folder")) {
                    Text(viewModel.details.sharedFolder.displayPath
                        ?? ManagementLocalization.string("integration.not_configured"))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Text(ManagementLocalization.string(presentation.sharedFolderStatusKey))
                    .foregroundStyle(.secondary)
                Toggle(
                    ManagementLocalization.string("integrations.shared_folder.enabled"),
                    isOn: sharedFolderBinding
                )
                .disabled(viewModel.details.sharedFolder.path == nil)
                Button(ManagementLocalization.string("integrations.shared_folder.choose")) {
                    _ = viewModel.send(.chooseSharedFolder)
                }
            }

            Section(ManagementLocalization.string("integrations.network.title")) {
                LabeledContent(
                    ManagementLocalization.string("integrations.port_forwarding"),
                    value: portCount
                )
                Text(ManagementLocalization.string(presentation.portStatusKey))
                    .foregroundStyle(.secondary)
                Button(ManagementLocalization.string("integrations.port_forwarding.edit")) {
                    _ = viewModel.send(.editPortForwarding)
                }
            }

            Section(ManagementLocalization.string("integrations.devices.title")) {
                LabeledContent(ManagementLocalization.string("integrations.audio.output"), value: viewModel.details.audioOutput)
                LabeledContent(ManagementLocalization.string("integrations.audio.input"), value: viewModel.details.audioInput)
                LabeledContent(ManagementLocalization.string("integrations.clipboard"), value: runtimeStatus)
                LabeledContent(ManagementLocalization.string("integrations.camera"), value: runtimeStatus)
                Text(ManagementLocalization.string("integrations.devices.read_only"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(ManagementLocalization.string("navigation.integrations"))
    }

    private var sharedFolderBinding: Binding<Bool> {
        Binding(
            get: { viewModel.details.sharedFolder.isEnabled },
            set: { _ = viewModel.send(.setSharedFolderEnabled($0)) }
        )
    }

    private var portCount: String {
        String(format: ManagementLocalization.string("integrations.port_count"), viewModel.details.portMappings.count)
    }

    private var runtimeStatus: String {
        viewModel.state.lifecycle == .running
            ? ManagementLocalization.string("integration.status.running")
            : ManagementLocalization.string("integration.status.unknown")
    }
}
