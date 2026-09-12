import Testing
@testable import MyOmarchy

@Suite("VM runtime control")
struct VMRuntimeControllerTests {
    @Test("graceful shutdown sends system_powerdown exactly once")
    func gracefulShutdown() throws {
        var commands: [String] = []
        let controller = VMRuntimeController { command in
            commands.append(command)
        }

        try controller.requestGracefulShutdown()

        #expect(commands == ["system_powerdown"])
    }

    @Test("a failed shutdown command is reported without retrying")
    func failedShutdownIsNotRetried() {
        var attempts = 0
        let controller = VMRuntimeController { _ in
            attempts += 1
            throw TestError.expected
        }

        #expect(throws: TestError.self) {
            try controller.requestGracefulShutdown()
        }
        #expect(attempts == 1)
    }

    private enum TestError: Error {
        case expected
    }
}
