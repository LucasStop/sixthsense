import Testing
import SwiftUI
@testable import SixthSenseCore

// MARK: - Fake Module for testing type erasure

@MainActor
@Observable
private final class FakeModule: SixthSenseModule {
    static let descriptor = ModuleDescriptor(
        id: "fake",
        name: "Fake",
        tagline: "test module",
        systemImage: "star",
        category: .input
    )

    var state: ModuleState = .disabled
    var startCalls = 0
    var stopCalls = 0

    var requiredPermissions: [PermissionRequirement] {
        [PermissionRequirement(type: .camera, reason: "fake")]
    }

    func start() async throws {
        state = .starting
        startCalls += 1
        state = .running
    }

    func stop() async {
        state = .stopping
        stopCalls += 1
        state = .disabled
    }

    var settingsView: some View {
        EmptyView()
    }
}

@Test @MainActor func anyModuleExposesDescriptor() {
    let fake = FakeModule()
    let wrapped = AnyModule(fake)

    #expect(wrapped.id == "fake")
    #expect(wrapped.descriptor.name == "Fake")
    #expect(wrapped.descriptor.category == .input)
}

@Test @MainActor func anyModuleInitialStateMatchesUnderlying() {
    let fake = FakeModule()
    let wrapped = AnyModule(fake)

    #expect(wrapped.state == .disabled)
}

@Test @MainActor func anyModuleStartForwardsAndSyncsState() async throws {
    let fake = FakeModule()
    let wrapped = AnyModule(fake)

    try await wrapped.start()

    #expect(fake.startCalls == 1)
    #expect(wrapped.state == .running)
}

@Test @MainActor func anyModuleStopForwardsAndSyncsState() async throws {
    let fake = FakeModule()
    let wrapped = AnyModule(fake)

    try await wrapped.start()
    await wrapped.stop()

    #expect(fake.stopCalls == 1)
    #expect(wrapped.state == .disabled)
}

@Test @MainActor func anyModuleExposesRequiredPermissions() {
    let fake = FakeModule()
    let wrapped = AnyModule(fake)

    #expect(wrapped.requiredPermissions.count == 1)
    #expect(wrapped.requiredPermissions.first?.type == .camera)
}

@Test @MainActor func anyModulePollingSyncsExternalStateChanges() async {
    let fake = FakeModule()
    let wrapped = AnyModule(fake)

    // Mutate state outside of start/stop — the 100ms polling task should catch it
    fake.state = .error

    // Wait slightly longer than the polling interval (100ms)
    try? await Task.sleep(for: .milliseconds(180))

    #expect(wrapped.state == .error)
}
