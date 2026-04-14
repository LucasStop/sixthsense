import Testing
@testable import SixthSenseCore

@Test func moduleDescriptorIdentifiable() {
    let descriptor = ModuleDescriptor(
        id: "test-module",
        name: "Test",
        tagline: "A test module",
        systemImage: "star",
        category: .input
    )
    #expect(descriptor.id == "test-module")
    #expect(descriptor.name == "Test")
    #expect(descriptor.category == .input)
}

@Test func moduleStateProperties() {
    #expect(ModuleState.running.isActive == true)
    #expect(ModuleState.starting.isActive == true)
    #expect(ModuleState.disabled.isActive == false)
    #expect(ModuleState.error.isActive == false)
}

@Test func eventBusPublishesEvents() async {
    let bus = EventBus()
    var received = false

    let cancellable = bus.publisher.sink { event in
        if case .handTrackingLost = event {
            received = true
        }
    }

    bus.emit(.handTrackingLost)

    // Give the publisher a moment to deliver
    try? await Task.sleep(for: .milliseconds(50))
    #expect(received == true)
    _ = cancellable
}
