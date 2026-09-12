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
}
