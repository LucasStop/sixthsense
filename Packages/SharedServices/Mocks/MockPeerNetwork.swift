import Foundation
import Combine
import Network
import SharedServices

/// In-memory PeerNetwork that tracks advertise/browse/send calls and
/// exposes a controllable messagePublisher for injecting test messages.
@MainActor
public final class MockPeerNetwork: PeerNetwork {
    public private(set) var isAdvertising: Bool = false
    public private(set) var isBrowsing: Bool = false
    public var discoveredPeers: [DiscoveredPeer] = []

    public private(set) var startAdvertisingCalls: [(name: String, port: UInt16)] = []
    public private(set) var stopAdvertisingCalls: Int = 0
    public private(set) var startBrowsingCalls: Int = 0
    public private(set) var stopBrowsingCalls: Int = 0
    public private(set) var connectCalls: [DiscoveredPeer] = []
    public private(set) var sentMessages: [(peerId: String, data: Data)] = []

    /// Toggle this to true to make startAdvertising throw a test error.
    public var shouldFailAdvertising: Bool = false

    private let messageSubject = PassthroughSubject<PeerMessage, Never>()

    public init() {}

    public var messagePublisher: AnyPublisher<PeerMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    public func startAdvertising(name: String, port: UInt16) throws {
        startAdvertisingCalls.append((name: name, port: port))
        if shouldFailAdvertising {
            throw MockPeerNetworkError.forcedFailure
        }
        isAdvertising = true
    }

    public func stopAdvertising() {
        stopAdvertisingCalls += 1
        isAdvertising = false
    }

    public func startBrowsing() {
        startBrowsingCalls += 1
        isBrowsing = true
    }

    public func stopBrowsing() {
        stopBrowsingCalls += 1
        isBrowsing = false
        discoveredPeers.removeAll()
    }

    public func connect(to peer: DiscoveredPeer) {
        connectCalls.append(peer)
    }

    public func send(data: Data, to peerId: String) {
        sentMessages.append((peerId: peerId, data: data))
    }

    /// Inject an incoming message to all subscribers of messagePublisher.
    public func injectIncomingMessage(_ message: PeerMessage) {
        messageSubject.send(message)
    }
}

public enum MockPeerNetworkError: Error {
    case forcedFailure
}
