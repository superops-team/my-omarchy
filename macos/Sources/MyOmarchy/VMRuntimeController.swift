final class VMRuntimeController {
    private let execute: (String) throws -> Void

    init(execute: @escaping (String) throws -> Void) {
        self.execute = execute
    }

    convenience init(socketPath: String) {
        self.init { command in
            let connection = try QMPConnection(
                socketPath: socketPath,
                identifierPrefix: "my-omarchy-runtime-control"
            )
            defer { connection.close() }
            _ = try connection.execute(command)
        }
    }

    func requestGracefulShutdown() throws {
        try execute("system_powerdown")
    }
}
