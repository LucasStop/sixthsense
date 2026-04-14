import SwiftUI

// MARK: - Onboarding / Tutorial

/// With a single feature module, the tutorial window is just the
/// HandCommand guide with no sidebar. The ModuleGuideView already knows
/// how to render one ModuleGuide end-to-end.
struct OnboardingView: View {
    var body: some View {
        ModuleGuideView(guide: .handCommand)
            .frame(minWidth: 720, minHeight: 620)
            .navigationTitle("Tutorial — HandCommand")
    }
}
