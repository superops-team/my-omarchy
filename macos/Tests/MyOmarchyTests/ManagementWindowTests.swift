import AppKit
import Testing
@testable import MyOmarchy

@Suite("Management window", .serialized)
@MainActor
struct ManagementWindowTests {
    @Test("the native management window is resizable and follows system appearance")
    func nativeWindowConfiguration() {
        _ = NSApplication.shared
        let windowController = makeWindow()
        defer { windowController.window.close() }

        #expect(windowController.window.contentLayoutRect.size == NSSize(width: 860, height: 620))
        #expect(windowController.window.title == "My Omarchy")
        #expect(windowController.window.minSize == NSSize(width: 720, height: 520))
        #expect(windowController.window.styleMask.contains(.resizable))
        #expect(windowController.window.appearance == nil)
        #expect(!windowController.window.isReleasedWhenClosed)
    }

    @Test("closing hides and reopening restores the same management window")
    func hidesAndRestoresSameWindow() {
        _ = NSApplication.shared
        let windowController = makeWindow()
        let originalWindow = windowController.window
        defer { originalWindow.close() }

        originalWindow.orderFront(nil)
        #expect(originalWindow.isVisible)
        #expect(!windowController.windowShouldClose(originalWindow))
        #expect(!originalWindow.isVisible)

        windowController.show(activateApplication: false)
        #expect(windowController.window === originalWindow)
        #expect(originalWindow.isVisible)
    }

    private func makeWindow() -> ManagementWindow {
        ManagementWindow(
            viewModel: ManagementViewModel { _ in },
            navigation: ManagementNavigation(
                defaults: UserDefaults(suiteName: "ManagementWindowTests")!
            )
        )
    }
}
