import AppKit
import Testing
@testable import MyOmarchy

@Suite("Management recovery", .serialized)
@MainActor
struct ManagementRecoveryTests {
    @Test("factory reset requires the exact application name")
    func resetConfirmationIsTypedAndExact() {
        let prompt = ResetConfirmationPrompt(detail: "This cannot be undone.")
        #expect(prompt.confirmationField.identifier?.rawValue == "reset-confirmation-field")
        #expect(!prompt.resetButton.isEnabled)

        for invalidValue in [
            "try omarchy",
            "TRY OMARCHY",
            "My Omarchy ",
            " My Omarchy",
        ] {
            prompt.confirmationField.stringValue = invalidValue
            NotificationCenter.default.post(
                name: NSControl.textDidChangeNotification,
                object: prompt.confirmationField
            )
            #expect(!prompt.resetButton.isEnabled)
        }

        prompt.confirmationField.stringValue = "My Omarchy"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: prompt.confirmationField
        )
        #expect(prompt.resetButton.isEnabled)
    }

    @Test("boot recovery promises preservation and never implies reset or upgrade")
    func bootRecoveryNotice() throws {
        let detail = try ManagementLocalization.text(
            "recovery.boot.detail",
            locale: "en"
        )
        #expect(detail.contains("one-time, read-only"))
        #expect(detail.contains("saved disk"))
        #expect(detail.contains("data remain intact"))
        #expect(detail.contains("does not reset"))
        #expect(detail.contains("upgrade Omarchy"))
    }

    @Test("boot recovery consent applies to one launch and retries at most once")
    func bootRecoveryGate() {
        var promptCount = 0
        let accepted = BootRecoveryLaunchGate.decide(
            preflight: .requiresConfirmation,
            confirm: {
                promptCount += 1
                return true
            }
        )
        #expect(promptCount == 1)
        #expect(accepted == .launch(allowBootRecovery: true))

        let consentRequired = VMExitPresentationDecision.make(
            status: VMExitPresentationDecision.bootRecoveryConsentRequiredStatus,
            reachedVirtualMachineStart: false,
            wasStopping: false
        )
        #expect(BootRecoveryChildExitGate.decide(
            presentation: consentRequired,
            launchWasAuthorized: true
        ) == .reportFailure)
    }
}
