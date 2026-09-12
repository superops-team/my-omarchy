struct IntegrationPresentation: Equatable {
    let sharedFolderStatusKey: String
    let portStatusKey: String

    static func make(
        details: ManagementDetails,
        lifecycle: ManagementLifecycle
    ) -> Self {
        let isRunning = lifecycle == .running || lifecycle == .stopping || lifecycle == .restarting
        return Self(
            sharedFolderStatusKey: statusKey(
                configured: details.sharedFolder.isEnabled
                    && details.sharedFolder.problem == nil,
                matchesActive: isRunning
                    && details.sharedFolder.path == details.activeSharedFolderPath
            ),
            portStatusKey: statusKey(
                configured: !details.portMappings.isEmpty,
                matchesActive: isRunning
                    && details.portMappings == details.activePortMappings
            )
        )
    }

    private static func statusKey(configured: Bool, matchesActive: Bool) -> String {
        guard configured else { return "integration.status.not_configured" }
        return matchesActive
            ? "integration.status.running"
            : "integration.status.configured_next_launch"
    }
}
