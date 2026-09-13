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
        #expect(windowController.window.titleVisibility == .hidden)
        #expect(windowController.window.minSize.width == 720)
        #expect(windowController.window.minSize.height >= 520)
        #expect(windowController.window.styleMask.contains(.resizable))
        #expect(windowController.window.appearance == nil)
        #expect(!windowController.window.isReleasedWhenClosed)
    }

    @Test("sidebar toggle stays before the My Omarchy toolbar title")
    func sidebarTogglePrecedesTitle() {
        _ = NSApplication.shared
        let windowController = makeWindow()
        defer { windowController.window.close() }
        windowController.show(activateApplication: false)
        windowController.window.contentView?.layoutSubtreeIfNeeded()

        let identifiers = windowController.window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
        #expect(!identifiers.contains(
            "com.apple.SwiftUI.navigationSplitView.toggleSidebar"
        ))
        let sidebarIndex = try? #require(identifiers.firstIndex(
            of: "management-sidebar-toggle"
        ))
        let titleIndex = try? #require(identifiers.firstIndex(
            of: "management-window-title"
        ))

        #expect(sidebarIndex != nil)
        #expect(titleIndex != nil)
        if let sidebarIndex, let titleIndex {
            #expect(sidebarIndex < titleIndex)
        }
        let separatorIndex = try? #require(identifiers.firstIndex(
            of: "management-title-separator"
        ))
        if let titleIndex, let separatorIndex {
            #expect(titleIndex < separatorIndex)
        }

        #expect(windowController.sidebarState.isVisible)
        windowController.toggleSidebar()
        #expect(!windowController.sidebarState.isVisible)
        windowController.window.contentView?.layoutSubtreeIfNeeded()
        let identifiersAfterToggle = windowController.window.toolbar?.items.map(
            \.itemIdentifier.rawValue
        ) ?? []
        #expect(!identifiersAfterToggle.contains(
            "com.apple.SwiftUI.navigationSplitView.toggleSidebar"
        ))
        let sidebarIndexAfterToggle = try? #require(identifiersAfterToggle.firstIndex(
            of: "management-sidebar-toggle"
        ))
        let titleIndexAfterToggle = try? #require(identifiersAfterToggle.firstIndex(
            of: "management-window-title"
        ))
        if let sidebarIndexAfterToggle, let titleIndexAfterToggle {
            #expect(sidebarIndexAfterToggle < titleIndexAfterToggle)
        }
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
