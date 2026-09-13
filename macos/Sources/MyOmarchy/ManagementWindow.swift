import AppKit
import SwiftUI

@MainActor
final class ManagementWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let sidebarState = ManagementSidebarState()

    init(viewModel: ManagementViewModel, navigation: ManagementNavigation) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "My Omarchy"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = false
        window.appearance = nil
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: ManagementRootView(
                viewModel: viewModel,
                navigation: navigation,
                sidebarState: sidebarState
            )
        )
        window.minSize = NSSize(width: 720, height: 520)
        window.setContentSize(NSSize(width: 860, height: 620))
    }

    func show(activateApplication: Bool = true) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        if activateApplication {
            NSApp.activate()
        }
    }

    func toggleSidebar() {
        sidebarState.toggle()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
