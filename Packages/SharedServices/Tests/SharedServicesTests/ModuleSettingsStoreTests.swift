import Testing
import Foundation
@testable import SharedServices

private func makeStore() -> ModuleSettingsStore {
    ModuleSettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
}

@Test func enabledDefaultsToFalse() {
    let store = makeStore()
    #expect(store.isModuleEnabled("any-module") == false)
}

@Test func settingsAreIsolatedByModuleId() {
    let store = makeStore()

    store.setModuleEnabled("hand-command", enabled: true)
    store.setModuleEnabled("gaze-shift", enabled: false)

    #expect(store.isModuleEnabled("hand-command") == true)
    #expect(store.isModuleEnabled("gaze-shift") == false)
    #expect(store.isModuleEnabled("air-cursor") == false)
}

@Test func valuesAreIsolatedBetweenModules() {
    let store = makeStore()

    store.setValue(2.5, for: "sensitivity", moduleId: "hand-command")
    store.setValue(0.3, for: "sensitivity", moduleId: "gaze-shift")

    let hc: Double? = store.value(for: "sensitivity", moduleId: "hand-command")
    let gs: Double? = store.value(for: "sensitivity", moduleId: "gaze-shift")

    #expect(hc == 2.5)
    #expect(gs == 0.3)
}

@Test func supportsDifferentValueTypes() {
    let store = makeStore()
    let moduleId = "test-module"

    store.setValue(42, for: "int", moduleId: moduleId)
    store.setValue(3.14, for: "double", moduleId: moduleId)
    store.setValue("hello", for: "string", moduleId: moduleId)
    store.setValue(true, for: "bool", moduleId: moduleId)
    store.setValue(["a", "b", "c"], for: "array", moduleId: moduleId)

    let intValue: Int? = store.value(for: "int", moduleId: moduleId)
    let doubleValue: Double? = store.value(for: "double", moduleId: moduleId)
    let stringValue: String? = store.value(for: "string", moduleId: moduleId)
    let boolValue: Bool? = store.value(for: "bool", moduleId: moduleId)
    let arrayValue: [String]? = store.value(for: "array", moduleId: moduleId)

    #expect(intValue == 42)
    #expect(doubleValue == 3.14)
    #expect(stringValue == "hello")
    #expect(boolValue == true)
    #expect(arrayValue == ["a", "b", "c"])
}

@Test func overwritingValueReplacesIt() {
    let store = makeStore()

    store.setValue(1.0, for: "sensitivity", moduleId: "hand-command")
    store.setValue(2.0, for: "sensitivity", moduleId: "hand-command")

    let value: Double? = store.value(for: "sensitivity", moduleId: "hand-command")
    #expect(value == 2.0)
}

@Test func defaultValueWhenKeyAbsent() {
    let store = makeStore()

    let value: Double = store.value(for: "missing", moduleId: "x", default: 9.9)
    #expect(value == 9.9)
}

@Test func defaultValueReturnsSavedValueWhenPresent() {
    let store = makeStore()

    store.setValue(5.0, for: "existing", moduleId: "x")
    let value: Double = store.value(for: "existing", moduleId: "x", default: 99.0)
    #expect(value == 5.0)
}

@Test func persistenceSurvivesStoreReinstantiation() {
    let suiteName = "test-persist-\(UUID().uuidString)"
    let first = ModuleSettingsStore(defaults: UserDefaults(suiteName: suiteName)!)

    first.setModuleEnabled("gaze-shift", enabled: true)
    first.setValue(0.75, for: "dimIntensity", moduleId: "gaze-shift")

    // Recreate with same suite — data should persist
    let second = ModuleSettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
    let dim: Double? = second.value(for: "dimIntensity", moduleId: "gaze-shift")

    #expect(second.isModuleEnabled("gaze-shift") == true)
    #expect(dim == 0.75)
}
