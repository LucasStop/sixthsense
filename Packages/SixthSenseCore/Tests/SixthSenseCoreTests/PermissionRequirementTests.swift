import Testing
@testable import SixthSenseCore

@Test func permissionTypeHasAllCases() {
    let types = PermissionType.allCases
    #expect(types.contains(.camera))
    #expect(types.contains(.accessibility))
    #expect(types.contains(.screenRecording))
    #expect(types.contains(.localNetwork))
    #expect(types.contains(.microphone))
    #expect(types.count == 5)
}

@Test func permissionTypeLabelsArePortuguese() {
    #expect(PermissionType.camera.label == "Câmera")
    #expect(PermissionType.accessibility.label == "Acessibilidade")
    #expect(PermissionType.screenRecording.label == "Gravação de Tela")
    #expect(PermissionType.localNetwork.label == "Rede Local")
    #expect(PermissionType.microphone.label == "Microfone")
}

@Test func permissionTypeDescriptionsArePortuguese() {
    // All descriptions should be non-empty and start with "Necessário" to be consistent
    for type in PermissionType.allCases {
        #expect(type.description.hasPrefix("Necessário"))
    }
}

@Test func permissionTypeHasSystemImage() {
    for type in PermissionType.allCases {
        #expect(type.systemImage.isEmpty == false)
    }
}

@Test func permissionRequirementDefaultsToRequired() {
    let req = PermissionRequirement(type: .camera, reason: "teste")
    #expect(req.isRequired == true)
}

@Test func permissionRequirementCanBeOptional() {
    let req = PermissionRequirement(type: .microphone, reason: "opcional", isRequired: false)
    #expect(req.isRequired == false)
    #expect(req.type == .microphone)
    #expect(req.reason == "opcional")
}

@Test func permissionRequirementStoresContext() {
    let req = PermissionRequirement(
        type: .accessibility,
        reason: "Controle de cursor e janelas"
    )
    #expect(req.type == .accessibility)
    #expect(req.reason == "Controle de cursor e janelas")
}

@Test func multipleRequirementsCanBeGrouped() {
    let requirements: [PermissionRequirement] = [
        PermissionRequirement(type: .camera, reason: "r1"),
        PermissionRequirement(type: .accessibility, reason: "r2"),
    ]
    #expect(requirements.count == 2)
    #expect(requirements[0].type == .camera)
    #expect(requirements[1].type == .accessibility)
}
