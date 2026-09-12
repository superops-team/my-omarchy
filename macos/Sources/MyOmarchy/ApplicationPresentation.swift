import AppKit

@MainActor
enum ApplicationPresentation {
    static let prelaunchActivationPolicy = NSApplication.ActivationPolicy.regular
    static let runningActivationPolicy = NSApplication.ActivationPolicy.regular
    static let openManagementWindowAction = NSSelectorFromString("openManagementWindow:")

    static func installMainMenu(
        in application: NSApplication,
        applicationName: String
    ) {
        let mainMenu = NSMenu(title: "Main Menu")

        let applicationItem = NSMenuItem()
        mainMenu.addItem(applicationItem)
        let applicationMenu = NSMenu(title: applicationName)
        applicationItem.submenu = applicationMenu
        applicationMenu.addItem(
            withTitle: String(
                format: ManagementLocalization.string("menu.about"),
                applicationName
            ),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: String(
                format: ManagementLocalization.string("menu.open"),
                applicationName
            ),
            action: openManagementWindowAction,
            keyEquivalent: "0"
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: String(
                format: ManagementLocalization.string("menu.hide"),
                applicationName
            ),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        applicationMenu.addItem(
            withTitle: String(
                format: ManagementLocalization.string("menu.quit"),
                applicationName
            ),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: ManagementLocalization.string("menu.window"))
        windowItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: ManagementLocalization.string("menu.close_window"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: ManagementLocalization.string("menu.minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )

        application.mainMenu = mainMenu
        application.windowsMenu = windowMenu
    }
}
