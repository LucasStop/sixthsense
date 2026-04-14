import Foundation
import CoreMedia
import CoreGraphics
import Combine

// MARK: - Camera Pipeline

/// Abstraction over the shared camera pipeline. Modules that need video frames
/// depend on this protocol rather than the concrete CameraManager, so tests
/// can inject a mock pipeline that never touches AVFoundation.
@MainActor
public protocol CameraPipeline: AnyObject {
    func subscribe(id: String, handler: @escaping @Sendable (CMSampleBuffer) -> Void)
    func unsubscribe(id: String)
}

extension CameraManager: CameraPipeline {}

// MARK: - Mouse Controller

/// Abstraction over synthetic mouse event injection. Tests use a mock that
/// records calls instead of actually moving the cursor via CGEvent.
public protocol MouseController: Sendable {
    var currentPosition: CGPoint { get }
    func moveTo(_ point: CGPoint)
    func moveBy(dx: CGFloat, dy: CGFloat)
    func leftClick(at point: CGPoint)
    func rightClick(at point: CGPoint)
    func leftMouseDown(at point: CGPoint)
    func leftMouseUp(at point: CGPoint)
    func leftMouseDragged(to point: CGPoint)
    func scroll(deltaY: Int32, deltaX: Int32)
}

extension CursorController: MouseController {}

// MARK: - Window Accessibility

/// Abstraction over the macOS Accessibility API for window querying and
/// manipulation. Tests inject a mock that returns predetermined window lists.
@MainActor
public protocol WindowAccessibility {
    var isAccessibilityGranted: Bool { get }
    func allWindows() -> [WindowInfo]
    func windowAtPoint(_ point: CGPoint) -> WindowInfo?
    func focusWindow(_ window: WindowInfo)
}

extension AccessibilityService: WindowAccessibility {}

// MARK: - Peer Network

/// Abstraction over Bonjour-based device discovery and peer messaging. Tests
/// use a mock that publishes messages through a controlled subject without
/// touching the real network stack.
@MainActor
public protocol PeerNetwork: AnyObject {
    var isAdvertising: Bool { get }
    var isBrowsing: Bool { get }
    var discoveredPeers: [DiscoveredPeer] { get }
    var messagePublisher: AnyPublisher<PeerMessage, Never> { get }
    func startAdvertising(name: String, port: UInt16) throws
    func stopAdvertising()
    func startBrowsing()
    func stopBrowsing()
    func connect(to peer: DiscoveredPeer)
    func send(data: Data, to peerId: String)
}

extension BonjourService: PeerNetwork {}

// MARK: - Overlay Presenter

/// Abstraction over the parts of the overlay manager that modules need at
/// stop() time. Creating overlays uses a generic SwiftUI API and stays on the
/// concrete OverlayWindowManager — this protocol only exposes removal.
@MainActor
public protocol OverlayPresenter: AnyObject {
    func removeOverlay(id: String)
    func hasOverlay(id: String) -> Bool
}

extension OverlayWindowManager: OverlayPresenter {}
