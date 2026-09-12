import Foundation
import Testing
@testable import MyOmarchy

@Suite("Management navigation", .serialized)
@MainActor
struct ManagementNavigationTests {
    @Test("five stable pages default to Overview and restore the last selection")
    func stablePagesAndRestoration() {
        #expect(ManagementPage.allCases.map(\.rawValue) == [
            "overview",
            "virtual-machine",
            "integrations",
            "permissions",
            "diagnostics",
        ])

        let suiteName = "ManagementNavigationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ManagementNavigation(defaults: defaults)
        #expect(first.selection == .overview)
        first.selection = .permissions

        let restored = ManagementNavigation(defaults: defaults)
        #expect(restored.selection == .permissions)
    }

    @Test("search maps localized current capabilities to pages and anchors")
    func searchIndex() {
        #expect(ManagementSearch.results(for: "storage", locale: "en") == [
            ManagementDestination(page: .virtualMachine, anchor: .storage),
        ])
        #expect(ManagementSearch.results(for: "端口", locale: "zh-Hans") == [
            ManagementDestination(page: .integrations, anchor: .portForwarding),
        ])
        #expect(ManagementSearch.results(for: "camera", locale: "en") == [
            ManagementDestination(page: .integrations, anchor: .camera),
            ManagementDestination(page: .permissions, anchor: .cameraPermission),
        ])
        #expect(ManagementSearch.results(for: "backup", locale: "en").isEmpty)
        #expect(ManagementSearch.results(for: "备份", locale: "zh-Hans").isEmpty)
    }
}
