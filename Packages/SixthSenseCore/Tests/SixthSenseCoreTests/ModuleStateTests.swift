import Testing
@testable import SixthSenseCore

@Test func moduleStateIsActiveOnlyWhenStartingOrRunning() {
    #expect(ModuleState.running.isActive == true)
    #expect(ModuleState.starting.isActive == true)

    #expect(ModuleState.disabled.isActive == false)
    #expect(ModuleState.error.isActive == false)
    #expect(ModuleState.waitingForPermissions.isActive == false)
    #expect(ModuleState.stopping.isActive == false)
}

@Test func moduleStateLabelsArePortuguese() {
    #expect(ModuleState.disabled.label == "Desligado")
    #expect(ModuleState.waitingForPermissions.label == "Permissões Necessárias")
    #expect(ModuleState.starting.label == "Iniciando...")
    #expect(ModuleState.running.label == "Ativo")
    #expect(ModuleState.error.label == "Erro")
    #expect(ModuleState.stopping.label == "Parando...")
}

@Test func moduleStateHasSystemImageForEachCase() {
    let states: [ModuleState] = [.disabled, .waitingForPermissions, .starting, .running, .error, .stopping]
    for state in states {
        #expect(state.systemImage.isEmpty == false)
    }
}

@Test func moduleStateStartingAndStoppingShareYellowIndicator() {
    // Both are "transitioning" states and should use the same systemImage
    #expect(ModuleState.starting.systemImage == ModuleState.stopping.systemImage)
}

@Test func moduleStateEquatable() {
    #expect(ModuleState.running == ModuleState.running)
    #expect(ModuleState.disabled == ModuleState.disabled)
    #expect(ModuleState.running != ModuleState.disabled)
    #expect(ModuleState.starting != ModuleState.running)
}
