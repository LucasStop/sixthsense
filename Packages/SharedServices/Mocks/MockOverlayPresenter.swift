import Foundation
import SharedServices

/// In-memory overlay presenter that tracks which IDs have been created
/// (simulated) and removed.
@MainActor
public final class MockOverlayPresenter: OverlayPresenter {
    public private(set) var removeCalls: [String] = []
    public var registeredIds: Set<String> = []

    public init() {}

    public func removeOverlay(id: String) {
        removeCalls.append(id)
        registeredIds.remove(id)
    }

    public func hasOverlay(id: String) -> Bool {
        registeredIds.contains(id)
    }

    /// Test helper: pretend an overlay with this id is currently shown.
    public func simulateCreated(id: String) {
        registeredIds.insert(id)
    }
}
