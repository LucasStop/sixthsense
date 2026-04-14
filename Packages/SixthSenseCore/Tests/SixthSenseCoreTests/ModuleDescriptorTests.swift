import Testing
@testable import SixthSenseCore

@Test func moduleDescriptorStoresAllFields() {
    let descriptor = ModuleDescriptor(
        id: "air-cursor",
        name: "AirCursor",
        tagline: "Telekinesis KVM",
        systemImage: "iphone.radiowaves.left.and.right",
        category: .input
    )

    #expect(descriptor.id == "air-cursor")
    #expect(descriptor.name == "AirCursor")
    #expect(descriptor.tagline == "Telekinesis KVM")
    #expect(descriptor.systemImage == "iphone.radiowaves.left.and.right")
    #expect(descriptor.category == .input)
}

@Test func moduleDescriptorIsIdentifiable() {
    let a = ModuleDescriptor(id: "id-1", name: "A", tagline: "t", systemImage: "star", category: .input)
    let b = ModuleDescriptor(id: "id-2", name: "B", tagline: "t", systemImage: "star", category: .input)
    #expect(a.id != b.id)
}

@Test func moduleCategoryHasAllCases() {
    let cases = ModuleCategory.allCases
    #expect(cases.contains(.input))
    #expect(cases.contains(.display))
    #expect(cases.contains(.transfer))
    #expect(cases.contains(.interface))
    #expect(cases.count == 4)
}

@Test func moduleCategoryLabelsArePortuguese() {
    #expect(ModuleCategory.input.label == "Controle de Entrada")
    #expect(ModuleCategory.display.label == "Tela")
    #expect(ModuleCategory.transfer.label == "Transferência")
    #expect(ModuleCategory.interface.label == "Interface")
}

@Test func moduleCategoryHasSystemImage() {
    for category in ModuleCategory.allCases {
        #expect(category.systemImage.isEmpty == false)
    }
}
