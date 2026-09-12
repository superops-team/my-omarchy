import Foundation
import Testing
@testable import MyOmarchy

@Suite("Overview presentation")
struct OverviewPresentationTests {
    @Test("each lifecycle exposes only its valid overview actions")
    func lifecycleMatrix() {
        let idle = OverviewPresentation.make(from: state(after: []))
        #expect(idle.statusKey == "overview.status.ready")
        #expect(idle.primaryCommand == .launch)
        #expect(idle.secondaryCommands.isEmpty)
        #expect(!idle.isBusy)

        let launching = OverviewPresentation.make(from: state(after: [
            .launchRequested(session: session),
        ]))
        #expect(launching.statusKey == "overview.status.launching")
        #expect(launching.primaryCommand == nil)
        #expect(launching.isBusy)
        #expect(launching.stageKey == "overview.stage.preflight")

        let running = OverviewPresentation.make(from: state(after: [
            .launchRequested(session: session),
            .virtualMachineReady(session: session),
        ]))
        #expect(running.statusKey == "overview.status.running")
        #expect(running.primaryCommand == .openVirtualMachine)
        #expect(running.secondaryCommands == [.stop, .restart])
        #expect(!running.isBusy)
        #expect(running.stageKey == "overview.stage.qemu_ready")

        let stopping = OverviewPresentation.make(from: state(after: [
            .launchRequested(session: session),
            .virtualMachineReady(session: session),
            .stopRequested(session: session),
        ]))
        #expect(stopping.statusKey == "overview.status.stopping")
        #expect(stopping.primaryCommand == nil)
        #expect(stopping.secondaryCommands.isEmpty)
        #expect(stopping.isBusy)

        let timedOut = OverviewPresentation.make(from: state(after: [
            .launchRequested(session: session),
            .virtualMachineReady(session: session),
            .stopRequested(session: session),
            .gracefulStopTimedOut(session: session),
        ]))
        #expect(timedOut.secondaryCommands == [.forceStop])

        let nextSession = UUID()
        let restarting = OverviewPresentation.make(from: state(after: [
            .launchRequested(session: session),
            .virtualMachineReady(session: session),
            .restartRequested(session: session, nextSession: nextSession),
        ]))
        #expect(restarting.statusKey == "overview.status.restarting")
        #expect(restarting.primaryCommand == nil)
        #expect(restarting.secondaryCommands.isEmpty)
        #expect(restarting.isBusy)
    }

    @Test("a launch failure stays visible and offers a retry")
    func failurePresentation() {
        let failed = OverviewPresentation.make(from: state(after: [
            .launchRequested(session: session),
            .childExited(session: session, status: 70),
        ]))

        #expect(failed.statusKey == "overview.status.failed")
        #expect(failed.primaryCommand == .launch)
        #expect(failed.lastExitStatus == 70)
        #expect(failed.stageKey == "overview.stage.exited")
    }

    private let session = UUID()

    private func state(after events: [ManagementEvent]) -> ManagementState {
        var state = ManagementState()
        for event in events {
            _ = state.apply(event)
        }
        return state
    }
}
