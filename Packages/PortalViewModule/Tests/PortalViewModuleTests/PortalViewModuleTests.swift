import Testing
import CoreGraphics
import SixthSenseCore
import SharedServices
import SharedServicesMocks
@testable import PortalViewModule

@MainActor
private func makeModule() -> (PortalViewModule, MockPeerNetwork) {
    let network = MockPeerNetwork()
    let module = PortalViewModule(bonjourService: network)
    return (module, network)
}

@Test func portalViewDescriptorIsCorrect() {
    #expect(PortalViewModule.descriptor.id == "portal-view")
    #expect(PortalViewModule.descriptor.name == "PortalView")
    #expect(PortalViewModule.descriptor.category == .display)
}

@Test @MainActor func portalViewRequiresScreenRecordingAndLocalNetwork() {
    let (module, _) = makeModule()
    let perms = module.requiredPermissions

    #expect(perms.count == 2)
    #expect(perms.contains(where: { $0.type == .screenRecording }))
    #expect(perms.contains(where: { $0.type == .localNetwork }))
}

@Test @MainActor func portalViewStartsDisabled() {
    let (module, _) = makeModule()
    #expect(module.state == .disabled)
}

@Test @MainActor func portalViewDefaultResolutionIs1080p() {
    let (module, _) = makeModule()
    #expect(module.resolution == CGSize(width: 1920, height: 1080))
}

@Test @MainActor func portalViewDefaultFpsIs30() {
    let (module, _) = makeModule()
    #expect(module.targetFPS == 30)
}

@Test @MainActor func portalViewStartBeginsAdvertising() async throws {
    let (module, network) = makeModule()

    try await module.start()

    #expect(module.state == .running)
    #expect(network.startAdvertisingCalls.count == 1)
    #expect(network.isAdvertising == true)
    #expect(network.startAdvertisingCalls.first?.name.hasPrefix("PortalView-") == true)
}

@Test @MainActor func portalViewStopStopsAdvertising() async throws {
    let (module, network) = makeModule()

    try await module.start()
    await module.stop()

    #expect(module.state == .disabled)
    #expect(network.stopAdvertisingCalls == 1)
    #expect(network.isAdvertising == false)
}

@Test @MainActor func portalViewStartPropagatesNetworkError() async {
    let network = MockPeerNetwork()
    network.shouldFailAdvertising = true
    let module = PortalViewModule(bonjourService: network)

    do {
        try await module.start()
        Issue.record("Expected start() to throw when advertising fails")
    } catch {
        // Expected: MockPeerNetworkError.forcedFailure bubbles up
    }
}
