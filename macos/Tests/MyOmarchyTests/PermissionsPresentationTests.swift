import Testing
@testable import MyOmarchy

@Suite("Permissions presentation")
struct PermissionsPresentationTests {
    @Test("permission states expose only valid recovery actions")
    func permissionActions() {
        #expect(PermissionPresentation.make(kind: .microphone, state: .authorized).command == nil)
        #expect(PermissionPresentation.make(kind: .microphone, state: .notDetermined).command == .requestMicrophone)
        #expect(PermissionPresentation.make(kind: .microphone, state: .denied).command == .openMicrophoneSettings)
        #expect(PermissionPresentation.make(kind: .microphone, state: .restricted).command == nil)
        #expect(PermissionPresentation.make(kind: .accessibility, state: .unavailable).command == .requestAccessibility)
        #expect(PermissionPresentation.make(kind: .camera, state: .denied).command == .openCameraSettings)
    }
}
