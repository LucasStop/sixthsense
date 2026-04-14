import Testing
import SixthSenseCore
import SharedServices
import SharedServicesMocks
@testable import GazeShiftModule

@MainActor
private func makeModule() -> (GazeShiftModule, MockCameraPipeline, MockOverlayPresenter, MockWindowAccessibility) {
    let camera = MockCameraPipeline()
    let overlay = MockOverlayPresenter()
    let accessibility = MockWindowAccessibility()

    let module = GazeShiftModule(
        cameraManager: camera,
        overlayManager: overlay,
        accessibilityService: accessibility
    )
    return (module, camera, overlay, accessibility)
}

@Test func gazeShiftDescriptorIsCorrect() {
    #expect(GazeShiftModule.descriptor.id == "gaze-shift")
    #expect(GazeShiftModule.descriptor.name == "GazeShift")
    #expect(GazeShiftModule.descriptor.category == .input)
    #expect(GazeShiftModule.descriptor.systemImage == "eye")
}

@Test @MainActor func gazeShiftRequiresCameraAndAccessibility() {
    let (module, _, _, _) = makeModule()
    let perms = module.requiredPermissions

    #expect(perms.count == 2)
    #expect(perms.contains(where: { $0.type == .camera && $0.isRequired }))
    #expect(perms.contains(where: { $0.type == .accessibility && $0.isRequired }))
}

@Test @MainActor func gazeShiftStartsDisabled() {
    let (module, _, _, _) = makeModule()
    #expect(module.state == .disabled)
}

@Test @MainActor func gazeShiftDefaultDimIntensity() {
    let (module, _, _, _) = makeModule()
    #expect(module.dimIntensity == 0.4)
}

@Test @MainActor func gazeShiftDimIntensityIsMutable() {
    let (module, _, _, _) = makeModule()
    module.dimIntensity = 0.75
    #expect(module.dimIntensity == 0.75)
}

@Test @MainActor func gazeShiftStartSubscribesToCamera() async throws {
    let (module, camera, _, _) = makeModule()

    try await module.start()

    #expect(module.state == .running)
    #expect(camera.subscribeCalls.contains("gaze-shift"))
}

@Test @MainActor func gazeShiftStopUnsubscribesAndRemovesOverlay() async throws {
    let (module, camera, overlay, _) = makeModule()

    try await module.start()
    await module.stop()

    #expect(module.state == .disabled)
    #expect(camera.unsubscribeCalls.contains("gaze-shift"))
    #expect(overlay.removeCalls.contains("gaze-shift"))
}
