import AppKit
import Darwin

struct VirtualMachineWindowActivator {
    private let processExists: (Int32) -> Bool
    private let activateApplication: (Int32) -> Bool

    init(
        processExists: @escaping (Int32) -> Bool = { Darwin.kill($0, 0) == 0 },
        activate: @escaping (Int32) -> Bool = { processIdentifier in
            guard let application = NSRunningApplication(
                processIdentifier: processIdentifier
            ) else { return false }
            application.unhide()
            return application.activate(options: [.activateAllWindows])
        }
    ) {
        self.processExists = processExists
        self.activateApplication = activate
    }

    func activate(processIdentifier: Int32) -> Bool {
        guard processIdentifier > 1, processExists(processIdentifier) else {
            return false
        }
        return activateApplication(processIdentifier)
    }
}
