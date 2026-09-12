import SwiftUI

struct PermissionsView: View {
    @ObservedObject var viewModel: ManagementViewModel

    var body: some View {
        Form {
            permissionRow(
                kind: .accessibility,
                state: viewModel.details.accessibility,
                titleKey: "permissions.accessibility.title",
                detailKey: "permissions.accessibility.detail",
                symbol: "accessibility"
            )
            permissionRow(
                kind: .microphone,
                state: viewModel.details.microphone,
                titleKey: "permissions.microphone.title",
                detailKey: "permissions.microphone.detail",
                symbol: "mic"
            )
            permissionRow(
                kind: .camera,
                state: viewModel.details.camera,
                titleKey: "permissions.camera.title",
                detailKey: "permissions.camera.detail",
                symbol: "camera"
            )
        }
        .formStyle(.grouped)
    }

    private func permissionRow(
        kind: ManagementPermissionKind,
        state: ManagementPermissionState,
        titleKey: String,
        detailKey: String,
        symbol: String
    ) -> some View {
        let presentation = PermissionPresentation.make(kind: kind, state: state)
        return Section {
            LabeledContent {
                Text(ManagementLocalization.string(presentation.statusKey))
            } label: {
                Label(ManagementLocalization.string(titleKey), systemImage: symbol)
            }
            Text(ManagementLocalization.string(detailKey))
                .foregroundStyle(.secondary)
            if let command = presentation.command {
                Button(ManagementLocalization.string("permission.action")) {
                    _ = viewModel.send(command)
                }
            }
        }
    }
}
