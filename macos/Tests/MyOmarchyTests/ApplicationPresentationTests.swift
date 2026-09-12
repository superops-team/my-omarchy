import AppKit
import Testing
@testable import MyOmarchy

@Suite("Application presentation", .serialized)
@MainActor
struct ApplicationPresentationTests {
    @Test("the management app remains a regular Dock app while QEMU runs")
    func activationPolicies() {
        #expect(ApplicationPresentation.prelaunchActivationPolicy == .regular)
        #expect(ApplicationPresentation.runningActivationPolicy == .regular)
    }

    @Test("the Cocoa VM window stays an accessory to the management app")
    func cocoaWindowProcessPolicy() throws {
        let patch = try source(named: "patches/qemu-cocoa-product-identity.patch")

        #expect(!patch.contains("+    TransformProcessType(&psn, kProcessTransformToForegroundApplication)"))
        #expect(patch.contains("-    TransformProcessType(&psn, kProcessTransformToForegroundApplication)"))
        #expect(patch.contains("[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]"))

        #expect(patch.contains("+        [window orderFrontRegardless];"))
        #expect(patch.contains("+        [window makeKeyWindow];"))
        #expect(!patch.contains("+        [NSApp activate];"))
    }

    @Test("the application menu exposes standard quit and window shortcuts")
    func standardApplicationMenu() throws {
        let application = NSApplication.shared
        let previousMainMenu = application.mainMenu
        let previousWindowMenu = application.windowsMenu
        defer {
            application.mainMenu = previousMainMenu
            application.windowsMenu = previousWindowMenu
        }

        ApplicationPresentation.installMainMenu(
            in: application,
            applicationName: "My Omarchy"
        )

        let appMenu = try #require(application.mainMenu?.items.first?.submenu)
        let quit = try #require(appMenu.items.first(where: {
            $0.title == "Quit My Omarchy"
        }))
        #expect(quit.keyEquivalent == "q")
        #expect(quit.action == #selector(NSApplication.terminate(_:)))

        let open = try #require(appMenu.items.first(where: {
            $0.title == "Open My Omarchy"
        }))
        #expect(open.keyEquivalent == "0")
        #expect(open.action == ApplicationPresentation.openManagementWindowAction)

        let windowMenu = try #require(application.windowsMenu)
        let close = try #require(windowMenu.items.first(where: {
            $0.title == "Close Window"
        }))
        #expect(close.keyEquivalent == "w")
        #expect(close.action == #selector(NSWindow.performClose(_:)))
    }

    private func source(named relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let macosDirectory = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: macosDirectory.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
