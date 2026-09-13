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
                    selection: resourceSelectionBinding
                ) {
                    Text(ManagementLocalization.string("virtual_machine.resources.automatic"))
                        .tag(VMResourceProfileSelection.automatic)
                    Text(ManagementLocalization.string("virtual_machine.resources.low"))
                        .tag(VMResourceProfileSelection.lowResource)
                    Text(ManagementLocalization.string("virtual_machine.resources.custom"))
                        .tag(VMResourceProfileSelection.custom)
                        .disabled(viewModel.details.customResourceLimits == nil)
                }
                .disabled(!presentation.canEditResources)
                if viewModel.details.resourcePreference.selection == .custom {
                    customResourceControls
                }
                if let profile = viewModel.details.effectiveResourceProfile {
                    LabeledContent(
                        ManagementLocalization.string("virtual_machine.resources.effective"),
                        value: String(
                            format: ManagementLocalization.string("virtual_machine.resources.summary"),
                            profile.vcpuCount,
                            profile.memoryMiB
                        )
                    )
                }
                if viewModel.details.resourcePreference.selection == .custom,
                   let custom = customResourcePresentation,
                   let validationMessage = custom.validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
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
                if let logicalDiskSize = viewModel.details.logicalDiskSize {
                    LabeledContent(ManagementLocalization.string("virtual_machine.storage.logical"), value: logicalDiskSize)
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

    private var resourceSelectionBinding: Binding<VMResourceProfileSelection> {
        Binding(
            get: { viewModel.details.resourcePreference.selection },
            set: { _ = viewModel.send(.setResourceProfileSelection($0)) }
        )
    }

    @ViewBuilder
    private var customResourceControls: some View {
        if let custom = customResourcePresentation {
            Stepper(
                value: customVCPUBinding,
                in: custom.vcpuRange,
                step: 1
            ) {
                LabeledContent(
                    ManagementLocalization.string("virtual_machine.resources.cpu"),
                    value: String(
                        format: ManagementLocalization.string("virtual_machine.resources.cpu_value"),
                        viewModel.details.resourcePreference.customVCPUCount
                    )
                )
            }
            .disabled(!presentation.canEditResources)

            Stepper(
                value: customMemoryBinding,
                in: custom.memoryRange,
                step: custom.memoryStepMiB
            ) {
                LabeledContent(
                    ManagementLocalization.string("virtual_machine.resources.memory"),
                    value: Self.formatMemory(
                        mib: viewModel.details.resourcePreference.customMemoryMiB
                    )
                )
            }
            .disabled(!presentation.canEditResources)

            Text(String(
                format: ManagementLocalization.string("virtual_machine.resources.host_reserve"),
                custom.reservedHostVCPUCount,
                Self.formatMemory(mib: custom.reservedHostMemoryMiB)
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Label(
                ManagementLocalization.string("virtual_machine.resources.custom_unavailable"),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        }
    }

    private var customResourcePresentation: CustomResourcePresentation? {
        guard let limits = viewModel.details.customResourceLimits else { return nil }
        return .make(
            preference: viewModel.details.resourcePreference,
            limits: limits,
            hostPhysicalMemoryMiB: viewModel.details.hostPhysicalMemoryMiB
        )
    }

    private var customVCPUBinding: Binding<Int> {
        Binding(
            get: { customResourcePresentation?.clampedVCPUCount ?? 4 },
            set: { _ = viewModel.send(.setCustomVCPUCount($0)) }
        )
    }

    private var customMemoryBinding: Binding<Int> {
        Binding(
            get: { customResourcePresentation?.clampedMemoryMiB ?? 2_048 },
            set: { _ = viewModel.send(.setCustomMemoryMiB($0)) }
        )
    }

    private static func formatMemory(mib: Int) -> String {
        let gib = Double(mib) / 1_024
        return gib.rounded() == gib
            ? String(format: "%.0f GiB", gib)
            : String(format: "%.1f GiB", gib)
    }
}
