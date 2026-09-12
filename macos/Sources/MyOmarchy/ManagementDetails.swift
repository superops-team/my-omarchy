enum ManagementPermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unavailable
}

struct ManagementDetails: Equatable {
    var isImmersive: Bool = true
    var resourcePreference: VMResourceProfilePreference = .automatic
    var storage: StorageLocationMenuState = .defaultLocation
    var reclaimableStorage: String?
    var sharedFolder: SharedFolderMenuState = .disabled
    var portMappings: [PortForwardMapping] = []
    var audioOutput = "System Default"
    var audioInput = "System Default"
    var accessibility: ManagementPermissionState = .unavailable
    var microphone: ManagementPermissionState = .notDetermined
    var camera: ManagementPermissionState = .notDetermined
    var recentDiagnosticsLogPath: String?
    var recentErrorSummary: String?
    var canResetStorage = true
}
