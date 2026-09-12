enum ManagementCommand: Equatable {
    case launch
    case openVirtualMachine
    case stop
    case forceStop
    case restart
    case resetStorage
    case setImmersive(Bool)
    case setResourceProfile(VMResourceProfilePreference)
    case chooseStorageLocation
    case useDefaultStorageLocation
    case openStorageLocation
    case chooseSharedFolder
    case setSharedFolderEnabled(Bool)
    case editPortForwarding
    case requestAccessibility
    case requestMicrophone
    case requestCamera
    case openMicrophoneSettings
    case openCameraSettings
    case openDiagnosticsLog
    case copyDiagnosticSummary
}

enum ManagementCommandPolicy {
    static func allows(
        _ command: ManagementCommand,
        while lifecycle: ManagementLifecycle
    ) -> Bool {
        switch (command, lifecycle) {
        case (.launch, .idle), (.launch, .failed):
            true
        case (.stop, .running), (.restart, .running):
            true
        case (.openVirtualMachine, .running):
            true
        case (.resetStorage, .idle), (.resetStorage, .failed):
            true
        case (.setImmersive, .idle), (.setImmersive, .failed),
             (.setResourceProfile, .idle), (.setResourceProfile, .failed),
             (.chooseStorageLocation, .idle), (.chooseStorageLocation, .failed),
             (.useDefaultStorageLocation, .idle), (.useDefaultStorageLocation, .failed):
            true
        case (.chooseSharedFolder, _), (.setSharedFolderEnabled, _),
             (.editPortForwarding, _), (.requestAccessibility, _),
             (.requestMicrophone, _), (.requestCamera, _),
             (.openMicrophoneSettings, _), (.openCameraSettings, _),
             (.openStorageLocation, _), (.openDiagnosticsLog, _),
             (.copyDiagnosticSummary, _):
            true
        default:
            false
        }
    }

    static func allows(_ command: ManagementCommand, in state: ManagementState) -> Bool {
        if command == .forceStop {
            return state.lifecycle == .stopping && state.forceStopAvailable
        }
        return allows(command, while: state.lifecycle)
    }
}
