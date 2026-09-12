import SwiftUI

struct ManagementRootView: View {
    @ObservedObject var viewModel: ManagementViewModel
    @ObservedObject var navigation: ManagementNavigation
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(ManagementPage.allCases, selection: $navigation.selection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .accessibilityLabel(ManagementLocalization.string("navigation.sidebar"))
        } detail: {
            destinationView
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: ManagementLocalization.string("search.prompt")
                )
                .searchSuggestions {
                    ForEach(searchResults, id: \.self) { destination in
                        Button {
                            navigation.selection = destination.page
                            searchText = ""
                        } label: {
                            Label(
                                destination.page.title,
                                systemImage: destination.page.systemImage
                            )
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 520)
    }

    private var searchResults: [ManagementDestination] {
        let locale = Locale.current.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        return ManagementSearch.results(for: searchText, locale: locale)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch navigation.selection {
        case .overview:
            OverviewView(viewModel: viewModel)
        case .virtualMachine:
            VirtualMachineView(viewModel: viewModel)
        case .integrations:
            IntegrationsView(viewModel: viewModel)
        case .permissions:
            PermissionsView(viewModel: viewModel)
        case .diagnostics:
            DiagnosticsView(viewModel: viewModel)
        }
    }
}

extension ManagementPage {
    var title: String {
        ManagementLocalization.string("navigation.\(rawValue)")
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .virtualMachine: "desktopcomputer"
        case .integrations: "link"
        case .permissions: "hand.raised"
        case .diagnostics: "stethoscope"
        }
    }
}
