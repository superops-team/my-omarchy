import Testing
@testable import MyOmarchy

@Suite("Virtual machine window activation")
struct VirtualMachineWindowActivatorTests {
    @Test("activates only the expected live QEMU process")
    func activatesExpectedProcess() {
        var activated: [Int32] = []
        let activator = VirtualMachineWindowActivator(
            processExists: { $0 == 4242 },
            activate: { activated.append($0); return true }
        )

        #expect(activator.activate(processIdentifier: 4242))
        #expect(activated == [4242])
        #expect(!activator.activate(processIdentifier: 4343))
        #expect(activated == [4242])
    }

    @Test("rejects invalid process identifiers")
    func rejectsInvalidIdentifiers() {
        let activator = VirtualMachineWindowActivator(
            processExists: { _ in true },
            activate: { _ in true }
        )

        #expect(!activator.activate(processIdentifier: 0))
        #expect(!activator.activate(processIdentifier: -1))
    }
}
