import SwiftUI

struct VirtualMachineView: View {
    @ObservedObject var viewModel: ManagementViewModel

    private var presentation: VirtualMachinePresentation {
        .make(lifecycle: viewModel.state.lifecycle)
    }

    var body: some View {
        Form {
            Section(ManagementLocalization.string("virtual_machine.launch.title")) {
                Picker(
                    ManagementLocalization.string("virtual_machine.launch.mode"),
                    selection: immersiveBinding
                ) {
                    Text(ManagementLocalization.string("virtual_machine.launch.full_screen"))
                        .tag(true)
                    Text(ManagementLocalization.string("virtual_machine.launch.window"))
                        .tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(!presentation.canEditLaunchMode)
                Text(ManagementLocalization.string("setting.next_launch"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(ManagementLocalization.string("virtual_machine.resources.title")) {
                Picker(
                    ManagementLocalization.string("virtual_machine.resources.profile"),
                    selection: resourceBinding
                ) {
                    Text(ManagementLocalization.string("virtual_machine.resources.automatic"))
                        .tag(VMResourceProfilePreference.automatic)
                    Text(ManagementLocalization.string("virtual_machine.resources.low"))
                        .tag(VMResourceProfilePreference.lowResource)
                }
                .disabled(!presentation.canEditResources)
                Text(ManagementLocalization.string("setting.next_launch"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(ManagementLocalization.string("virtual_machine.storage.title")) {
                LabeledContent(ManagementLocalization.string("virtual_machine.storage.location")) {
                    Text(storagePath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let volumeName = viewModel.details.storage.volumeName {
                    LabeledContent(ManagementLocalization.string("virtual_machine.storage.volume"), value: volumeName)
                }
                if let reclaimable = viewModel.details.reclaimableStorage {
                    LabeledContent(ManagementLocalization.string("virtual_machine.storage.allocated"), value: reclaimable)
                }
                if let problem = viewModel.details.storage.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if let warning = viewModel.details.storage.warning {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(ManagementLocalization.string("virtual_machine.storage.choose")) {
                        _ = viewModel.send(.chooseStorageLocation)
                    }
                    .disabled(!presentation.canEditStorage || !viewModel.details.canResetStorage)
                    Button(ManagementLocalization.string("virtual_machine.storage.default")) {
                        _ = viewModel.send(.useDefaultStorageLocation)
                    }
                    .disabled(!presentation.canEditStorage || viewModel.details.storage.isDefault)
                    Button(ManagementLocalization.string("virtual_machine.storage.open")) {
                        _ = viewModel.send(.openStorageLocation)
                    }
                }
                Text(ManagementLocalization.string("setting.requires_stopped_vm"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(
                    ManagementLocalization.string("command.reset_storage"),
                    role: .destructive
                ) {
                    _ = viewModel.send(.resetStorage)
                }
                .disabled(!presentation.canResetStorage || !viewModel.details.canResetStorage)
            } header: {
                Text(ManagementLocalization.string("virtual_machine.reset.title"))
            } footer: {
                Text(ManagementLocalization.string("virtual_machine.reset.detail"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(ManagementLocalization.string("navigation.virtual-machine"))
    }

    private var storagePath: String {
        viewModel.details.storage.displayPath
            ?? ManagementLocalization.string("virtual_machine.storage.default_value")
    }

    private var immersiveBinding: Binding<Bool> {
        Binding(
            get: { viewModel.details.isImmersive },
            set: { _ = viewModel.send(.setImmersive($0)) }
        )
    }

    private var resourceBinding: Binding<VMResourceProfilePreference> {
        Binding(
            get: { viewModel.details.resourcePreference },
            set: { _ = viewModel.send(.setResourceProfile($0)) }
        )
    }
}
