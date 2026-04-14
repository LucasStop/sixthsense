import Foundation
import CoreMedia
import SharedServices

/// Records subscribe/unsubscribe calls without touching AVFoundation.
/// Use in unit tests of modules that depend on CameraPipeline.
@MainActor
public final class MockCameraPipeline: CameraPipeline {
    public private(set) var subscribeCalls: [String] = []
    public private(set) var unsubscribeCalls: [String] = []
    public private(set) var handlers: [String: @Sendable (CMSampleBuffer) -> Void] = [:]

    public init() {}

    public func subscribe(id: String, handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        subscribeCalls.append(id)
        handlers[id] = handler
    }

    public func unsubscribe(id: String) {
        unsubscribeCalls.append(id)
        handlers.removeValue(forKey: id)
    }

    /// Helper for tests that want to simulate receiving a frame on a given subscriber.
    /// Real CMSampleBuffer creation is painful, so most tests only verify subscribe/unsubscribe.
    public var isSubscribed: Bool {
        !handlers.isEmpty
    }
}
