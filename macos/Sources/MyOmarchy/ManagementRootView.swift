import AppKit
import SwiftUI

struct ManagementRootView: View {
    @ObservedObject var viewModel: ManagementViewModel
    @ObservedObject var navigation: ManagementNavigation
    @ObservedObject var sidebarState: ManagementSidebarState
    @State private var searchText = ""

    var body: some View {
        HSplitView {
            if sidebarState.isVisible {
                List(ManagementPage.allCases, selection: $navigation.selection) { page in
                    Label(page.title, systemImage: page.systemImage)
                        .tag(page)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 180, idealWidth: 210, maxWidth: 260)
                .accessibilityLabel(ManagementLocalization.string("navigation.sidebar"))
            }

            destinationView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .toolbar {
            ToolbarItem(id: "management-sidebar-toggle", placement: .navigation) {
                Button {
                    sidebarState.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .accessibilityLabel(
                    ManagementLocalization.string("navigation.toggle_sidebar")
                )
                .help(ManagementLocalization.string("navigation.toggle_sidebar"))
            }
            ToolbarItem(id: "management-window-title", placement: .navigation) {
                Text("My Omarchy")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(id: "management-title-separator", placement: .navigation) {
                Divider()
                    .frame(height: 24)
            }
        }
    }

    private var searchResults: [ManagementDestination] {
        ManagementSearch.results(for: searchText, locale: ManagementLocalization.currentLocale)
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
