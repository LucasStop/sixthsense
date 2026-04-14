import Testing
import SixthSenseCore
import SharedServices
import SharedServicesMocks
@testable import GhostDropModule

@MainActor
private func makeModule() -> (GhostDropModule, MockCameraPipeline, MockPeerNetwork, EventBus) {
    let camera = MockCameraPipeline()
    let network = MockPeerNetwork()
    let bus = EventBus()

    let module = GhostDropModule(
        cameraManager: camera,
        bonjourService: network,
        eventBus: bus
    )
    return (module, camera, network, bus)
}

@Test func ghostDropDescriptorIsCorrect() {
    #expect(GhostDropModule.descriptor.id == "ghost-drop")
    #expect(GhostDropModule.descriptor.name == "GhostDrop")
    #expect(GhostDropModule.descriptor.category == .transfer)
}

@Test @MainActor func ghostDropRequiresCameraAndLocalNetwork() {
    let (module, _, _, _) = makeModule()
    let perms = module.requiredPermissions

    #expect(perms.count == 2)
    #expect(perms.contains(where: { $0.type == .camera }))
    #expect(perms.contains(where: { $0.type == .localNetwork }))
}

@Test @MainActor func ghostDropStartsDisabled() {
    let (module, _, _, _) = makeModule()
    #expect(module.state == .disabled)
}

@Test @MainActor func ghostDropStartBeginsBrowsing() async throws {
    let (module, _, network, _) = makeModule()

    try await module.start()

    #expect(module.state == .running)
    #expect(network.startBrowsingCalls == 1)
}

@Test @MainActor func ghostDropStopStopsBrowsing() async throws {
    let (module, _, network, _) = makeModule()

    try await module.start()
    await module.stop()

    #expect(module.state == .disabled)
    #expect(network.stopBrowsingCalls == 1)
}

@Test @MainActor func ghostDropStopCleansUpEvenWhenHandTrackingNotStarted() async throws {
    let (module, camera, _, _) = makeModule()

    try await module.start()
    // Do NOT wait 2 seconds — so fallback hand tracking doesn't kick in
    await module.stop()

    // No subscribe should have happened (fallback delay is 2s)
    #expect(camera.subscribeCalls.isEmpty)
}
