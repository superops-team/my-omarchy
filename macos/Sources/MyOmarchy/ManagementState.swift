import Foundation

enum ManagementLifecycle: Equatable {
    case idle
    case launching
    case running
    case stopping
    case restarting
    case failed
}

enum ManagementReadiness: Equatable {
    case unchecked
    case ready
    case blocked
}

enum ManagementStartupStage: Equatable {
    case none
    case preflight
    case launcherRunning
    case qemuReady
    case exited
}

enum ManagementOperation: Equatable {
    case none
    case launch
    case stop
    case restart
    case resetStorage
}

enum ManagementEvent: Equatable {
    case launchRequested(session: UUID)
    case launcherStarted(session: UUID)
    case virtualMachineReady(session: UUID)
    case stopRequested(session: UUID)
    case restartRequested(session: UUID, nextSession: UUID)
    case gracefulStopTimedOut(session: UUID)
    case resetRequested
    case resetCancelled
    case resetFinished(status: Int32)
    case launchFailed(message: String)
    case childExited(session: UUID, status: Int32)
}

struct ManagementState: Equatable {
    private(set) var lifecycle: ManagementLifecycle = .idle
    private(set) var readiness: ManagementReadiness = .unchecked
    private(set) var startupStage: ManagementStartupStage = .none
    private(set) var operation: ManagementOperation = .none
    private(set) var sessionID: UUID?
    private(set) var lastExitStatus: Int32?
    private(set) var lastFailureSummary: String?
    private(set) var forceStopAvailable = false
    private var pendingRestartSession: UUID?

    @discardableResult
    mutating func apply(_ event: ManagementEvent) -> Bool {
        switch event {
        case .launchRequested(let session) where lifecycle == .idle || lifecycle == .failed:
            sessionID = session
            lifecycle = .launching
            startupStage = .preflight
            operation = .launch
            lastExitStatus = nil
            lastFailureSummary = nil
            forceStopAvailable = false
        case .launcherStarted(let session)
            where lifecycle == .launching && sessionID == session:
            startupStage = .launcherRunning
        case .virtualMachineReady(let session)
            where lifecycle == .launching && sessionID == session:
            lifecycle = .running
            readiness = .ready
            startupStage = .qemuReady
            operation = .none
        case .stopRequested(let session)
            where lifecycle == .running && sessionID == session:
            lifecycle = .stopping
            operation = .stop
            forceStopAvailable = false
        case .restartRequested(let session, let nextSession)
            where lifecycle == .running && sessionID == session:
            lifecycle = .restarting
            operation = .restart
            pendingRestartSession = nextSession
            forceStopAvailable = false
        case .gracefulStopTimedOut(let session)
            where (lifecycle == .stopping || lifecycle == .restarting)
                && sessionID == session:
            forceStopAvailable = true
        case .resetRequested where (lifecycle == .idle || lifecycle == .failed)
            && operation == .none:
            operation = .resetStorage
        case .resetCancelled where operation == .resetStorage:
            operation = .none
        case .resetFinished(let status) where operation == .resetStorage:
            operation = .none
            lifecycle = status == 0 ? .idle : .failed
            if status == 0 {
                lastFailureSummary = nil
                lastExitStatus = nil
            } else {
                lastExitStatus = status
            }
        case .launchFailed(let message) where lifecycle == .idle || lifecycle == .failed:
            lifecycle = .failed
            if startupStage == .none { startupStage = .preflight }
            operation = .none
            lastFailureSummary = message
        case .childExited(let session, _)
            where lifecycle == .stopping && sessionID == session:
            lifecycle = .idle
            startupStage = .exited
            operation = .none
            sessionID = nil
            forceStopAvailable = false
        case .childExited(let session, let status)
            where lifecycle == .launching && sessionID == session:
            lifecycle = .failed
            startupStage = .exited
            operation = .none
            lastExitStatus = status
            lastFailureSummary = nil
        case .childExited(let session, let status)
            where lifecycle == .running && sessionID == session:
            lifecycle = status == 0 ? .idle : .failed
            startupStage = .exited
            operation = .none
            lastExitStatus = status == 0 ? nil : status
            if status == 0 { sessionID = nil }
        case .childExited(let session, _)
            where lifecycle == .restarting && sessionID == session:
            guard let nextSession = pendingRestartSession else { return false }
            lifecycle = .launching
            startupStage = .preflight
            operation = .launch
            sessionID = nextSession
            pendingRestartSession = nil
        default:
            return false
        }
        return true
    }
}
