import Darwin
import Foundation
import Testing
@testable import MyOmarchy

@Suite("QEMU GPU app launch request")
struct QEMUGPULaunchRequestTests {
    @Test("accepts only the launcher storage flags and an optional absolute guest directory")
    func parsesAllowedArguments() {
        let guest = "/private/tmp/omarchy guest"
        #expect(QEMUGPULaunchRequest(arguments: []) == QEMUGPULaunchRequest(
            storageOption: nil,
            guestDirectoryPath: nil
        ))
        #expect(QEMUGPULaunchRequest(arguments: ["--ephemeral"]) == QEMUGPULaunchRequest(
            storageOption: .ephemeral,
            guestDirectoryPath: nil
        ))
        #expect(QEMUGPULaunchRequest(arguments: ["--reset-storage", guest]) == QEMUGPULaunchRequest(
            storageOption: .resetStorage,
            guestDirectoryPath: guest
        ))
        #expect(QEMUGPULaunchRequest(arguments: ["--reset-storage-only", guest]) == QEMUGPULaunchRequest(
            storageOption: .resetStorageOnly,
            guestDirectoryPath: guest
        ))
        #expect(QEMUGPULaunchRequest(arguments: [guest]) == QEMUGPULaunchRequest(
            storageOption: nil,
            guestDirectoryPath: guest
        ))
    }

    @Test("rejects unknown flags, relative paths, reordered flags, and extra arguments")
    func rejectsUnsafeArguments() {
        for arguments in [
            ["--unknown"],
            ["relative/guest"],
            ["/guest", "--ephemeral"],
            ["--ephemeral", "--reset-storage"],
            ["--ephemeral", "/guest", "/other"],
            ["/guest\nother"],
        ] {
            #expect(QEMUGPULaunchRequest(arguments: arguments) == nil)
        }
    }

    @Test("canonicalizes a safe guest directory before passing it to the script")
    func validatesGuestDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-qemu-request-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let request = try #require(QEMUGPULaunchRequest(arguments: ["--ephemeral", root.path]))
        #expect(try request.validatedScriptArguments() == ["--ephemeral", root.resolvingSymlinksInPath().path])
    }

    @Test("rejects a final guest-directory symlink")
    func rejectsGuestSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-qemu-request-\(UUID().uuidString)", isDirectory: true)
        let guest = root.appendingPathComponent("guest", isDirectory: true)
        let link = root.appendingPathComponent("guest-link", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: guest, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: guest)

        let request = try #require(QEMUGPULaunchRequest(arguments: [link.path]))
        #expect(throws: HelperError.self) {
            try request.validatedScriptArguments()
        }
    }

}

@Suite("QEMU runtime environment")
struct QEMUGPURuntimeEnvironmentTests {
    @Test("ordinary launches strip build-only controls")
    func sanitizesLaunch() {
        let environment = QEMUGPURuntimeEnvironment.sanitizedForLaunch([
            "KEEP_ME": "yes",
            QEMUGPURuntimeEnvironment.inspectOnlyKey: "1",
            QEMUGPURuntimeEnvironment.dryRunKey: "1",
            QEMUGPURuntimeEnvironment.bootRecoveryConsentKey: "1",
        ])

        #expect(environment == ["KEEP_ME": "yes"])
    }

    @Test("boot recovery consent is an explicit one-launch environment addition")
    func addsBootRecoveryConsent() {
        let ordinary = QEMUGPURuntimeEnvironment.sanitizedForLaunch(["KEEP_ME": "yes"])
        let approved = QEMUGPURuntimeEnvironment.withBootRecoveryConsent(ordinary)

        #expect(ordinary == ["KEEP_ME": "yes"])
        #expect(approved == [
            "KEEP_ME": "yes",
            QEMUGPURuntimeEnvironment.bootRecoveryConsentKey: "1",
        ])
        #expect(QEMUGPURuntimeEnvironment.sanitizedForLaunch(approved) == ordinary)
    }

    @Test("storage reset ignores inherited integration settings")
    func sanitizesReset() {
        let controlledKeys = [
            AudioLaunchConfiguration.inheritedSDLDeviceNameKey,
            AudioLaunchConfiguration.outputDeviceNameKey,
            AudioLaunchConfiguration.inputDeviceNameKey,
            SharedFolderPolicy.environmentKey,
            PortForwardPolicy.environmentKey,
            QEMUGPURuntimeEnvironment.inspectOnlyKey,
            QEMUGPURuntimeEnvironment.dryRunKey,
            QEMUGPURuntimeEnvironment.bootRecoveryConsentKey,
        ]
        var inherited = ["KEEP_ME": "yes"]
        for key in controlledKeys {
            inherited[key] = "untrusted inherited value"
        }

        #expect(QEMUGPURuntimeEnvironment.sanitizedForReset(inherited)
            == ["KEEP_ME": "yes"])
    }
}

@Suite("QEMU standard-error drain")
struct QEMUStandardErrorDrainTests {
    @Test("launch diagnostic logs use the user log directory")
    func launchDiagnosticLogPath() throws {
        let directory = try #require(LaunchDiagnosticsLog.defaultDirectory())

        #expect(directory.path.hasSuffix("/Library/Logs/My Omarchy"))
    }

    @Test("launch diagnostic logs create private files with deterministic names")
    func launchDiagnosticLogWritesPrivateFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-launch-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = try #require(LaunchDiagnosticsLog.create(
            directory: directory,
            now: Date(timeIntervalSince1970: 1_789_017_130),
            processIdentifier: 42,
            uuid: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000000")!
        ))
        log.appendLine("[my-omarchy] hello")
        log.append(Data("[qemu-gpu] Ready. QMP: /tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock\n".utf8))
        let arkSecret = "secret-" + "ark-value"
        let anthropicSecret = "secret-" + "anthropic-value"
        let openAISecret = "sk-" + "testsecretvalue1234567890"
        let arkKey = "ARK" + "_API_KEY"
        let openAIKey = "OPENAI" + "_API_KEY"
        let anthropicKey = "ANTHROPIC" + "_API_KEY"
        log.appendLine("[my-omarchy] Environment: \(arkKey)=\(arkSecret) \(openAIKey)=\(openAISecret)")
        log.append(Data("stderr \(anthropicKey)='\(anthropicSecret)' raw \(openAISecret)\n".utf8))
        log.close()

        #expect(log.url.lastPathComponent == "launch-1789017130-42-a1b2c3d4.log")
        let directoryMode = try mode(of: directory)
        let fileMode = try mode(of: log.url)
        #expect(directoryMode & 0o777 == 0o700)
        #expect(fileMode & 0o777 == 0o600)
        let contents = try String(contentsOf: log.url, encoding: .utf8)
        #expect(contents.contains("[my-omarchy] hello"))
        #expect(contents.contains("[qemu-gpu] Ready. QMP: /tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock"))
        #expect(contents.contains("ARK_API_KEY=<redacted>"))
        #expect(contents.contains("OPENAI_API_KEY=<redacted>"))
        #expect(contents.contains("ANTHROPIC_API_KEY=<redacted>"))
        #expect(contents.contains("sk-<redacted>"))
        #expect(!contents.contains(arkSecret))
        #expect(!contents.contains(anthropicSecret))
        #expect(!contents.contains(openAISecret))
    }

    @Test("launch diagnostic logs redact secrets split across stderr chunks")
    func launchDiagnosticLogRedactsSecretsAcrossChunks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-launch-log-split-secret-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = try #require(LaunchDiagnosticsLog.create(directory: directory))
        let secret = "sk-" + "splitsecretvalue1234567890"

        log.append(Data("stderr OPENAI_API_".utf8))
        log.append(Data("KEY=\(secret.prefix(11))".utf8))
        log.append(Data("\(secret.dropFirst(11)) done\n".utf8))
        log.close()

        let contents = try String(contentsOf: log.url, encoding: .utf8)
        #expect(contents.contains("OPENAI_API_KEY=<redacted>"))
        #expect(!contents.contains(secret))
        #expect(!contents.contains("splitsecretvalue"))
    }

    @Test("launch diagnostic logs reject a symbolic-link directory without changing its target")
    func launchDiagnosticLogRejectsSymbolicLinkDirectory() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-launch-log-link-\(UUID().uuidString)", isDirectory: true)
        let target = parent.appendingPathComponent("target", isDirectory: true)
        let link = parent.appendingPathComponent("logs", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(
            at: target,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(LaunchDiagnosticsLog.create(directory: link) == nil)
        #expect(try mode(of: target) & 0o777 == 0o755)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    @Test("launch diagnostic logs never overwrite a colliding file")
    func launchDiagnosticLogRejectsFileCollision() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-launch-log-collision-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_789_017_130)
        let uuid = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000000")!
        let existing = directory.appendingPathComponent(
            LaunchDiagnosticsLog.fileName(now: now, processIdentifier: 42, uuid: uuid)
        )
        let sentinel = Data("must survive".utf8)
        try sentinel.write(to: existing)

        #expect(LaunchDiagnosticsLog.create(
            directory: directory,
            now: now,
            processIdentifier: 42,
            uuid: uuid
        ) == nil)
        #expect(try Data(contentsOf: existing) == sentinel)
    }

    @Test("launch diagnostic logs stop at ten MiB with one truncation marker")
    func launchDiagnosticLogHasHardSizeLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-launch-log-limit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = try #require(LaunchDiagnosticsLog.create(directory: directory))

        log.append(Data(repeating: 0x61, count: LaunchDiagnosticsLog.maximumFileBytes + 1))
        let sizeAtLimit = try #require(
            (FileManager.default.attributesOfItem(atPath: log.url.path)[.size] as? NSNumber)?.intValue
        )
        log.append(Data(repeating: 0x62, count: 4096))
        log.close()

        let contents = try Data(contentsOf: log.url)
        let marker = Data(LaunchDiagnosticsLog.truncationMarker.utf8)
        #expect(sizeAtLimit == LaunchDiagnosticsLog.maximumFileBytes)
        #expect(contents.count == LaunchDiagnosticsLog.maximumFileBytes)
        #expect(contents.suffix(marker.count) == marker)
        #expect(contents.dropLast(marker.count).range(of: marker) == nil)
    }

    @Test("launch diagnostic logs reserve quota and remove only the oldest managed files")
    func launchDiagnosticLogRetainsBoundedHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-launch-log-retention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var historical: [URL] = []
        for index in 0..<11 {
            let url = directory.appendingPathComponent(
                "launch-\(100 + index)-42-a1b2c3d4.log"
            )
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(5 * 1024 * 1024))
            try handle.close()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            historical.append(url)
        }
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        let target = directory.appendingPathComponent("target.txt")
        try Data("target".utf8).write(to: target)
        let unsafeLink = directory.appendingPathComponent("launch-1-42-deadbeef.log")
        try FileManager.default.createSymbolicLink(at: unsafeLink, withDestinationURL: target)

        let log = try #require(LaunchDiagnosticsLog.create(
            directory: directory,
            now: Date(timeIntervalSince1970: 1_789_017_130),
            processIdentifier: 42,
            uuid: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000000")!
        ))
        log.close()

        #expect(!FileManager.default.fileExists(atPath: historical[0].path))
        #expect(!FileManager.default.fileExists(atPath: historical[1].path))
        #expect(!FileManager.default.fileExists(atPath: historical[2].path))
        #expect(FileManager.default.fileExists(atPath: historical[3].path))
        #expect(try Data(contentsOf: unrelated) == Data("keep".utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: unsafeLink.path) == target.path)

        let managed = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("launch-") && $0.pathExtension == "log" }
        let regularManaged = managed.filter { url in
            var information = stat()
            return Darwin.lstat(url.path, &information) == 0
                && (information.st_mode & S_IFMT) == S_IFREG
        }
        let totalBytes = try regularManaged.reduce(Int64(0)) { total, url in
            let size = try #require(
                (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            )
            return total + size
        }
        #expect(regularManaged.count == 9)
        #expect(totalBytes <= Int64(50 * 1024 * 1024))
    }

    @Test("launch diagnostic logs enforce final quota after the current log grows")
    func launchDiagnosticLogEnforcesQuotaOnClose() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-launch-log-close-quota-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<8 {
            let url = directory.appendingPathComponent("launch-\(100 + index)-42-a1b2c3d4.log")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(5 * 1024 * 1024))
            try handle.close()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let oldest = directory.appendingPathComponent("launch-100-42-a1b2c3d4.log")
        let log = try #require(LaunchDiagnosticsLog.create(directory: directory))
        let grownHistorical = directory.appendingPathComponent("launch-107-42-a1b2c3d4.log")
        let growthHandle = try FileHandle(forWritingTo: grownHistorical)
        try growthHandle.truncate(atOffset: UInt64(5 * 1024 * 1024 + 1))
        try growthHandle.close()

        log.append(Data(repeating: 0x61, count: LaunchDiagnosticsLog.maximumFileBytes))
        log.close()

        #expect(!FileManager.default.fileExists(atPath: oldest.path))
        let managed = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.lastPathComponent.hasPrefix("launch-") && $0.pathExtension == "log" }
        let totalBytes = try managed.reduce(Int64(0)) { total, url in
            total + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        #expect(managed.count <= LaunchDiagnosticsLog.maximumRetainedFiles)
        #expect(totalBytes <= LaunchDiagnosticsLog.maximumRetainedBytes)
    }

    @Test("launch diagnostic retention stays bound to the opened directory")
    func launchDiagnosticLogDoesNotCleanReplacementDirectory() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-launch-log-replacement-\(UUID().uuidString)", isDirectory: true)
        let directory = parent.appendingPathComponent("logs", isDirectory: true)
        let movedDirectory = parent.appendingPathComponent("opened-logs", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let log = try #require(LaunchDiagnosticsLog.create(directory: directory))
        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        for index in 0..<11 {
            let replacement = directory.appendingPathComponent("launch-\(index + 1)-42-deadbeef.log")
            try Data("replacement".utf8).write(to: replacement)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: replacement.path)
        }

        log.close()

        let replacementLogs = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(replacementLogs.count == 11)
        let originalLogs = try FileManager.default.contentsOfDirectory(atPath: movedDirectory.path)
        #expect(originalLogs.count == 1)
    }

    @Test("supervisor persists launcher diagnostics while preserving the recent error buffer")
    func supervisorWritesLaunchDiagnostics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-supervisor-log-\(UUID().uuidString)", isDirectory: true)
        let script = directory.appendingPathComponent("launcher.sh")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(
            """
            #!/bin/sh
            echo '[qemu-gpu] Starting test launcher' >&2
            echo '[qemu-gpu] Ready. QMP: /tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock PID: 4242' >&2
            echo 'guest diagnostic line' >&2
            exit 7
            """.utf8
        ).write(to: script)
        #expect(Darwin.chmod(script.path, 0o755) == 0)

        let supervisor = QEMUGPUProcessSupervisor(diagnosticsLogDirectory: directory)
        let finished = DispatchSemaphore(value: 0)
        let result = LockedLaunchResult()

        try supervisor.start(
            executableURL: script,
            arguments: ["--flag"],
            environment: ["OMARCHY_QEMU_GPU_RESOURCE_PROFILE": "balanced"],
            launchEvent: { event in
                if case .virtualMachineReady(let path, let processIdentifier) = event {
                    result.setReadySocket(path)
                    result.setReadyProcessIdentifier(processIdentifier)
                }
            }
        ) { status in
            result.setExitStatus(status)
            finished.signal()
        }

        #expect(waitFor(finished, timeout: 10))
        #expect(result.exitStatus == 7)
        #expect(result.readySocket == "/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock")
        #expect(result.readyProcessIdentifier == 4242)
        #expect(supervisor.recentStandardError.contains("guest diagnostic line"))
        let logPath = try #require(supervisor.recentDiagnosticsLogPath)
        let contents = try String(contentsOfFile: logPath, encoding: .utf8)
        #expect(contents.contains("[my-omarchy] Executable: \(script.path)"))
        #expect(contents.contains("[my-omarchy] Arguments: --flag"))
        #expect(contents.contains("OMARCHY_QEMU_GPU_RESOURCE_PROFILE=balanced"))
        #expect(contents.contains("[qemu-gpu] Starting test launcher"))
        #expect(contents.contains("guest diagnostic line"))
        #expect(contents.contains("[my-omarchy] Virtual machine ready event detected"))
        #expect(contents.contains("[my-omarchy] Launcher exited with status 7"))
    }

    @Test("drains a bounded tail without waiting for EOF and restores descriptor flags")
    func boundedNonblockingDrain() throws {
        let pipe = Pipe()
        var writerClosed = false
        defer {
            pipe.fileHandleForReading.closeFile()
            if !writerClosed {
                pipe.fileHandleForWriting.closeFile()
            }
        }

        let payload = Data("trailing QEMU diagnostic".utf8)
        try pipe.fileHandleForWriting.write(contentsOf: payload)
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let originalFlags = Darwin.fcntl(descriptor, F_GETFL)
        #expect(originalFlags >= 0)

        let first = QEMUGPUProcessSupervisor.drainAvailableStandardError(
            from: pipe.fileHandleForReading,
            maximumBytes: 8
        )
        #expect(first.data == Data(payload.prefix(8)))
        #expect(!first.reachedEnd)
        #expect(Darwin.fcntl(descriptor, F_GETFL) == originalFlags)

        let second = QEMUGPUProcessSupervisor.drainAvailableStandardError(
            from: pipe.fileHandleForReading,
            maximumBytes: 1_024
        )
        #expect(second.data == Data(payload.dropFirst(8)))
        #expect(!second.reachedEnd)
        #expect(Darwin.fcntl(descriptor, F_GETFL) == originalFlags)

        pipe.fileHandleForWriting.closeFile()
        writerClosed = true
        let end = QEMUGPUProcessSupervisor.drainAvailableStandardError(
            from: pipe.fileHandleForReading,
            maximumBytes: 1_024
        )
        #expect(end.data.isEmpty)
        #expect(end.reachedEnd)
        #expect(Darwin.fcntl(descriptor, F_GETFL) == originalFlags)
    }

    @Test("waits for a complete Ready line and carries its private QMP socket and QEMU pid")
    func parsesReadyControlSocket() {
        let partial = "startup output\n[qemu-gpu] Ready. QMP: /tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock PID:"
        #expect(QEMUGPUProcessSupervisor.virtualMachineReadyEvent(in: partial) == nil)

        let complete = partial + " 4242\nmore output\n"
        #expect(QEMUGPUProcessSupervisor.virtualMachineReadyEvent(in: complete) ==
            .virtualMachineReady(
                qmpSocketPath: "/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock",
                processIdentifier: 4242
            ))
    }

    @Test("ignores a Ready marker embedded inside another diagnostic line")
    func readyMarkerMustStartItsLine() {
        let output = """
            shared folder: /tmp/[qemu-gpu] Ready. QMP: not-a-socket
            [qemu-gpu] Ready. QMP: /tmp/my-omarchy-qemu-gpu.Z9y8X7/qmp.sock PID: 4242
            """ + "\n"
        #expect(QEMUGPUProcessSupervisor.virtualMachineReadyEvent(in: output) ==
            .virtualMachineReady(
                qmpSocketPath: "/tmp/my-omarchy-qemu-gpu.Z9y8X7/qmp.sock",
                processIdentifier: 4242
            ))

        let lookalike = "[qemu-gpu] Ready.bad QMP: /tmp/my-omarchy-qemu-gpu.Z9y8X7/qmp.sock\n"
        #expect(QEMUGPUProcessSupervisor.virtualMachineReadyEvent(in: lookalike) == nil)
    }

    @Test("does not trust a malformed socket advertised by the launcher")
    func rejectsMalformedReadyControlSocket() {
        for path in [
            "/tmp/my-omarchy-qemu-gpu.short/qmp.sock",
            "/tmp/my-omarchy-qemu-gpu.A1b2C3/../qmp.sock",
            "/private/tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock",
            "/tmp/other.A1b2C3/qmp.sock",
        ] {
            let output = "[qemu-gpu] Ready. QMP: \(path) PID: 4242\n"
            #expect(QEMUGPUProcessSupervisor.virtualMachineReadyEvent(in: output) ==
                .virtualMachineReady(qmpSocketPath: nil, processIdentifier: nil))
        }
    }

    @Test("does not trust an invalid QEMU pid advertised by the launcher")
    func rejectsMalformedReadyProcessIdentifier() {
        for pid in ["0", "-1", "abc", "999999999999999999999"] {
            let output = "[qemu-gpu] Ready. QMP: /tmp/my-omarchy-qemu-gpu.A1b2C3/qmp.sock PID: \(pid)\n"
            #expect(QEMUGPUProcessSupervisor.virtualMachineReadyEvent(in: output) ==
                .virtualMachineReady(qmpSocketPath: nil, processIdentifier: nil))
        }
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }

    private func waitFor(_ semaphore: DispatchSemaphore, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if semaphore.wait(timeout: .now()) == .success {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return semaphore.wait(timeout: .now()) == .success
    }

    private final class LockedLaunchResult: @unchecked Sendable {
        private let lock = NSLock()
        private var storedExitStatus: Int32?
        private var storedReadySocket: String?
        private var storedReadyProcessIdentifier: Int32?

        var exitStatus: Int32? {
            lock.lock()
            defer { lock.unlock() }
            return storedExitStatus
        }

        var readySocket: String? {
            lock.lock()
            defer { lock.unlock() }
            return storedReadySocket
        }

        var readyProcessIdentifier: Int32? {
            lock.lock()
            defer { lock.unlock() }
            return storedReadyProcessIdentifier
        }

        func setExitStatus(_ status: Int32) {
            lock.lock()
            storedExitStatus = status
            lock.unlock()
        }

        func setReadySocket(_ socket: String?) {
            lock.lock()
            storedReadySocket = socket
            lock.unlock()
        }

        func setReadyProcessIdentifier(_ processIdentifier: Int32?) {
            lock.lock()
            storedReadyProcessIdentifier = processIdentifier
            lock.unlock()
        }
    }
}

@Suite("QEMU storage-space estimate")
struct QEMUGPUStorageSpaceEstimateTests {
    @Test("shows the app data folder while keeping the VM layout versioned")
    func displaysStorageRoot() throws {
        let configuredRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("my-omarchy-configured/../data", isDirectory: true)
            .path
        let configuredEnvironment = ["OMARCHY_QEMU_GPU_STATE_ROOT": configuredRoot]
        let standardizedConfiguredRoot = URL(
            fileURLWithPath: configuredRoot,
            isDirectory: true
        ).standardizedFileURL
        #expect(QEMUGPUStorageSpaceEstimate.dataDirectoryDisplayPath(
            environment: configuredEnvironment
        ) == "~/data")
        #expect(QEMUGPUStorageSpaceEstimate.dataDirectoryURL(
            environment: configuredEnvironment
        ) == standardizedConfiguredRoot)
        #expect(QEMUGPUStorageSpaceEstimate.storageRootURL(
            environment: configuredEnvironment
        ) == standardizedConfiguredRoot)

        let defaultDirectory = try #require(QEMUGPUStorageSpaceEstimate.dataDirectoryDisplayPath(
            environment: [:]
        ))
        #expect(defaultDirectory == "~/Library/Application Support/My Omarchy")

        let defaultDirectoryURL = try #require(QEMUGPUStorageSpaceEstimate.dataDirectoryURL(
            environment: [:]
        ))
        let defaultStorageRoot = try #require(QEMUGPUStorageSpaceEstimate.storageRootURL(
            environment: [:]
        ))
        #expect(defaultStorageRoot == defaultDirectoryURL
            .appendingPathComponent("VM/v1", isDirectory: true)
            .standardizedFileURL)

        for invalidRoot in ["relative/path", "/private/tmp/..", "/tmp", "/opt", "/bad\npath"] {
            let invalidEnvironment = ["OMARCHY_QEMU_GPU_STATE_ROOT": invalidRoot]
            #expect(QEMUGPUStorageSpaceEstimate.dataDirectoryURL(
                environment: invalidEnvironment
            ) == nil)
            #expect(QEMUGPUStorageSpaceEstimate.storageRootURL(
                environment: invalidEnvironment
            ) == nil)
        }
    }

    @Test("a chosen data folder replaces the default without the versioned suffix")
    func honorsStoredPreference() throws {
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".my-omarchy-tests", isDirectory: true)
            .appendingPathComponent("omarchy-launcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let preference = StorageLocationPreference(containerPath: container.path)

        // A chosen workspace is the state root itself, exactly as the launcher
        // script treats OMARCHY_QEMU_GPU_STATE_ROOT — the picked folder is
        // used directly, with no folder nested inside it.
        let expected = URL(fileURLWithPath: container.path, isDirectory: true)
            .standardizedFileURL
        #expect(QEMUGPUStorageSpaceEstimate.dataDirectoryURL(
            environment: [:],
            preference: preference
        ) == expected)
        #expect(QEMUGPUStorageSpaceEstimate.storageRootURL(
            environment: [:],
            preference: preference
        ) == expected)
    }

    @Test("the development override still wins over a stored preference")
    func overrideBeatsPreference() throws {
        let configuredURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".my-omarchy-tests/override-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: configuredURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: configuredURL) }
        let configured = configuredURL.path
        let expected = URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        #expect(QEMUGPUStorageSpaceEstimate.storageRootURL(
            environment: ["OMARCHY_QEMU_GPU_STATE_ROOT": configured],
            preference: StorageLocationPreference(containerPath: "/Volumes/Ignored")
        ) == expected)
    }

    @Test("formats allocated bytes as a readable decimal gigabyte estimate")
    func formatsGigabytes() {
        #expect(QEMUGPUStorageSpaceEstimate.format(bytes: 0) == nil)
        #expect(QEMUGPUStorageSpaceEstimate.format(bytes: 50_000_000) == "less than 0.1 GB")
        #expect(QEMUGPUStorageSpaceEstimate.format(bytes: 3_250_000_000) == "3.2 GB")
    }

    @Test("selects the same single or development workspace used by the launcher")
    func selectsStorageKey() {
        let identity = String(repeating: "a", count: 64)
        #expect(QEMUGPUStorageSpaceEstimate.storageKey(
            environment: [:],
            bundleIdentity: identity
        ) == "current")
        #expect(QEMUGPUStorageSpaceEstimate.storageKey(
            environment: ["OMARCHY_QEMU_GPU_DEVELOPMENT_MULTI_DISK": "0"],
            bundleIdentity: identity
        ) == "current")
        #expect(QEMUGPUStorageSpaceEstimate.storageKey(
            environment: ["OMARCHY_QEMU_GPU_DEVELOPMENT_MULTI_DISK": "1"],
            bundleIdentity: identity
        ) == identity)
        #expect(QEMUGPUStorageSpaceEstimate.storageKey(
            environment: ["OMARCHY_QEMU_GPU_DEVELOPMENT_MULTI_DISK": "1"],
            bundleIdentity: nil
        ) == nil)
        #expect(QEMUGPUStorageSpaceEstimate.storageKey(
            environment: ["OMARCHY_QEMU_GPU_DEVELOPMENT_MULTI_DISK": "invalid"],
            bundleIdentity: identity
        ) == nil)
    }

    @Test("counts every safely recognized disk removed by a single-disk reset")
    func countsResettableLegacyDisks() throws {
        let fileManager = FileManager.default
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".my-omarchy-tests", isDirectory: true)
            .appendingPathComponent(
            "my-omarchy-space-estimate-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: root) }
        let disks = root.appendingPathComponent("state/disks", isDirectory: true)
        try fileManager.createDirectory(at: disks, withIntermediateDirectories: true)

        let identityA = String(repeating: "a", count: 64)
        let identityB = String(repeating: "b", count: 64)
        let identityC = String(repeating: "c", count: 64)
        let current = try makeWorkspace(
            in: disks,
            name: "current",
            identity: identityA,
            payloadBytes: 8_192
        )
        let legacy = try makeWorkspace(
            in: disks,
            name: identityB,
            identity: identityB,
            payloadBytes: 12_288
        )
        _ = try makeWorkspace(
            in: disks,
            name: identityC,
            identity: identityC,
            payloadBytes: 16_384,
            addUnknownFile: true
        )

        let allocated = try [current, legacy].reduce(Int64(0)) { total, disk in
            let values = try disk.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
            ])
            return total + Int64(try #require(
                values.totalFileAllocatedSize ?? values.fileAllocatedSize
            ))
        }
        let environment = ["OMARCHY_QEMU_GPU_STATE_ROOT": root.appendingPathComponent("state").path]
        #expect(QEMUGPUStorageSpaceEstimate.reclaimableBytes(
            environment: environment,
            bundleIdentity: identityA,
            fileManager: fileManager
        ) == allocated)

        #expect(QEMUGPUStorageSpaceEstimate.reclaimableBytes(
            environment: environment.merging(
                ["OMARCHY_QEMU_GPU_DEVELOPMENT_MULTI_DISK": "1"],
                uniquingKeysWith: { _, new in new }
            ),
            bundleIdentity: identityB,
            fileManager: fileManager
        ) == allocatedSize(of: legacy))
    }

    @Test("ignores semantically valid metadata with noncanonical whitespace or key order")
    func ignoresNoncanonicalSerializedMetadata() throws {
        let fileManager = FileManager.default
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".my-omarchy-tests", isDirectory: true)
            .appendingPathComponent(
            "my-omarchy-space-estimate-noncanonical-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: root) }
        let disks = root.appendingPathComponent("state/disks", isDirectory: true)
        try fileManager.createDirectory(at: disks, withIntermediateDirectories: true)

        let identity = String(repeating: "a", count: 64)
        let sourceSHA = String(repeating: "d", count: 64)
        _ = try makeWorkspace(
            in: disks,
            name: "current",
            identity: identity,
            payloadBytes: 8_192,
            metadataContents: """
            { "kind": "my-omarchy-persistent-disk", "bundleIdentity": "\(identity)", "sourceRootfs": { "sha256": "\(sourceSHA)", "bytes": 1 }, "schemaVersion": 2 }
            """
        )

        let environment = ["OMARCHY_QEMU_GPU_STATE_ROOT": root.appendingPathComponent("state").path]
        #expect(QEMUGPUStorageSpaceEstimate.reclaimableBytes(
            environment: environment,
            bundleIdentity: identity,
            fileManager: fileManager
        ) == nil)
    }

    @Test("ignores fractional schema and source byte values")
    func ignoresFractionalMetadataNumbers() throws {
        let fileManager = FileManager.default
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".my-omarchy-tests", isDirectory: true)
            .appendingPathComponent(
            "my-omarchy-space-estimate-fractional-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: root) }
        let disks = root.appendingPathComponent("state/disks", isDirectory: true)
        try fileManager.createDirectory(at: disks, withIntermediateDirectories: true)

        let identity = String(repeating: "b", count: 64)
        let sourceSHA = String(repeating: "d", count: 64)
        _ = try makeWorkspace(
            in: disks,
            name: identity,
            identity: identity,
            payloadBytes: 8_192,
            metadataContents: "{\"bundleIdentity\":\"\(identity)\",\"kind\":\"my-omarchy-persistent-disk\",\"schemaVersion\":2.5,\"sourceRootfs\":{\"bytes\":1.5,\"sha256\":\"\(sourceSHA)\"}}\n"
        )

        let environment = ["OMARCHY_QEMU_GPU_STATE_ROOT": root.appendingPathComponent("state").path]
        #expect(QEMUGPUStorageSpaceEstimate.reclaimableBytes(
            environment: environment,
            bundleIdentity: identity,
            fileManager: fileManager
        ) == nil)
    }

    private func makeWorkspace(
        in disks: URL,
        name: String,
        identity: String,
        payloadBytes: Int,
        addUnknownFile: Bool = false,
        metadataContents: String? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = disks.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        #expect(Darwin.chmod(directory.path, 0o700) == 0)

        let metadata = directory.appendingPathComponent("metadata.json")
        let sourceSHA = String(repeating: "d", count: 64)
        try Data(
            (metadataContents ?? "{\"bundleIdentity\":\"\(identity)\",\"kind\":\"my-omarchy-persistent-disk\",\"schemaVersion\":2,\"sourceRootfs\":{\"bytes\":1,\"sha256\":\"\(sourceSHA)\"}}\n").utf8
        ).write(to: metadata)
        #expect(Darwin.chmod(metadata.path, 0o600) == 0)

        let disk = directory.appendingPathComponent("rootfs.ext4")
        try Data(repeating: 0x5a, count: payloadBytes).write(to: disk)
        #expect(Darwin.chmod(disk.path, 0o600) == 0)
        if addUnknownFile {
            let unknown = directory.appendingPathComponent("unknown.txt")
            try Data("preserve".utf8).write(to: unknown)
            #expect(Darwin.chmod(unknown.path, 0o600) == 0)
        }
        return disk
    }

    private func allocatedSize(of disk: URL) -> Int64? {
        guard let values = try? disk.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
        ]),
              let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize
        else { return nil }
        return Int64(bytes)
    }
}

@Suite("Bundled QEMU GPU launcher path")
struct QEMUGPULauncherPathTests {
    @Test("resolves only the executable inside the app resources")
    func resolvesExpectedLayout() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        #expect(try QEMUGPULauncherPath.resolve(bundleURL: fixture.app) == fixture.launcher)
    }

    @Test("rejects a launcher symlink")
    func rejectsLauncherSymlink() throws {
        let fixture = try makeFixture(createLauncher: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let other = fixture.root.appendingPathComponent("other-launcher")
        try Data("#!/bin/bash\nexit 0\n".utf8).write(to: other)
        #expect(Darwin.chmod(other.path, 0o755) == 0)
        try FileManager.default.createSymbolicLink(at: fixture.launcher, withDestinationURL: other)

        #expect(throws: HelperError.self) {
            try QEMUGPULauncherPath.resolve(bundleURL: fixture.app)
        }
    }

    @Test("rejects an app with the wrong bundle name")
    func rejectsWrongBundleName() throws {
        let fixture = try makeFixture(appName: "Other.app")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        #expect(throws: HelperError.self) {
            try QEMUGPULauncherPath.resolve(bundleURL: fixture.app)
        }
    }

    private struct PathFixture {
        let root: URL
        let app: URL
        let launcher: URL
    }

    private func makeFixture(
        appName: String = QEMUGPULauncherPath.appName,
        createLauncher: Bool = true
    ) throws -> PathFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-omarchy-qemu-path-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent(appName, isDirectory: true)
        let scripts = app
            .appendingPathComponent("Contents/Resources/scripts", isDirectory: true)
        let launcher = scripts.appendingPathComponent(QEMUGPULauncherPath.launcherName)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        if createLauncher {
            try Data("#!/bin/bash\nexit 0\n".utf8).write(to: launcher)
            #expect(Darwin.chmod(launcher.path, 0o755) == 0)
        }
        return PathFixture(
            root: root,
            app: app.resolvingSymlinksInPath(),
            launcher: launcher.resolvingSymlinksInPath()
        )
    }
}

@Suite("Microphone launch policy")
struct MicrophoneLaunchDecisionTests {
    @Test("denial keeps playback launchable and gives recovery instructions")
    func deniedStillLaunches() {
        let decision = MicrophoneLaunchDecision.make(for: .denied)
        #expect(decision.allowsLaunch)
        #expect(decision.warning?.contains("Audio playback will continue") == true)
        #expect(decision.warning?.contains("System Settings > Privacy & Security > Microphone") == true)
    }

    @Test("restriction keeps playback launchable with an administrator action")
    func restrictedStillLaunches() {
        let decision = MicrophoneLaunchDecision.make(for: .restricted)
        #expect(decision.allowsLaunch)
        #expect(decision.warning?.contains("Mac administrator") == true)
    }

    @Test("authorization launches without a warning")
    func authorizedHasNoWarning() {
        let decision = MicrophoneLaunchDecision.make(for: .authorized)
        #expect(decision.allowsLaunch)
        #expect(decision.warning == nil)
    }

    @Test("an unrequested microphone remains optional")
    func notDeterminedStillLaunches() {
        let decision = MicrophoneLaunchDecision.make(for: .notDetermined)
        #expect(decision.allowsLaunch)
        #expect(decision.warning?.contains("was not requested") == true)
    }
}

@Suite("Accessibility launch policy")
struct AccessibilityLaunchDecisionTests {
    @Test("an unavailable grant never blocks Omarchy startup")
    func unavailableStillLaunches() {
        let decision = AccessibilityLaunchDecision.make(for: .unavailable)
        #expect(decision.allowsLaunch)
        #expect(decision.warning?.contains("start without Command-to-Super mapping") == true)
        #expect(decision.warning?.contains("later launch") == true)
    }

    @Test("authorization launches without a warning")
    func authorizedHasNoWarning() {
        let decision = AccessibilityLaunchDecision.make(for: .authorized)
        #expect(decision.allowsLaunch)
        #expect(decision.warning == nil)
    }
}
