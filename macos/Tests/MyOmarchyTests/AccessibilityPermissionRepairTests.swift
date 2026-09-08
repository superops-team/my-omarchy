import Foundation
import Testing
@testable import MyOmarchy

@Suite("Accessibility permission repair", .serialized)
struct AccessibilityPermissionRepairTests {
    @Test("a successful scoped TCC reset is reported")
    func successfulReset() {
        #expect(
            AccessibilityPermissionRepair.resetStaleEntry(
                tccutilURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        )
    }

    @Test("a failed scoped TCC reset does not masquerade as success")
    func failedReset() {
        #expect(
            !AccessibilityPermissionRepair.resetStaleEntry(
                tccutilURL: URL(fileURLWithPath: "/usr/bin/false")
            )
        )
    }

    @Test("the repair is permanently scoped to this app")
    func fixedBundleIdentifier() {
        #expect(AccessibilityPermissionRepair.bundleIdentifier == "team.superops.myomarchy")
    }
}
