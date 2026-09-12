import Foundation
import Testing
@testable import MyOmarchy

@Suite("Management state")
struct ManagementStateTests {
    @Test("the initial snapshot distinguishes readiness from VM lifecycle")
    func initialSnapshot() {
        let state = ManagementState()

        #expect(state.readiness == .unchecked)
        #expect(state.startupStage == .none)
        #expect(state.operation == .none)
        #expect(state.lifecycle == .idle)
    }

    @Test("a VM session follows the normal launch and stop lifecycle")
    func normalLifecycle() {
        let session = UUID()
        var state = ManagementState()

        #expect(state.lifecycle == .idle)
        let launchAccepted = state.apply(.launchRequested(session: session))
        #expect(launchAccepted)
        #expect(state.lifecycle == .launching)
        #expect(state.startupStage == .preflight)
        #expect(state.operation == .launch)
        #expect(state.sessionID == session)
        let launcherAccepted = state.apply(.launcherStarted(session: session))
        #expect(launcherAccepted)
        #expect(state.startupStage == .launcherRunning)
        let readyAccepted = state.apply(.virtualMachineReady(session: session))
        #expect(readyAccepted)
        #expect(state.lifecycle == .running)
        #expect(state.startupStage == .qemuReady)
        #expect(state.operation == .none)
        let stopAccepted = state.apply(.stopRequested(session: session))
        #expect(stopAccepted)
        #expect(state.lifecycle == .stopping)
        let exitAccepted = state.apply(.childExited(session: session, status: 0))
        #expect(exitAccepted)
        #expect(state.lifecycle == .idle)
        #expect(state.sessionID == nil)
    }

    @Test("events from an older session cannot change the active VM")
    func staleSessionEventsAreIgnored() {
        let stale = UUID()
        let current = UUID()
        var state = ManagementState()

        _ = state.apply(.launchRequested(session: current))
        let staleReady = state.apply(.virtualMachineReady(session: stale))
        let staleExit = state.apply(.childExited(session: stale, status: 1))

        #expect(!staleReady)
        #expect(!staleExit)
        #expect(state.lifecycle == .launching)
        #expect(state.sessionID == current)
    }

    @Test("a child failure during launch remains visible until a new session starts")
    func launchFailurePersists() {
        let failedSession = UUID()
        let retrySession = UUID()
        var state = ManagementState()

        _ = state.apply(.launchRequested(session: failedSession))
        let failureAccepted = state.apply(.childExited(session: failedSession, status: 70))

        #expect(failureAccepted)
        #expect(state.lifecycle == .failed)
        #expect(state.lastExitStatus == 70)
        #expect(state.sessionID == failedSession)

        let retryAccepted = state.apply(.launchRequested(session: retrySession))
        #expect(retryAccepted)
        #expect(state.lifecycle == .launching)
        #expect(state.lastExitStatus == nil)
        #expect(state.sessionID == retrySession)
    }

    @Test("restart waits for the running child to exit before creating a new session")
    func restartIsSequential() {
        let runningSession = UUID()
        let restartSession = UUID()
        var state = ManagementState()

        _ = state.apply(.launchRequested(session: runningSession))
        _ = state.apply(.virtualMachineReady(session: runningSession))

        let restartAccepted = state.apply(
            .restartRequested(session: runningSession, nextSession: restartSession)
        )
        #expect(restartAccepted)
        #expect(state.lifecycle == .restarting)
        #expect(state.sessionID == runningSession)

        let duplicateLaunch = state.apply(.launchRequested(session: restartSession))
        #expect(!duplicateLaunch)

        let exitAccepted = state.apply(.childExited(session: runningSession, status: 0))
        #expect(exitAccepted)
        #expect(state.lifecycle == .launching)
        #expect(state.sessionID == restartSession)
    }

    @Test("force stop becomes available only after the graceful stop timeout")
    func forceStopRequiresTimeout() {
        let session = UUID()
        var state = ManagementState()
        _ = state.apply(.launchRequested(session: session))
        _ = state.apply(.virtualMachineReady(session: session))
        _ = state.apply(.stopRequested(session: session))

        #expect(!state.forceStopAvailable)
        #expect(!ManagementCommandPolicy.allows(.forceStop, in: state))
        let timeoutAccepted = state.apply(.gracefulStopTimedOut(session: session))
        #expect(timeoutAccepted)
        #expect(state.forceStopAvailable)
        #expect(ManagementCommandPolicy.allows(.forceStop, in: state))
    }
}
