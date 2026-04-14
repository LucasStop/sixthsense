import Testing
import SixthSenseCore
import SharedServices
@testable import NotchBarModule

// Note: NotchBarModule uses the concrete OverlayWindowManager because it relies
// on the generic createOverlay<Content: View> API. Lifecycle tests would require
// a real NSWindow, so we test only static properties and settings here.

@Test func notchBarDescriptorIsCorrect() {
    #expect(NotchBarModule.descriptor.id == "notch-bar")
    #expect(NotchBarModule.descriptor.name == "NotchBar")
    #expect(NotchBarModule.descriptor.category == .interface)
}

@Test @MainActor func notchBarMicrophoneIsOptional() {
    let module = NotchBarModule(overlay: OverlayWindowManager())
    let perms = module.requiredPermissions

    #expect(perms.count == 1)
    #expect(perms.first?.type == .microphone)
    #expect(perms.first?.isRequired == false)
}

@Test @MainActor func notchBarStartsDisabled() {
    let module = NotchBarModule(overlay: OverlayWindowManager())
    #expect(module.state == .disabled)
}

@Test @MainActor func notchBarDefaultAutoHideIsFalse() {
    let module = NotchBarModule(overlay: OverlayWindowManager())
    #expect(module.autoHide == false)
}

@Test @MainActor func notchBarAutoHideIsMutable() {
    let module = NotchBarModule(overlay: OverlayWindowManager())
    module.autoHide = true
    #expect(module.autoHide == true)
}
