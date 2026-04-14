import Testing
import Foundation
import CoreGraphics
import SixthSenseCore
import SharedServices
import SharedServicesMocks
@testable import HandCommandModule

// MARK: - Helpers

@MainActor
private func makeModule() -> (HandCommandModule, MockCameraPipeline, MockOverlayPresenter, MockWindowAccessibility, MockMouseController, EventBus) {
    let camera = MockCameraPipeline()
    let overlay = MockOverlayPresenter()
    let accessibility = MockWindowAccessibility()
    let cursor = MockMouseController()
    let bus = EventBus()

    let module = HandCommandModule(
        cameraManager: camera,
        overlayManager: overlay,
        accessibilityService: accessibility,
        cursorController: cursor,
        eventBus: bus
    )
    return (module, camera, overlay, accessibility, cursor, bus)
}

// MARK: - Descriptor & Permissions

@Test func handCommandDescriptorIsCorrect() {
    #expect(HandCommandModule.descriptor.id == "hand-command")
    #expect(HandCommandModule.descriptor.name == "HandCommand")
    #expect(HandCommandModule.descriptor.category == .input)
    #expect(HandCommandModule.descriptor.systemImage == "hand.raised")
}

@Test @MainActor func handCommandRequiresCameraAndAccessibility() {
    let (module, _, _, _, _, _) = makeModule()
    let perms = module.requiredPermissions

    #expect(perms.count == 2)
    #expect(perms.contains(where: { $0.type == .camera && $0.isRequired }))
    #expect(perms.contains(where: { $0.type == .accessibility && $0.isRequired }))
}

// MARK: - Initial State

@Test @MainActor func handCommandStartsDisabled() {
    let (module, _, _, _, _, _) = makeModule()
    #expect(module.state == .disabled)
    #expect(module.latestSnapshot == nil)
}

@Test @MainActor func handCommandDefaultSensitivityIsOne() {
    let (module, _, _, _, _, _) = makeModule()
    #expect(module.sensitivity == 1.0)
}

@Test @MainActor func handCommandSensitivityIsMutable() {
    let (module, _, _, _, _, _) = makeModule()
    module.sensitivity = 2.5
    #expect(module.sensitivity == 2.5)
}

// MARK: - Lifecycle

@Test @MainActor func handCommandStartSubscribesToCamera() async throws {
    let (module, camera, _, _, _, _) = makeModule()

    try await module.start()

    #expect(module.state == .running)
    #expect(camera.subscribeCalls.contains("hand-command"))
}

@Test @MainActor func handCommandStopUnsubscribesAndRemovesOverlay() async throws {
    let (module, camera, overlay, _, _, _) = makeModule()

    try await module.start()
    await module.stop()

    #expect(module.state == .disabled)
    #expect(camera.unsubscribeCalls.contains("hand-command"))
    #expect(overlay.removeCalls.contains("hand-command"))
}

@Test @MainActor func handCommandSnapshotStartsNil() {
    let (module, _, _, _, _, _) = makeModule()
    #expect(module.latestSnapshot == nil)
}
