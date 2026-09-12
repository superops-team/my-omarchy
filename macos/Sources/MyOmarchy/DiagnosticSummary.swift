import Foundation

enum DiagnosticSummary {
    static func safeError(
        _ rawError: String,
        homeDirectory: String,
        sharedFolderPath: String?
    ) -> String {
        var result = LaunchDiagnosticsLog.redactSecrets(in: rawError)
        if let sharedFolderPath, !sharedFolderPath.isEmpty {
            result = result.replacingOccurrences(
                of: sharedFolderPath,
                with: "~/\(URL(fileURLWithPath: sharedFolderPath).lastPathComponent)"
            )
        }
        if !homeDirectory.isEmpty {
            result = result.replacingOccurrences(of: homeDirectory, with: "~")
        }
        return result
    }

    static func make(
        lifecycle: ManagementLifecycle,
        startupStage: ManagementStartupStage,
        rawError: String?,
        homeDirectory: String,
        sharedFolderPath: String?
    ) -> String {
        var lines = [
            "My Omarchy diagnostic summary",
            "Lifecycle: \(lifecycle.label)",
            "Startup stage: \(startupStage.label)",
        ]
        if let rawError, !rawError.isEmpty {
            let error = safeError(
                rawError,
                homeDirectory: homeDirectory,
                sharedFolderPath: sharedFolderPath
            )
            lines.append("Recent error: \(error)")
        }
        return lines.joined(separator: "\n")
    }
}

private extension ManagementLifecycle {
    var label: String {
        switch self {
        case .idle: "idle"
        case .launching: "launching"
        case .running: "running"
        case .stopping: "stopping"
        case .restarting: "restarting"
        case .failed: "failed"
        }
    }
}

private extension ManagementStartupStage {
    var label: String {
        switch self {
        case .none: "none"
        case .preflight: "preflight"
        case .launcherRunning: "launcher-running"
        case .qemuReady: "qemu-ready"
        case .exited: "exited"
        }
    }
}
