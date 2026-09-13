import Combine
import Foundation

enum ManagementPage: String, CaseIterable, Identifiable {
    case overview
    case virtualMachine = "virtual-machine"
    case integrations
    case permissions
    case diagnostics

    var id: String { rawValue }
}

@MainActor
final class ManagementNavigation: ObservableObject {
    private static let selectionKey = "ManagementNavigation.selection"

    @Published var selection: ManagementPage {
        didSet { defaults.set(selection.rawValue, forKey: Self.selectionKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: Self.selectionKey)
            .flatMap(ManagementPage.init(rawValue:)) ?? .overview
    }
}

@MainActor
final class ManagementSidebarState: ObservableObject {
    @Published private(set) var isVisible = true

    func toggle() {
        isVisible.toggle()
    }
}
