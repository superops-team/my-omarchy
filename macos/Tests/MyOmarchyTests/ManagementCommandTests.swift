import Testing
@testable import MyOmarchy

@Suite("Management commands")
struct ManagementCommandTests {
    @Test("lifecycle commands are accepted only in safe states")
    func lifecycleCommandGate() {
        #expect(ManagementCommandPolicy.allows(.launch, while: .idle))
        #expect(!ManagementCommandPolicy.allows(.launch, while: .launching))
        #expect(!ManagementCommandPolicy.allows(.resetStorage, while: .running))
        #expect(ManagementCommandPolicy.allows(.stop, while: .running))
        #expect(ManagementCommandPolicy.allows(.restart, while: .running))
        #expect(!ManagementCommandPolicy.allows(.restart, while: .stopping))
        #expect(ManagementCommandPolicy.allows(.launch, while: .failed))
    }
}
