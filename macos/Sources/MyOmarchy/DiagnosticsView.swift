import Foundation
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var viewModel: ManagementViewModel

    var body: some View {
        Form {
            Section(ManagementLocalization.string("diagnostics.status.title")) {
                LabeledContent(
                    ManagementLocalization.string("diagnostics.lifecycle"),
                    value: ManagementLocalization.string(OverviewPresentation.make(from: viewModel.state).statusKey)
                )
                if let stageKey = OverviewPresentation.make(from: viewModel.state).stageKey {
                    LabeledContent(
                        ManagementLocalization.string("diagnostics.stage"),
                        value: ManagementLocalization.string(stageKey)
                    )
                }
            }

            if let error = viewModel.details.recentErrorSummary, !error.isEmpty {
                Section(ManagementLocalization.string("diagnostics.error.title")) {
                    Text(error)
                        .textSelection(.enabled)
                }
            }

            Section(ManagementLocalization.string("diagnostics.log.title")) {
                if let path = viewModel.details.recentDiagnosticsLogPath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button(ManagementLocalization.string("diagnostics.log.open")) {
                        _ = viewModel.send(.openDiagnosticsLog)
                    }
                } else {
                    Text(ManagementLocalization.string("diagnostics.log.unavailable"))
                        .foregroundStyle(.secondary)
                }
                Button(ManagementLocalization.string("diagnostics.copy_summary")) {
                    _ = viewModel.send(.copyDiagnosticSummary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
