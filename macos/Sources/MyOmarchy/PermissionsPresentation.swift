enum ManagementPermissionKind {
    case accessibility
    case microphone
    case camera
}

struct PermissionPresentation: Equatable {
    let statusKey: String
    let command: ManagementCommand?

    static func make(
        kind: ManagementPermissionKind,
        state: ManagementPermissionState
    ) -> Self {
        let statusKey: String = switch state {
        case .authorized: "permission.status.authorized"
        case .notDetermined: "permission.status.not_determined"
        case .denied: "permission.status.denied"
        case .restricted: "permission.status.restricted"
        case .unavailable: "permission.status.unavailable"
        }
        let command: ManagementCommand? = switch (kind, state) {
        case (.accessibility, .unavailable): .requestAccessibility
        case (.microphone, .notDetermined): .requestMicrophone
        case (.microphone, .denied): .openMicrophoneSettings
        case (.camera, .notDetermined): .requestCamera
        case (.camera, .denied): .openCameraSettings
        default: nil
        }
        return Self(statusKey: statusKey, command: command)
    }
}
