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

// MARK: - Dual-hand snapshots

@Test @MainActor func handCommandStartsWithEmptyLeftAndRightSnapshots() {
    let (module, _, _, _, _, _) = makeModule()
    #expect(module.latestLeftSnapshot == nil)
    #expect(module.latestRightSnapshot == nil)
    #expect(module.lastActions.isEmpty)
}

@Test @MainActor func handCommandStopResetsAllSnapshots() async throws {
    let (module, _, _, _, _, _) = makeModule()

    try await module.start()
    await module.stop()

    #expect(module.latestSnapshot == nil)
    #expect(module.latestLeftSnapshot == nil)
    #expect(module.latestRightSnapshot == nil)
    #expect(module.lastActions.isEmpty)
}

// MARK: - Screen point conversion

@Test func handCommandScreenPointFlipsYAxis() {
    let size = CGSize(width: 1000, height: 500)
    // With deadzone 0.0 the mapping is trivial: (0,0) in Vision → top-left
    // in screen coords (which is (0, 500) because Vision's origin is at the
    // bottom of the image).
    let origin = HandCommandModule.screenPoint(
        from: CGPoint(x: 0, y: 0),
        in: size,
        deadzone: 0.0
    )
    #expect(origin.x == 0)
    #expect(origin.y == 500)
}

@Test func handCommandScreenPointDeadzoneSaturatesEdges() {
    let size = CGSize(width: 1000, height: 500)
    // With deadzone 0.2, anything with normalized x ≤ 0.2 should saturate
    // at screen x = 0. A normalized x = 0.1 is within the deadzone.
    let left = HandCommandModule.screenPoint(
        from: CGPoint(x: 0.1, y: 0.5),
        in: size,
        deadzone: 0.2
    )
    #expect(left.x == 0)

    // Symmetrically, x ≥ 0.8 should saturate at screen x = 1000.
    let right = HandCommandModule.screenPoint(
        from: CGPoint(x: 0.9, y: 0.5),
        in: size,
        deadzone: 0.2
    )
    #expect(right.x == 1000)
}

@Test func handCommandScreenPointRemapsCenter() {
    let size = CGSize(width: 1000, height: 500)
    // Center of the deadzone-adjusted usable region should be center of screen.
    let center = HandCommandModule.screenPoint(
        from: CGPoint(x: 0.5, y: 0.5),
        in: size,
        deadzone: 0.2
    )
    #expect(abs(center.x - 500) < 0.001)
    #expect(abs(center.y - 250) < 0.001)
}

// MARK: - Keyboard injection via overload init

@MainActor
private func makeModuleWithKeyboard() -> (HandCommandModule, MockCameraPipeline, MockOverlayPresenter, MockWindowAccessibility, MockMouseController, MockKeyboardInput, EventBus) {
    let camera = MockCameraPipeline()
    let overlay = MockOverlayPresenter()
    let accessibility = MockWindowAccessibility()
    let cursor = MockMouseController()
    let keyboard = MockKeyboardInput()
    let bus = EventBus()

    let module = HandCommandModule(
        cameraManager: camera,
        overlayManager: overlay,
        accessibilityService: accessibility,
        cursorController: cursor,
        keyboardInput: keyboard,
        eventBus: bus
    )
    return (module, camera, overlay, accessibility, cursor, keyboard, bus)
}

@Test @MainActor func handCommandAcceptsSeparateKeyboardInput() async throws {
    let (module, camera, _, _, _, _, _) = makeModuleWithKeyboard()

    try await module.start()

    #expect(module.state == .running)
    #expect(camera.subscribeCalls.contains("hand-command"))
}

// MARK: - Debug lines

@Test @MainActor func handCommandDebugLinesStartEmpty() {
    let (module, _, _, _, _, _) = makeModule()
    #expect(module.debugLines.isEmpty)
}

@Test @MainActor func handCommandStopClearsDebugLines() async throws {
    let (module, _, _, _, _, _) = makeModule()

    try await module.start()
    await module.stop()

    #expect(module.debugLines.isEmpty)
}

@Test @MainActor func handCommandInputDeadzoneDefault() {
    let (module, _, _, _, _, _) = makeModule()
    #expect(module.inputDeadzone > 0)
    #expect(module.inputDeadzone < 0.5)
}

// MARK: - Sensitivity scaling

@Test @MainActor func effectiveDeadzoneRespectsDefaultSensitivity() {
    let (module, _, _, _, _, _) = makeModule()
    #expect(module.sensitivity == 1.0)
    // Baseline deadzone × 1.0 sensitivity should equal baseline.
    #expect(abs(module.effectiveDeadzone - Double(module.inputDeadzone)) < 0.001)
}

@Test @MainActor func effectiveDeadzoneGrowsWithSensitivity() {
    let (module, _, _, _, _, _) = makeModule()
    module.sensitivity = 2.0
    // 0.18 × 2.0 = 0.36, within the [0.08, 0.40] clamp.
    #expect(module.effectiveDeadzone > Double(module.inputDeadzone))
    #expect(module.effectiveDeadzone <= 0.40)
}

@Test @MainActor func effectiveDeadzoneShrinksWithLowSensitivity() {
    let (module, _, _, _, _, _) = makeModule()
    module.sensitivity = 0.5
    // 0.18 × 0.5 = 0.09
    #expect(module.effectiveDeadzone < Double(module.inputDeadzone))
    #expect(module.effectiveDeadzone >= 0.08)
}

@Test @MainActor func effectiveDeadzoneClampsAtExtremeSensitivity() {
    let (module, _, _, _, _, _) = makeModule()

    module.sensitivity = 0.01
    #expect(module.effectiveDeadzone == 0.08)

    module.sensitivity = 10.0
    #expect(module.effectiveDeadzone == 0.40)
}
