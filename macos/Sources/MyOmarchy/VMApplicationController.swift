import AppKit
import ApplicationServices
import Darwin
import Foundation

@MainActor
final class HostPowerNotificationObserver {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onWillSleep: @escaping @MainActor () -> Void,
        onDidWake: @escaping @MainActor () -> Void
    ) {
        self.center = center
        tokens = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onWillSleep()
                }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onDidWake()
                }
            },
        ]
    }

    func stop() {
        for token in tokens {
            center.removeObserver(token)
        }
        tokens = []
    }
}

@MainActor
final class VMApplicationController: NSObject, NSApplicationDelegate {
    private let launcherURL: URL
    private let initialArguments: [String]
    private let baseEnvironment: [String: String]
    private let supervisor: any QEMUGPUProcessSupervising
    private let preferenceStore: AudioRoutingPreferenceStore
    private let sharedFolderStore: SharedFolderPreferenceStore
    private let portForwardingStore: PortForwardingPreferenceStore
    private let fullscreenPreferenceStore: FullscreenPreferenceStore
    private let resourceProfilePreferenceStore: VMResourceProfilePreferenceStore
    private let storageLocationStore: StorageLocationPreferenceStore
    private let volumeProbe: VolumeProbing
    private let volumeRootDetector: VolumeRootDetecting
    private let deviceProvider: HostAudioDeviceProviding
    private let bundledMetrics: BundledGuestMetrics?
    private let managementViewModel: ManagementViewModel
    private let runtimeControllerFactory: (String) -> VMRuntimeController
    private let windowActivator: VirtualMachineWindowActivator
    private let scheduleGracefulStopTimeout: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
    private(set) var managementWindow: ManagementWindow?
    private lazy var managementPresenter = ManagementAppKitPresenter { [weak self] in
        self?.managementWindow?.window
    }
    private var volumeObserver: NSObjectProtocol?
    private var hostPowerObserver: HostPowerNotificationObserver?
    private let hostSleepCoordinator = VMHostSleepCoordinator()

    /// The workspace the running VM is writing to, so an unmount of its volume
    /// can be recognized as the disk disappearing under QEMU.
    private var activeStateRoot: String?

    private var lifecycle = VMRunLifecycle()
    private var childRunning = false
    private var applicationTerminationPending = false
    private var virtualMachineReachedStart = false
    private var activeLaunchAllowedBootRecovery = false
    private var pendingHostSleepControlFailure: String?
    private var activeManagementSession: UUID?
    private var activeRuntimeController: VMRuntimeController?
    private var activeQEMUProcessIdentifier: Int32?
    private var activeSharedFolderPath: String?
    private var activePortMappings: [PortForwardMapping] = []
    private var pendingInitialReset: Bool
    private var virtualMachineReadyDate: Date?

    /// True while a modal alert this controller opened itself (rather than
    /// AppKit) is on screen awaiting a click. `finish()`'s watchdog checks
    /// this so it never yanks a dialog out from under the user; it reschedules
    /// instead of firing while this is true.
    private var isPresentingBlockingAlert = false

    private(set) var exitStatus: Int32 = 0

    init(
        launcherURL: URL,
        initialArguments: [String],
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        supervisor: any QEMUGPUProcessSupervising = QEMUGPUProcessSupervisor(),
        preferenceStore: AudioRoutingPreferenceStore = AudioRoutingPreferenceStore(),
        sharedFolderStore: SharedFolderPreferenceStore = SharedFolderPreferenceStore(),
        portForwardingStore: PortForwardingPreferenceStore = PortForwardingPreferenceStore(),
        fullscreenPreferenceStore: FullscreenPreferenceStore = FullscreenPreferenceStore(),
        resourceProfilePreferenceStore: VMResourceProfilePreferenceStore = VMResourceProfilePreferenceStore(),
        storageLocationStore: StorageLocationPreferenceStore = StorageLocationPreferenceStore(),
        volumeProbe: VolumeProbing = URLVolumeProbe(),
        volumeRootDetector: VolumeRootDetecting = FileManagerVolumeRootDetector(),
        deviceProvider: HostAudioDeviceProviding = CoreAudioHostAudioDeviceProvider(),
        bundledMetrics: BundledGuestMetrics? = QEMUGPUStorageSpaceEstimate.bundledMetrics(),
        managementViewModel: ManagementViewModel? = nil,
        runtimeControllerFactory: @escaping (String) -> VMRuntimeController = {
            VMRuntimeController(socketPath: $0)
        },
        windowActivator: VirtualMachineWindowActivator = VirtualMachineWindowActivator(),
        scheduleGracefulStopTimeout: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: action)
        }
    ) {
        self.launcherURL = launcherURL
        self.initialArguments = initialArguments
        self.baseEnvironment = baseEnvironment
        self.supervisor = supervisor
        self.preferenceStore = preferenceStore
        self.sharedFolderStore = sharedFolderStore
        self.portForwardingStore = portForwardingStore
        self.fullscreenPreferenceStore = fullscreenPreferenceStore
        self.resourceProfilePreferenceStore = resourceProfilePreferenceStore
        self.storageLocationStore = storageLocationStore
        self.volumeProbe = volumeProbe
        self.volumeRootDetector = volumeRootDetector
        self.deviceProvider = deviceProvider
        self.bundledMetrics = bundledMetrics
        self.managementViewModel = managementViewModel ?? ManagementViewModel { _ in }
        self.runtimeControllerFactory = runtimeControllerFactory
        self.windowActivator = windowActivator
        self.scheduleGracefulStopTimeout = scheduleGracefulStopTimeout
        pendingInitialReset = initialArguments.first == QEMUGPUStorageOption.resetStorage.rawValue
            || initialArguments.first == QEMUGPUStorageOption.resetStorageOnly.rawValue
        super.init()
        self.managementViewModel.connect { [weak self] command in
            self?.performManagementCommand(command)
        }
    }

    @discardableResult
    func recordManagementEvent(_ event: ManagementEvent) -> Bool {
        let accepted = managementViewModel.publish(event: event)
        if accepted, case .launchRequested(let session) = event {
            activeManagementSession = session
        }
        if accepted {
            refreshManagementDetails()
        }
        return accepted
    }

    @discardableResult
    func connectManagementRuntime(
        qmpSocketPath: String,
        processIdentifier: Int32
    ) -> Bool {
        guard processIdentifier > 1 else { return false }
        activeRuntimeController = runtimeControllerFactory(qmpSocketPath)
        activeQEMUProcessIdentifier = processIdentifier
        return true
    }

    func openVirtualMachineWindow() -> Bool {
        guard let activeQEMUProcessIdentifier else { return false }
        return windowActivator.activate(processIdentifier: activeQEMUProcessIdentifier)
    }

    @discardableResult
    func requestGracefulStop() throws -> Bool {
        guard let session = activeManagementSession,
              let activeRuntimeController else { return false }
        try activeRuntimeController.requestGracefulShutdown()
        let accepted = recordManagementEvent(.stopRequested(session: session))
        if accepted {
            scheduleGracefulStopTimeout { [weak self] in
                guard let self, self.activeManagementSession == session else { return }
                _ = self.recordManagementEvent(.gracefulStopTimedOut(session: session))
            }
        }
        return accepted
    }

    @discardableResult
    func requestGracefulRestart(nextSession: UUID) throws -> Bool {
        guard let session = activeManagementSession,
              let activeRuntimeController else { return false }
        try activeRuntimeController.requestGracefulShutdown()
        let accepted = recordManagementEvent(
            .restartRequested(session: session, nextSession: nextSession)
        )
        if accepted {
            scheduleGracefulStopTimeout { [weak self] in
                guard let self, self.activeManagementSession == session else { return }
                _ = self.recordManagementEvent(.gracefulStopTimedOut(session: session))
            }
        }
        return accepted
    }

    func launchPreparedVirtualMachine(session: UUID) throws {
        try launch(arguments: launchArguments(), managementSession: session)
    }

    func refreshManagementDetails() {
        let audioPreferences = preferenceStore.load()
        let resourcePreference = resourceProfilePreferenceStore.load()
        let effectiveResourceProfile = VMResourceLaunchConfiguration.make(
            baseEnvironment: [:],
            preference: resourcePreference
        ).profile
        let sharedFolder = sharedFolderMenuState()
        let rawError = managementViewModel.state.lastFailureSummary
            ?? supervisor.recentStandardError
        let recentError = managementViewModel.state.lifecycle == .failed
            ? DiagnosticSummary.safeError(
                rawError,
                homeDirectory: Self.homeDirectory,
                sharedFolderPath: sharedFolder.path
            )
            : nil
        managementViewModel.publish(details: ManagementDetails(
            isImmersive: fullscreenPreferenceStore.load().isImmersive,
            resourcePreference: resourcePreference,
            effectiveResourceProfile: effectiveResourceProfile,
            storage: storageLocationMenuState(),
            reclaimableStorage: QEMUGPUStorageSpaceEstimate.formattedReclaimableSpace(
                environment: baseEnvironment,
                bundleIdentity: bundledMetrics?.identity,
                preference: storageLocationStore.load()
            ),
            logicalDiskSize: bundledMetrics.map {
                StorageLocationPolicy.format(bytes: $0.workingDiskBytes)
            },
            sharedFolder: sharedFolder,
            portMappings: portForwardingStore.load(),
            activeSharedFolderPath: activeSharedFolderPath,
            activePortMappings: activePortMappings,
            audioOutput: Self.audioRouteName(audioPreferences.output),
            audioInput: Self.audioRouteName(audioPreferences.input),
            accessibility: AXIsProcessTrusted() ? .authorized : .unavailable,
            microphone: Self.managementPermission(MicrophonePreflight.authorizationState()),
            camera: Self.managementPermission(CameraPreflight.authorizationState()),
            recentDiagnosticsLogPath: supervisor.recentDiagnosticsLogPath,
            recentErrorSummary: recentError,
            canResetStorage: initialArguments.first != QEMUGPUStorageOption.ephemeral.rawValue,
            readyDate: virtualMachineReadyDate
        ))
    }

    private static func audioRouteName(_ route: AudioRouteSelection) -> String {
        switch route {
        case .systemDefault: ManagementLocalization.string("integration.audio.system_default")
        case .device(_, let lastKnownName): lastKnownName
        }
    }

    private static func managementPermission(
        _ state: MicrophoneAuthorizationState
    ) -> ManagementPermissionState {
        switch state {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        }
    }

    private static func managementPermission(
        _ state: CameraAuthorizationState
    ) -> ManagementPermissionState {
        switch state {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        }
    }

    private func performManagementCommand(_ command: ManagementCommand) {
        do {
            switch command {
            case .launch:
                startVirtualMachine()
            case .openVirtualMachine:
                _ = openVirtualMachineWindow()
            case .stop:
                _ = try requestGracefulStop()
            case .forceStop:
                supervisor.forward(signal: SIGKILL)
            case .restart:
                _ = try requestGracefulRestart(nextSession: UUID())
            case .resetStorage:
                guard recordManagementEvent(.resetRequested) else { return }
                confirmAndResetVirtualMachine()
            case .setImmersive(let isImmersive):
                fullscreenPreferenceStore.save(
                    FullscreenPreferences(isImmersive: isImmersive)
                )
                refreshManagementDetails()
            case .setResourceProfile(let preference):
                resourceProfilePreferenceStore.save(preference)
                refreshManagementDetails()
            case .chooseStorageLocation:
                presentStorageLocationPicker()
            case .openStorageLocation:
                openStorageLocationInFinder()
            case .chooseSharedFolder:
                presentSharedFolderPicker()
            case .editPortForwarding:
                presentPortForwardingEditor()
            case .requestAccessibility:
                requestOptionalAccessibilityPermission()
                refreshManagementDetails()
            case .requestMicrophone:
                MicrophonePreflight.requestAccess { [weak self] _ in
                    DispatchQueue.main.async { self?.refreshManagementDetails() }
                }
            case .requestCamera:
                CameraPreflight.requestAccess { [weak self] _ in
                    DispatchQueue.main.async { self?.refreshManagementDetails() }
                }
            case .openMicrophoneSettings:
                openPrivacySettings(pane: "Privacy_Microphone")
            case .openCameraSettings:
                openPrivacySettings(pane: "Privacy_Camera")
            case .openDiagnosticsLog:
                openDiagnosticsLogFolder()
            case .copyDiagnosticSummary:
                copyDiagnosticSummary()
            case .useDefaultStorageLocation:
                useDefaultStorageLocation()
                refreshManagementDetails()
            case .setSharedFolderEnabled(let enabled):
                setSharedFolderEnabled(enabled)
                refreshManagementDetails()
            }
        } catch {
            fputs("my-omarchy: management command failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func presentStorageLocationPicker() {
        let current = storageLocationMenuState().containerPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        guard let selected = managementPresenter.chooseDirectory(
            title: ManagementLocalization.string("storage.picker.title"),
            message: ManagementLocalization.string("storage.picker.message"),
            prompt: ManagementLocalization.string("storage.picker.action"),
            initialURL: current
        ) else { return }
        if let problem = validateStorageLocation(selected.path) {
            managementPresenter.showWarning(
                title: ManagementLocalization.string("storage.invalid.title"),
                detail: problem
            )
            return
        }
        let destination = StorageLocationPolicy.stateRoot(forContainer: selected.path)
        guard managementPresenter.confirm(
            title: ManagementLocalization.string("storage.confirm.title"),
            detail: String(
                format: ManagementLocalization.string("storage.confirm.detail"),
                destination
            ),
            actionTitle: ManagementLocalization.string("storage.confirm.action")
        ) else { return }
        if let problem = chooseStorageLocation(selected.path) {
            managementPresenter.showWarning(
                title: ManagementLocalization.string("storage.invalid.title"),
                detail: problem
            )
        }
        refreshManagementDetails()
    }

    private func openStorageLocationInFinder() {
        guard let url = QEMUGPUStorageSpaceEstimate.dataDirectoryURL(
            environment: baseEnvironment,
            preference: storageLocationStore.load()
        ) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            guard storageLocationMenuState().isDefault else {
                managementPresenter.showWarning(
                    title: ManagementLocalization.string("storage.open_failed.title"),
                    detail: ManagementLocalization.string("storage.open_failed.detail")
                )
                return
            }
            try? FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        _ = managementPresenter.open(url)
    }

    private func presentSharedFolderPicker() {
        let current = sharedFolderMenuState().path.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        guard let selected = managementPresenter.chooseDirectory(
            title: ManagementLocalization.string("shared_folder.picker.title"),
            message: ManagementLocalization.string("shared_folder.picker.message"),
            prompt: ManagementLocalization.string("shared_folder.picker.action"),
            initialURL: current
        ) else { return }
        if let problem = chooseSharedFolder(selected.path) {
            managementPresenter.showWarning(
                title: ManagementLocalization.string("shared_folder.invalid.title"),
                detail: problem
            )
        }
        refreshManagementDetails()
    }

    private func presentPortForwardingEditor() {
        managementPresenter.editPortForwarding(
            mappings: portForwardingStore.load(),
            save: { [weak self] mappings in self?.savePortForwarding(mappings) },
            didClose: { [weak self] in self?.refreshManagementDetails() }
        )
    }

    private func confirmAndResetVirtualMachine() {
        var detail = ManagementLocalization.string("reset.confirm.detail")
        if let estimate = managementViewModel.details.reclaimableStorage {
            detail += " " + String(
                format: ManagementLocalization.string("reset.confirm.space"),
                estimate
            )
        }
        managementPresenter.confirmFactoryReset(detail: detail) { [weak self] confirmed in
            guard let self else { return }
            guard confirmed else {
                _ = self.recordManagementEvent(.resetCancelled)
                return
            }
            self.resetVirtualMachine()
        }
    }

    private func openPrivacySettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        _ = managementPresenter.open(url)
    }

    private func openDiagnosticsLogFolder() {
        guard let path = supervisor.recentDiagnosticsLogPath else { return }
        _ = managementPresenter.open(
            URL(fileURLWithPath: path).deletingLastPathComponent()
        )
    }

    private func copyDiagnosticSummary() {
        let summary = DiagnosticSummary.make(
            lifecycle: managementViewModel.state.lifecycle,
            startupStage: managementViewModel.state.startupStage,
            rawError: managementViewModel.details.recentErrorSummary,
            homeDirectory: Self.homeDirectory,
            sharedFolderPath: managementViewModel.details.sharedFolder.path
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeVolumeUnmounts()
        observeHostPowerEvents()
        showManagementWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshManagementDetails()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showManagementWindow()
        return true
    }

    @objc func openManagementWindow(_ sender: Any?) {
        showManagementWindow()
    }

    private func showManagementWindow() {
        if managementWindow == nil {
            managementWindow = ManagementWindow(
                viewModel: managementViewModel,
                navigation: ManagementNavigation()
            )
        }
        refreshManagementDetails()
        managementWindow?.show()

        if pendingInitialReset {
            pendingInitialReset = false
            _ = managementViewModel.send(.resetStorage)
        }
    }

    private func startVirtualMachine(allowBootRecovery: Bool = false) {
        cancelHostWakeRetry()
        virtualMachineReachedStart = false
        pendingHostSleepControlFailure = nil
        do {
            let accessibilityDecision = AccessibilityLaunchDecision.make(
                for: AXIsProcessTrusted() ? .authorized : .unavailable
            )
            if let warning = accessibilityDecision.warning {
                fputs("[input-bridge] \(warning)\n", stderr)
            }
            guard accessibilityDecision.allowsLaunch else {
                throw HelperError.io("accessibility policy unexpectedly prevented launch")
            }
            let microphoneDecision = MicrophonePreflight.decision()
            if let warning = microphoneDecision.warning {
                fputs("[audio] \(warning)\n", stderr)
            }
            guard microphoneDecision.allowsLaunch else {
                throw HelperError.io("microphone policy unexpectedly prevented audio playback")
            }
            // Switching to the default is an acceptable way to start a VM, so
            // both `.available` and `.switchedToDefault` proceed here.
            guard resolveStorageLocationAvailability() != .cancelled else {
                return
            }
            var approvedBootRecovery = allowBootRecovery
            if !approvedBootRecovery {
                let preflight: BootRecoveryLaunchPreflight
                if initialArguments.first == QEMUGPUStorageOption.ephemeral.rawValue {
                    preflight = .notRequired
                } else {
                    preflight = QEMUGPUStorageSpaceEstimate.bootRecoveryPreflight(
                        environment: baseEnvironment,
                        bundleIdentity: bundledMetrics?.identity,
                        preference: storageLocationStore.load()
                    )
                }
                switch BootRecoveryLaunchGate.decide(
                    preflight: preflight,
                    confirm: { [weak self] in
                        self?.managementPresenter.confirm(
                            title: ManagementRecoveryPresentation.bootRecoveryConfirmationTitle,
                            detail: ManagementRecoveryPresentation.bootRecoveryConfirmationDetail,
                            actionTitle: ManagementLocalization.string("recovery.boot.action")
                        ) ?? false
                    }
                ) {
                case .cancel:
                    return
                case .launch(let allowBootRecovery):
                    approvedBootRecovery = allowBootRecovery
                }
            }
            let cameraDecision = CameraPreflight.decision()
            if let warning = cameraDecision.warning {
                fputs("[camera] \(warning)\n", stderr)
            }
            guard cameraDecision.allowsLaunch else {
                throw HelperError.io("camera policy unexpectedly prevented launch")
            }
            try launch(
                arguments: launchArguments(),
                allowBootRecovery: approvedBootRecovery
            )
        } catch {
            failLaunch(error)
        }
    }

    private func launchArguments() -> [String] {
        var arguments = initialArguments
        let resetOptions = [
            QEMUGPUStorageOption.resetStorage.rawValue,
            QEMUGPUStorageOption.resetStorageOnly.rawValue,
        ]
        if let first = arguments.first, resetOptions.contains(first) {
            arguments.removeFirst()
        }
        return arguments
    }

    private func resetArguments() -> [String] {
        var arguments = launchArguments()
        arguments.insert(QEMUGPUStorageOption.resetStorageOnly.rawValue, at: 0)
        return arguments
    }

    private func resetVirtualMachine() {
        // Unlike launch, a reset that lands on the default workspace after the
        // chosen drive went missing would erase a VM the user never confirmed.
        // Switching the setting is allowed; erasing on that same click is not,
        // so the reset is abandoned and they get an accurate confirmation the
        // next time they ask for one.
        guard resolveStorageLocationAvailability() == .available else {
            _ = recordManagementEvent(.resetFinished(status: 1))
            return
        }
        do {
            let context = childLaunchContext()
            if let reason = context.storageUnavailableReason {
                managementPresenter.showWarning(
                    title: ManagementLocalization.string("reset.failed.title"),
                    detail: reason
                )
                _ = recordManagementEvent(.resetFinished(status: 1))
                return
            }
            if let reason = context.resourceUnavailableReason {
                managementPresenter.showWarning(
                    title: ManagementLocalization.string("reset.failed.title"),
                    detail: reason
                )
                _ = recordManagementEvent(.resetFinished(status: 1))
                return
            }
            activeStateRoot = context.stateRoot
            try supervisor.start(
                executableURL: launcherURL,
                arguments: resetArguments(),
                environment: QEMUGPURuntimeEnvironment.sanitizedForReset(context.environment)
            ) { [weak self] status in
                self?.resetDidExit(status: status)
            }
            childRunning = true
        } catch {
            managementPresenter.showWarning(
                title: ManagementLocalization.string("reset.failed.title"),
                detail: error.localizedDescription
            )
            _ = recordManagementEvent(.resetFinished(status: 1))
        }
    }

    private func resetDidExit(status: Int32) {
        guard childRunning else { return }
        childRunning = false
        cancelHostWakeRetry()
        hostSleepCoordinator.disconnect()
        let wasStopping = lifecycle.isStopping
        lifecycle.childExited()
        _ = recordManagementEvent(.resetFinished(status: status))
        if applicationTerminationPending {
            NSApp.reply(toApplicationShouldTerminate: true)
        } else if wasStopping {
            finish(status: status)
        } else if status == 0 {
            managementPresenter.showInformation(
                title: ManagementLocalization.string("reset.success.title"),
                detail: ManagementLocalization.string("reset.success.detail")
            )
        } else {
            managementPresenter.showWarning(
                title: ManagementLocalization.string("reset.failed.title"),
                detail: ManagementLocalization.string("reset.failed.detail")
            )
        }
        refreshManagementDetails()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard childRunning else { return .terminateNow }
        guard !applicationTerminationPending else { return .terminateLater }

        cancelHostWakeRetry()
        applicationTerminationPending = true
        lifecycle.requestQuit()
        supervisor.forward(signal: SIGTERM)
        return .terminateLater
    }

    func handleTerminationSignal(_ signal: Int32) {
        guard !applicationTerminationPending else { return }
        cancelHostWakeRetry()
        lifecycle.requestTermination(signal: signal)
        if childRunning {
            supervisor.forward(signal: signal)
        } else {
            finish(status: 128 + signal)
        }
    }

    private struct ChildLaunchContext {
        let environment: [String: String]
        let stateRoot: String?
        let portForwardMappings: [PortForwardMapping]
        /// Set when a chosen data folder could not be validated. Starting the
        /// launcher anyway would silently retarget the default workspace.
        let storageUnavailableReason: String?
        /// Set when this Mac cannot satisfy the minimum VM resource contract.
        let resourceUnavailableReason: String?
    }

    /// The environment every launcher invocation receives.
    ///
    /// Reset must compose this exactly as a normal launch does. When the two
    /// diverged, choosing a custom data folder would leave Reset erasing the
    /// default workspace while the VM the user meant to erase stayed untouched.
    ///
    /// Port-forward availability is deliberately *not* validated here: this
    /// context is shared with Reset, and a reset that only wipes the VM disk
    /// should never fail because an unrelated port mapping is unavailable.
    /// `launch()` validates the composed mappings itself, after calling this.
    private func childLaunchContext() -> ChildLaunchContext {
        let audio = AudioLaunchConfiguration.make(
            baseEnvironment: QEMUGPURuntimeEnvironment.sanitizedForLaunch(baseEnvironment),
            preferences: preferenceStore.load(),
            catalog: deviceProvider.catalog()
        )
        let sharing = SharedFolderLaunchConfiguration.make(
            baseEnvironment: audio.environment,
            preference: sharedFolderStore.load(),
            homeDirectory: Self.homeDirectory
        )
        let forwarding = PortForwardLaunchConfiguration.make(
            baseEnvironment: sharing.environment,
            mappings: portForwardingStore.load()
        )
        let fullscreen = FullscreenLaunchConfiguration.make(
            baseEnvironment: forwarding.environment,
            preferences: fullscreenPreferenceStore.load()
        )
        let resources = VMResourceLaunchConfiguration.make(
            baseEnvironment: fullscreen.environment,
            preference: resourceProfilePreferenceStore.load()
        )
        let storage = StorageLocationLaunchConfiguration.make(
            baseEnvironment: resources.environment,
            preference: storageLocationStore.load(),
            metrics: bundledMetrics,
            probe: volumeProbe,
            volumeRootDetector: volumeRootDetector
        )
        return ChildLaunchContext(
            environment: storage.environment,
            stateRoot: storage.stateRoot,
            portForwardMappings: forwarding.mappings,
            storageUnavailableReason: storage.unavailableReason,
            resourceUnavailableReason: resources.unavailableReason
        )
    }

    private func launch(
        arguments: [String],
        allowBootRecovery: Bool = false,
        managementSession requestedManagementSession: UUID? = nil,
        launchRequestAlreadyPublished: Bool = false
    ) throws {
        let context = childLaunchContext()
        // The UI gate above normally resolves this first; failing closed here
        // too keeps a silent fallback impossible for any future caller.
        if let reason = context.storageUnavailableReason {
            throw HelperError.io(reason)
        }
        if let reason = context.resourceUnavailableReason {
            throw HelperError.io(reason)
        }
        try PortForwardAvailability.validate(context.portForwardMappings)
        activeStateRoot = context.stateRoot
        var environment = context.environment
        if allowBootRecovery {
            environment = QEMUGPURuntimeEnvironment.withBootRecoveryConsent(environment)
        }

        activeLaunchAllowedBootRecovery = allowBootRecovery
        let managementSession = requestedManagementSession ?? UUID()
        activeManagementSession = managementSession
        if !launchRequestAlreadyPublished {
            _ = recordManagementEvent(.launchRequested(session: managementSession))
        }
        do {
            try supervisor.start(
                executableURL: launcherURL,
                arguments: arguments,
                environment: environment,
                launchEvent: { [weak self] event in
                    switch event {
                    case .virtualMachineReady(
                        let qmpSocketPath,
                        let processIdentifier
                    ):
                        self?.virtualMachineDidStart(
                            qmpSocketPath: qmpSocketPath,
                            processIdentifier: processIdentifier
                        )
                    }
                }
            ) { [weak self] status in
                self?.childDidExit(status: status)
            }
            activeSharedFolderPath = environment[SharedFolderPolicy.environmentKey]
            activePortMappings = context.portForwardMappings
        } catch {
            activeLaunchAllowedBootRecovery = false
            activeManagementSession = nil
            _ = recordManagementEvent(.childExited(session: managementSession, status: 1))
            throw error
        }
        childRunning = true
        _ = recordManagementEvent(.launcherStarted(session: managementSession))
    }

    private func virtualMachineDidStart(
        qmpSocketPath: String?,
        processIdentifier: Int32?
    ) {
        guard let qmpSocketPath,
              let processIdentifier,
              connectManagementRuntime(
                  qmpSocketPath: qmpSocketPath,
                  processIdentifier: processIdentifier
              ) else {
            failHostSleepControlSetup(
                detail: "the launcher did not provide a valid control identity"
            )
            return
        }
        do {
            try hostSleepCoordinator.connect(to: qmpSocketPath)
        } catch {
            failHostSleepControlSetup(detail: error.localizedDescription)
            return
        }
        virtualMachineReachedStart = true
        virtualMachineReadyDate = Date()
        if let activeManagementSession {
            _ = recordManagementEvent(.virtualMachineReady(session: activeManagementSession))
        }
        NSApp.setActivationPolicy(ApplicationPresentation.runningActivationPolicy)
        refreshManagementDetails()
    }

    private func failHostSleepControlSetup(detail: String) {
        fputs(
            "my-omarchy: host sleep control is unavailable: \(detail)\n",
            stderr
        )
        pendingHostSleepControlFailure = "The virtual machine started, but My Omarchy could not enable safe Mac sleep. Please close and reopen the app. (\(detail))"
        lifecycle.requestQuit()
        supervisor.forward(signal: SIGTERM)
    }

    private static var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    private func sharedFolderMenuState() -> SharedFolderMenuState {
        SharedFolderMenuState.make(
            preference: sharedFolderStore.load(),
            homeDirectory: Self.homeDirectory
        )
    }

    /// Returns an error message when the folder is rejected; otherwise saves
    /// it as the enabled share.
    private func chooseSharedFolder(_ path: String) -> String? {
        do {
            let canonical = try SharedFolderPolicy.validate(path, homeDirectory: Self.homeDirectory)
            sharedFolderStore.save(SharedFolderPreference(path: canonical, isEnabled: true))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func setSharedFolderEnabled(_ enabled: Bool) {
        var preference = sharedFolderStore.load()
        guard preference.path != nil else { return }
        preference.isEnabled = enabled
        sharedFolderStore.save(preference)
    }

    private func savePortForwarding(_ mappings: [PortForwardMapping]) -> String? {
        do {
            try portForwardingStore.save(mappings)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func storageLocationMenuState() -> StorageLocationMenuState {
        StorageLocationMenuState.make(
            preference: storageLocationStore.load(),
            metrics: bundledMetrics,
            homeDirectory: Self.homeDirectory,
            environmentOverride: storageEnvironmentOverride,
            probe: volumeProbe,
            volumeRootDetector: volumeRootDetector
        )
    }

    /// Returns an error message when the folder is rejected, changing nothing.
    private func validateStorageLocation(_ path: String) -> String? {
        do {
            _ = try StorageLocationPolicy.validate(
                path,
                metrics: bundledMetrics,
                probe: volumeProbe,
                volumeRootDetector: volumeRootDetector
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Returns an error message when the folder is rejected; otherwise stores
    /// it. The existing VM is deliberately left where it is: copying tens of
    /// gigabytes across volumes cannot use cloning and would be interruptible.
    private func chooseStorageLocation(_ path: String) -> String? {
        do {
            let resolution = try StorageLocationPolicy.validate(
                path,
                metrics: bundledMetrics,
                probe: volumeProbe,
                volumeRootDetector: volumeRootDetector
            )
            storageLocationStore.save(
                StorageLocationPreference(containerPath: resolution.containerPath)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func useDefaultStorageLocation() {
        storageLocationStore.save(.default)
    }

    /// What the user decided once their chosen drive turned out to be missing.
    ///
    /// Launch and reset must react differently, which is why this reports the
    /// choice instead of a bare yes/no. Switching to the default is a fine way
    /// to *start* a VM, but it must never be a way to *erase* one: the user
    /// confirmed erasing the workspace on their own drive, and the default
    /// workspace is a different VM they were never asked about.
    private enum StorageAvailability {
        case available
        case switchedToDefault
        case cancelled
    }

    /// Refuses to act on the default workspace behind the user's back when
    /// their chosen drive is missing. Silently falling back would create — or
    /// destroy — a second VM they never asked about, which is exactly the
    /// multi-workspace confusion the storage library works to avoid.
    /// The state root forced by the environment, if any.
    ///
    /// `StorageLocationLaunchConfiguration` lets this beat the stored
    /// preference, so anything that reports or gates on "the location" has to
    /// read it too. Otherwise the reset sheet names the folder the user picked
    /// while the launcher erases the one the environment chose.
    private var storageEnvironmentOverride: String? {
        let configured = baseEnvironment[StorageLocationPolicy.environmentKey]
        return (configured?.isEmpty == false) ? configured : nil
    }

    private func resolveStorageLocationAvailability() -> StorageAvailability {
        // An override wins over the preference on the way to the launcher, so
        // the preference's reachability says nothing about this run. The
        // launcher validates the override itself and fails loudly.
        if storageEnvironmentOverride != nil { return .available }
        let preference = storageLocationStore.load()
        guard let container = preference.containerPath else { return .available }
        do {
            _ = try StorageLocationPolicy.validate(
                container,
                metrics: bundledMetrics,
                probe: volumeProbe,
                volumeRootDetector: volumeRootDetector
            )
            return .available
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Omarchy\u{2019}s data folder is unavailable"
            alert.informativeText = """
                \(error.localizedDescription)

                Reconnect the drive and try again, or switch back to the default \
                folder. Switching does not delete the VM stored on that drive.
                """
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Use Default Folder")
            guard alert.runModal() == .alertSecondButtonReturn else { return .cancelled }
            storageLocationStore.save(.default)
            return .switchedToDefault
        }
    }

    /// A physical unplug cannot be prevented, but the VM must not keep writing
    /// into a vanished mount. A graceful eject is already refused by macOS
    /// while QEMU holds the disk open and FD 9 holds its advisory lock.
    private func observeVolumeUnmounts() {
        volumeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let volume = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
                else { return }
                self.handleVolumeUnmount(at: volume)
            }
        }
    }

    private func observeHostPowerEvents() {
        hostPowerObserver = HostPowerNotificationObserver(
            onWillSleep: { [weak self] in
                self?.prepareForHostSleep()
            },
            onDidWake: { [weak self] in
                self?.beginResumeAfterHostWake()
            }
        )
    }

    /// `willSleepNotification` observers may delay host sleep while they run.
    /// Keep this synchronous so QEMU acknowledges `stop` before macOS freezes
    /// the Hypervisor.framework process.
    private func prepareForHostSleep() {
        do {
            try hostSleepCoordinator.prepareForHostSleep(
                vmIsRunning: childRunning,
                isStopping: lifecycle.isStopping
            )
        } catch {
            fputs(
                "my-omarchy: could not pause the VM before host sleep: \(error.localizedDescription)\n",
                stderr
            )
        }
    }

    private func beginResumeAfterHostWake() {
        cancelHostWakeRetry()
        resumeAfterHostWake()
    }

    private func resumeAfterHostWake() {
        do {
            try hostSleepCoordinator.resumeAfterHostWake(
                vmIsRunning: childRunning,
                isStopping: lifecycle.isStopping
            )
            cancelHostWakeRetry()
        } catch {
            fputs(
                "my-omarchy: could not resume the VM after host wake: \(error.localizedDescription)\n",
                stderr
            )
            guard !(error is VMHostSleepControlError),
                  hostSleepCoordinator.pausedForHostSleep,
                  childRunning,
                  !lifecycle.isStopping
            else { return }
            guard hostSleepCoordinator.scheduleWakeRetry({ [weak self] in
                self?.resumeAfterHostWake()
            }) else {
                presentHostWakeRecovery(error: error)
                return
            }
        }
    }

    private func cancelHostWakeRetry() {
        hostSleepCoordinator.cancelWakeRetry()
    }

    private func presentHostWakeRecovery(error: Error) {
        guard childRunning,
              !lifecycle.isStopping,
              hostSleepCoordinator.pausedForHostSleep
        else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Omarchy is still paused"
        alert.informativeText = "My Omarchy could not reconnect after this Mac woke, so the VM remains paused to protect its state. Try again, or quit the app. (\(error.localizedDescription))"
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Quit My Omarchy")

        isPresentingBlockingAlert = true
        let response = alert.runModal()
        isPresentingBlockingAlert = false
        if response == .alertFirstButtonReturn {
            beginResumeAfterHostWake()
        } else {
            NSApp.terminate(nil)
        }
    }

    private func handleVolumeUnmount(at volume: URL) {
        guard childRunning, !lifecycle.isStopping, let root = activeStateRoot else { return }
        let mountPoint = volume.standardizedFileURL.path
        let prefix = mountPoint.hasSuffix("/") ? mountPoint : mountPoint + "/"
        guard root == mountPoint || root.hasPrefix(prefix) else { return }

        fputs(
            "my-omarchy: the volume holding the Omarchy VM was unmounted; stopping\n",
            stderr
        )
        lifecycle.requestQuit()
        supervisor.forward(signal: SIGTERM)

        // This alert is the first UI this accessory app shows all session, so
        // it must activate itself or it can be created without ever becoming
        // key/visible (see the note in finish()).
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "The Omarchy disk was disconnected"
        alert.informativeText = "The drive holding this VM was removed while it was running, so Omarchy is shutting down. Reconnect the drive before launching again. Removing the drive while the VM is running can damage it."
        alert.addButton(withTitle: "OK")

        // The child's own completion callback can arrive and call finish()
        // while this modal call is still blocking below it on the stack — a
        // dispatched main-queue block still gets pumped by a nested modal run
        // loop. Mark the alert as blocking so that reentrant finish() call
        // waits for this dialog instead of tearing it down mid-read.
        isPresentingBlockingAlert = true
        alert.runModal()
        isPresentingBlockingAlert = false
    }

    private func requestOptionalAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }
        // A replacement app can leave a disabled TCC row tied to the old
        // code signature. Reset only our own decision so the prompt below
        // registers the executable that is installed now.
        _ = AccessibilityPermissionRepair.resetStaleEntry()
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    private func childDidExit(status: Int32) {
        guard childRunning else { return }
        childRunning = false
        activeRuntimeController = nil
        activeQEMUProcessIdentifier = nil
        virtualMachineReadyDate = nil
        activeSharedFolderPath = nil
        activePortMappings = []
        var restartSession: UUID?
        var completedManagementStop = false
        if let managementSession = activeManagementSession {
            let wasRestarting = managementViewModel.state.lifecycle == .restarting
            let wasStopping = managementViewModel.state.lifecycle == .stopping
            activeManagementSession = nil
            let accepted = recordManagementEvent(
                .childExited(session: managementSession, status: status)
            )
            completedManagementStop = accepted && wasStopping
            if accepted,
               wasRestarting,
               managementViewModel.state.lifecycle == .launching {
                restartSession = managementViewModel.state.sessionID
            }
        }
        let launchAllowedBootRecovery = activeLaunchAllowedBootRecovery
        activeLaunchAllowedBootRecovery = false
        cancelHostWakeRetry()
        hostSleepCoordinator.disconnect()
        let recentStandardError = supervisor.recentStandardError
        let diagnosticsLogPath = supervisor.recentDiagnosticsLogPath

        let wasStopping = lifecycle.isStopping
        let presentation = VMExitPresentationDecision.make(
            status: status,
            reachedVirtualMachineStart: virtualMachineReachedStart,
            wasStopping: wasStopping
        )
        let hostSleepControlFailure = pendingHostSleepControlFailure
        pendingHostSleepControlFailure = nil
        lifecycle.childExited()
        if applicationTerminationPending {
            NSApp.reply(toApplicationShouldTerminate: true)
        } else if completedManagementStop {
            virtualMachineReachedStart = false
        } else if let restartSession {
            virtualMachineReachedStart = false
            do {
                try launch(
                    arguments: launchArguments(),
                    managementSession: restartSession,
                    launchRequestAlreadyPublished: true
                )
            } catch {
                fputs("my-omarchy: restart failed: \(error.localizedDescription)\n", stderr)
                _ = recordManagementEvent(
                    .launchFailed(message: error.localizedDescription)
                )
            }
        } else if let hostSleepControlFailure {
            managementPresenter.showWarning(
                title: "Safe Mac sleep is unavailable",
                detail: launchFailureMessage(
                    hostSleepControlFailure, diagnosticsLogPath: diagnosticsLogPath
                )
            )
        } else {
            if presentation.showsStartupFailure,
               let portFailure = PortForwardStartupFailure.message(
                   standardError: recentStandardError,
                   mappings: portForwardingStore.load()
               ) {
                managementPresenter.showWarning(
                    title: "My Omarchy couldn’t start",
                    detail: launchFailureMessage(
                        portFailure, diagnosticsLogPath: diagnosticsLogPath
                    )
                )
                return
            }
            if presentation.requiresWorkspaceReset {
                managementPresenter.showWarning(
                    title: "Reset Omarchy to continue",
                    detail: ManagementRecoveryPresentation.incompatibleWorkspaceDetail
                )
                return
            }
            switch BootRecoveryChildExitGate.decide(
                presentation: presentation,
                launchWasAuthorized: launchAllowedBootRecovery
            ) {
            case .reportFailure:
                managementPresenter.showWarning(
                    title: "My Omarchy couldn’t prepare the saved VM",
                    detail: launchFailureMessage(
                        "The saved VM was not reset or upgraded. You can safely try again.",
                        diagnosticsLogPath: diagnosticsLogPath
                    )
                )
                return
            case .requestConfirmation:
                switch BootRecoveryLaunchGate.decide(
                    preflight: .requiresConfirmation,
                    confirm: { [weak self] in
                        self?.managementPresenter.confirm(
                            title: ManagementRecoveryPresentation.bootRecoveryConfirmationTitle,
                            detail: ManagementRecoveryPresentation.bootRecoveryConfirmationDetail,
                            actionTitle: ManagementLocalization.string("recovery.boot.action")
                        ) ?? false
                    }
                ) {
                case .cancel:
                    break
                case .launch:
                    // Retry the same configured workspace directly. Re-running
                    // availability resolution here could offer to switch from
                    // a just-disconnected external VM to the default one, then
                    // accidentally spend consent on a different saved disk.
                    do {
                        try launch(
                            arguments: launchArguments(),
                            allowBootRecovery: true
                        )
                    } catch {
                        failLaunch(error)
                    }
                }
                return
            case .unrelated:
                break
            }
            if presentation.showsStartupFailure {
                managementPresenter.showWarning(
                    title: "My Omarchy couldn’t start",
                    detail: launchFailureMessage(
                        "The virtual machine stopped during startup. Review Diagnostics and try again.",
                        diagnosticsLogPath: diagnosticsLogPath
                    )
                )
            }
            refreshManagementDetails()
        }
    }

    private func failLaunch(_ error: Error) {
        fputs("my-omarchy: \(error.localizedDescription)\n", stderr)
        _ = recordManagementEvent(.launchFailed(message: error.localizedDescription))
        managementPresenter.showWarning(
            title: "My Omarchy couldn’t start",
            detail: launchFailureMessage(
                error.localizedDescription, diagnosticsLogPath: supervisor.recentDiagnosticsLogPath
            )
        )
        refreshManagementDetails()
    }

    private func launchFailureMessage(
        _ message: String,
        diagnosticsLogPath: String?
    ) -> String {
        guard let diagnosticsLogPath, !diagnosticsLogPath.isEmpty else {
            return message
        }
        let filename = URL(fileURLWithPath: diagnosticsLogPath).lastPathComponent
        return "\(message)\n\nDiagnostic log: \(filename)"
    }

    private func finish(status: Int32) {
        // The completion callback that reaches `finish()` can arrive while a
        // dialog this controller opened is still on screen — a dispatched
        // main-queue block is still pumped by a nested `runModal()` loop.
        // `NSApp.stop()` is not scoped to only the outer run loop: called
        // while a modal session is active, it can end THAT session too,
        // closing the alert before the user has read it. So the whole
        // shutdown sequence below waits for the alert to be dismissed on its
        // own, rather than only guarding the final forced exit.
        guard !isPresentingBlockingAlert else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.finish(status: status)
            }
            return
        }

        exitStatus = status

        // `stop` + a posted wake-up event only reliably pumps the run loop
        // for an app the window server considers active. This accessory app
        // never shows its own window once the VM is running — QEMU owns the
        // visible window as a separate process — so a path that reaches here
        // without our window ever having been key (an eject while running,
        // not a signal-driven quit) can leave the posted event unserviced and
        // the process running with nothing on screen. Activating first covers
        // that gap; the delayed hard exit is a backstop in case it does not.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.stop(nil)
        if let wakeUp = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) {
            NSApp.postEvent(wakeUp, atStart: false)
        }

        // Backstop: forces the process to exit if the run loop has not
        // already returned on its own. If `run()` has already returned by
        // the time this fires, the process has exited and this never runs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            fputs("my-omarchy: forcing exit; the run loop did not stop on its own\n", stderr)
            Darwin.exit(status)
        }
    }
}
