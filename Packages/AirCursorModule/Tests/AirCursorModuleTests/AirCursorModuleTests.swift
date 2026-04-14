import Testing
import SixthSenseCore
import SharedServices
import SharedServicesMocks
@testable import AirCursorModule

@MainActor
private func makeModule() -> (AirCursorModule, MockPeerNetwork, MockMouseController) {
    let network = MockPeerNetwork()
    let cursor = MockMouseController()

    let module = AirCursorModule(
        bonjourService: network,
        cursorController: cursor
    )
    return (module, network, cursor)
}

@Test func airCursorDescriptorIsCorrect() {
    #expect(AirCursorModule.descriptor.id == "air-cursor")
    #expect(AirCursorModule.descriptor.name == "AirCursor")
    #expect(AirCursorModule.descriptor.category == .input)
}

@Test @MainActor func airCursorRequiresLocalNetwork() {
    let (module, _, _) = makeModule()
    let perms = module.requiredPermissions

    #expect(perms.count == 1)
    #expect(perms.first?.type == .localNetwork)
    #expect(perms.first?.isRequired == true)
}

@Test @MainActor func airCursorStartsDisabled() {
    let (module, _, _) = makeModule()
    #expect(module.state == .disabled)
}

@Test @MainActor func airCursorDefaultGyroSensitivity() {
    let (module, _, _) = makeModule()
    #expect(module.gyroSensitivity == 1.0)
}

@Test @MainActor func airCursorGyroSensitivityIsMutable() {
    let (module, _, _) = makeModule()
    module.gyroSensitivity = 3.5
    #expect(module.gyroSensitivity == 3.5)
}

@Test @MainActor func airCursorStartStartsBrowsing() async throws {
    let (module, network, _) = makeModule()

    try await module.start()

    #expect(module.state == .running)
    #expect(network.startBrowsingCalls == 1)
    #expect(network.isBrowsing == true)
}

@Test @MainActor func airCursorStopStopsBrowsing() async throws {
    let (module, network, _) = makeModule()

    try await module.start()
    await module.stop()

    #expect(module.state == .disabled)
    #expect(network.stopBrowsingCalls == 1)
    #expect(network.isBrowsing == false)
}

@Test @MainActor func airCursorStartAndStopAreIdempotentSafe() async throws {
    let (module, network, _) = makeModule()

    try await module.start()
    await module.stop()
    try await module.start()
    await module.stop()

    #expect(network.startBrowsingCalls == 2)
    #expect(network.stopBrowsingCalls == 2)
}
