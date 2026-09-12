import AppKit

@MainActor
final class ManagementAppKitPresenter {
    private let parentWindow: () -> NSWindow?
    private var resetPrompt: ResetConfirmationPrompt?
    private var portEditor: PortForwardingEditor?

    init(parentWindow: @escaping () -> NSWindow?) {
        self.parentWindow = parentWindow
    }

    func chooseDirectory(
        title: String,
        message: String,
        prompt: String,
        initialURL: URL?
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.directoryURL = initialURL ?? FileManager.default.homeDirectoryForCurrentUser
        return panel.runModal() == .OK ? panel.url : nil
    }

    func confirm(title: String, detail: String, actionTitle: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: ManagementLocalization.string("command.cancel"))
        alert.addButton(withTitle: actionTitle)
        return alert.runModal() == .alertSecondButtonReturn
    }

    func showWarning(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        if let parentWindow = parentWindow() {
            alert.beginSheetModal(for: parentWindow)
        } else {
            alert.runModal()
        }
    }

    func showInformation(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        if let parentWindow = parentWindow() {
            alert.beginSheetModal(for: parentWindow)
        } else {
            alert.runModal()
        }
    }

    func confirmFactoryReset(detail: String, completion: @escaping (Bool) -> Void) {
        guard let parentWindow = parentWindow() else {
            completion(false)
            return
        }
        let prompt = ResetConfirmationPrompt(detail: detail)
        resetPrompt = prompt
        prompt.present(for: parentWindow) { [weak self, weak prompt] confirmed in
            guard let self, let prompt, self.resetPrompt === prompt else {
                completion(false)
                return
            }
            self.resetPrompt = nil
            completion(confirmed)
        }
    }

    func editPortForwarding(
        mappings: [PortForwardMapping],
        save: @escaping ([PortForwardMapping]) -> String?,
        didClose: @escaping () -> Void
    ) {
        guard portEditor == nil, let parentWindow = parentWindow() else { return }
        let editor = PortForwardingEditor(
            mappings: mappings,
            save: save,
            didClose: { [weak self] in
                self?.portEditor = nil
                didClose()
            }
        )
        portEditor = editor
        editor.beginSheet(for: parentWindow)
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
