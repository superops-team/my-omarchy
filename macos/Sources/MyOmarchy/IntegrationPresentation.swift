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
                isRunning: isRunning
            ),
            portStatusKey: statusKey(
                configured: !details.portMappings.isEmpty,
                isRunning: isRunning
            )
        )
    }

    private static func statusKey(configured: Bool, isRunning: Bool) -> String {
        guard configured else { return "integration.status.not_configured" }
        return isRunning
            ? "integration.status.running"
            : "integration.status.configured_next_launch"
    }
}
