import Foundation

enum ManagementAnchor: String, Equatable, Hashable {
    case lifecycle
    case launchMode
    case resources
    case storage
    case sharedFolder
    case portForwarding
    case audio
    case clipboard
    case camera
    case accessibilityPermission
    case microphonePermission
    case cameraPermission
    case recentError
    case launchLog
}

struct ManagementDestination: Equatable, Hashable {
    let page: ManagementPage
    let anchor: ManagementAnchor
}

enum ManagementSearch {
    private struct Entry {
        let destination: ManagementDestination
        let key: String
    }

    private static let entries = [
        Entry(destination: .init(page: .overview, anchor: .lifecycle), key: "search.lifecycle"),
        Entry(destination: .init(page: .virtualMachine, anchor: .launchMode), key: "search.launch_mode"),
        Entry(destination: .init(page: .virtualMachine, anchor: .resources), key: "search.resources"),
        Entry(destination: .init(page: .virtualMachine, anchor: .storage), key: "search.storage"),
        Entry(destination: .init(page: .integrations, anchor: .sharedFolder), key: "search.shared_folder"),
        Entry(destination: .init(page: .integrations, anchor: .portForwarding), key: "search.port_forwarding"),
        Entry(destination: .init(page: .integrations, anchor: .audio), key: "search.audio"),
        Entry(destination: .init(page: .integrations, anchor: .clipboard), key: "search.clipboard"),
        Entry(destination: .init(page: .integrations, anchor: .camera), key: "search.camera"),
        Entry(destination: .init(page: .permissions, anchor: .accessibilityPermission), key: "search.accessibility_permission"),
        Entry(destination: .init(page: .permissions, anchor: .microphonePermission), key: "search.microphone_permission"),
        Entry(destination: .init(page: .permissions, anchor: .cameraPermission), key: "search.camera_permission"),
        Entry(destination: .init(page: .diagnostics, anchor: .recentError), key: "search.recent_error"),
        Entry(destination: .init(page: .diagnostics, anchor: .launchLog), key: "search.launch_log"),
    ]

    static func results(for query: String, locale: String) -> [ManagementDestination] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        return entries.compactMap { entry in
            guard let terms = try? ManagementLocalization.text(entry.key, locale: locale),
                  terms.localizedCaseInsensitiveContains(needle) else { return nil }
            return entry.destination
        }
    }
}
