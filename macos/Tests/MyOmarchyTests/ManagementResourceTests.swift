import AppKit
import SwiftUI
import Testing
@testable import MyOmarchy

@Suite("Management resources", .serialized)
@MainActor
struct ManagementResourceTests {
    @Test("SwiftUI can be hosted by the AppKit application lifecycle")
    func appKitHostsSwiftUI() {
        _ = NSApplication.shared
        let hostingView = NSHostingView(rootView: Text("My Omarchy"))

        #expect(hostingView.fittingSize.width > 0)
        #expect(hostingView.fittingSize.height > 0)
    }

    @Test("management copy is available in English and Simplified Chinese")
    func localizedCopy() throws {
        #expect(try ManagementLocalization.text("navigation.overview", locale: "en") == "Overview")
        #expect(try ManagementLocalization.text("navigation.overview", locale: "zh-Hans") == "概览")
    }

    @Test("the management shell has complete English and Simplified Chinese copy")
    func localizedShellCopyIsComplete() throws {
        let keys = [
            "navigation.overview",
            "navigation.virtual-machine",
            "navigation.integrations",
            "navigation.permissions",
            "navigation.diagnostics",
            "navigation.sidebar",
            "search.prompt",
            "page.placeholder",
            "overview.title",
            "overview.subtitle",
            "overview.status.ready",
            "overview.status.launching",
            "overview.status.running",
            "overview.status.stopping",
            "overview.status.restarting",
            "overview.status.failed",
            "overview.stage.preflight",
            "overview.stage.launcher_running",
            "overview.stage.qemu_ready",
            "overview.stage.exited",
            "overview.failure.exit_status",
            "overview.preparation.title",
            "overview.preparation.permissions",
            "overview.preparation.configuration",
            "overview.preparation.launch",
            "overview.force_stop.title",
            "overview.force_stop.message",
            "command.launch",
            "command.open_virtual_machine",
            "command.stop",
            "command.force_stop",
            "command.restart",
            "command.reset_storage",
            "command.cancel",
            "search.lifecycle",
            "search.launch_mode",
            "search.resources",
            "search.storage",
            "search.shared_folder",
            "search.port_forwarding",
            "search.audio",
            "search.clipboard",
            "search.camera",
            "search.accessibility_permission",
            "search.microphone_permission",
            "search.camera_permission",
            "search.recent_error",
            "search.launch_log",
        ]

        for locale in ["en", "zh-Hans"] {
            for key in keys {
                let value = try ManagementLocalization.text(key, locale: locale)
                #expect(!value.isEmpty)
                #expect(value != key)
            }
        }
    }
}
