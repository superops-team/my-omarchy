import AppKit

enum ManagementRecoveryPresentation {
    static var incompatibleWorkspaceDetail: String {
        ManagementLocalization.string("recovery.incompatible.detail")
    }

    static var bootRecoveryConfirmationTitle: String {
        ManagementLocalization.string("recovery.boot.title")
    }

    static var bootRecoveryConfirmationDetail: String {
        ManagementLocalization.string("recovery.boot.detail")
    }
}

enum ResetConfirmationPolicy {
    static let requiredText = "My Omarchy"

    static func allowsReset(_ text: String) -> Bool {
        text == requiredText
    }
}

@MainActor
final class ResetConfirmationPrompt {
    let alert: NSAlert
    let confirmationField: NSTextField
    let resetButton: NSButton

    private var textChangeObserver: NSObjectProtocol?

    init(detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = ManagementLocalization.string("reset.confirm.title")
        alert.informativeText = detail
        alert.addButton(withTitle: ManagementLocalization.string("command.cancel"))
        let resetButton = alert.addButton(withTitle: ManagementLocalization.string("reset.confirm.action"))
        resetButton.hasDestructiveAction = true
        resetButton.isEnabled = false

        let instruction = NSTextField(
            labelWithString: String(
                format: ManagementLocalization.string("reset.confirm.instruction"),
                ResetConfirmationPolicy.requiredText
            )
        )
        instruction.font = .systemFont(ofSize: 12, weight: .medium)
        instruction.translatesAutoresizingMaskIntoConstraints = false

        let confirmationField = NSTextField(string: "")
        confirmationField.placeholderString = ResetConfirmationPolicy.requiredText
        confirmationField.identifier = NSUserInterfaceItemIdentifier("reset-confirmation-field")
        confirmationField.setAccessibilityLabel(
            String(
                format: ManagementLocalization.string("reset.confirm.accessibility"),
                ResetConfirmationPolicy.requiredText
            )
        )
        confirmationField.translatesAutoresizingMaskIntoConstraints = false

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 52))
        accessory.addSubview(instruction)
        accessory.addSubview(confirmationField)
        NSLayoutConstraint.activate([
            instruction.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            instruction.trailingAnchor.constraint(lessThanOrEqualTo: accessory.trailingAnchor),
            instruction.topAnchor.constraint(equalTo: accessory.topAnchor),
            confirmationField.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            confirmationField.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            confirmationField.topAnchor.constraint(equalTo: instruction.bottomAnchor, constant: 7),
            confirmationField.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
        ])
        alert.accessoryView = accessory

        self.alert = alert
        self.confirmationField = confirmationField
        self.resetButton = resetButton
        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification,
            object: confirmationField,
            queue: .main
        ) { [weak confirmationField, weak resetButton] _ in
            resetButton?.isEnabled = ResetConfirmationPolicy.allowsReset(
                confirmationField?.stringValue ?? ""
            )
        }
    }

    deinit {
        if let textChangeObserver {
            NotificationCenter.default.removeObserver(textChangeObserver)
        }
    }

    func present(for window: NSWindow, completion: @escaping (Bool) -> Void) {
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                completion(false)
                return
            }
            completion(
                response == .alertSecondButtonReturn
                    && ResetConfirmationPolicy.allowsReset(confirmationField.stringValue)
            )
        }
        DispatchQueue.main.async { [weak window, weak confirmationField] in
            guard let window, let confirmationField else { return }
            window.makeFirstResponder(confirmationField)
        }
    }
}
