import Network
import Foundation
import Combine

// MARK: - Bonjour Service

/// Handles local network device discovery and communication using Apple's Network framework.
/// Used by AirCursor, PortalView, and GhostDrop for cross-device communication.
@MainActor
@Observable
public final class BonjourService {

    public static let serviceType = "_sixthsense._tcp"

    public private(set) var isAdvertising = false
    public private(set) var isBrowsing = false
    public private(set) var discoveredPeers: [DiscoveredPeer] = []

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [String: NWConnection] = [:]

    private let connectionSubject = PassthroughSubject<PeerMessage, Never>()

    public init() {}

    /// Publisher for incoming messages from connected peers.
    public var messagePublisher: AnyPublisher<PeerMessage, Never> {
        connectionSubject.eraseToAnyPublisher()
    }

    // MARK: - Advertise

    /// Start advertising this Mac on the local network.
    public func startAdvertising(name: String, port: UInt16) throws {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
        listener.service = NWListener.Service(name: name, type: Self.serviceType)

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.isAdvertising = (state == .ready)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener.start(queue: .main)
        self.listener = listener
    }

    /// Stop advertising.
    public func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
    }

    // MARK: - Browse

    /// Start browsing for nearby SixthSense devices.
    public func startBrowsing() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.isBrowsing = (state == .ready)
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.discoveredPeers = results.compactMap { result in
                    if case .service(let name, let type, _, _) = result.endpoint {
                        return DiscoveredPeer(name: name, type: type, endpoint: result.endpoint)
                    }
                    return nil
                }
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    /// Stop browsing.
    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        discoveredPeers.removeAll()
    }

    // MARK: - Connect

    /// Connect to a discovered peer.
    public func connect(to peer: DiscoveredPeer) {
        let connection = NWConnection(to: peer.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                Task { @MainActor in
                    self?.receiveMessage(on: connection, peerId: peer.name)
                }
            }
        }
        connection.start(queue: .main)
        connections[peer.name] = connection
    }

    /// Send data to a connected peer.
    public func send(data: Data, to peerId: String) {
        guard let connection = connections[peerId] else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let peerId = connection.endpoint.debugDescription
        connections[peerId] = connection
        connection.start(queue: .main)
        receiveMessage(on: connection, peerId: peerId)
    }

    private func receiveMessage(on connection: NWConnection, peerId: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data {
                self?.connectionSubject.send(PeerMessage(peerId: peerId, data: data))
            }
            if error == nil {
                self?.receiveMessage(on: connection, peerId: peerId)
            }
        }
    }
}

// MARK: - Supporting Types

public struct DiscoveredPeer: Identifiable, Sendable {
    public let name: String
    public let type: String
    public let endpoint: NWEndpoint
    public var id: String { name }
}

public struct PeerMessage: Sendable {
    public let peerId: String
    public let data: Data
}
