import Testing
@testable import SharedServices

@Test func moduleSettingsStorePersistence() {
    let store = ModuleSettingsStore(defaults: .init(suiteName: "test-\(UUID().uuidString)")!)

    // Default state is disabled
    #expect(store.isModuleEnabled("hand-command") == false)

    // Enable module
    store.setModuleEnabled("hand-command", enabled: true)
    #expect(store.isModuleEnabled("hand-command") == true)

    // Custom settings
    store.setValue(0.8, for: "sensitivity", moduleId: "hand-command")
    let sensitivity: Double? = store.value(for: "sensitivity", moduleId: "hand-command")
    #expect(sensitivity == 0.8)

    // Default value
    let threshold: Double = store.value(for: "threshold", moduleId: "hand-command", default: 0.5)
    #expect(threshold == 0.5)
}
