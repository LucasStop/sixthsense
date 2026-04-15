import AVFoundation
import Foundation

// MARK: - Camera Frame Distributor

/// Receives frames from AVCaptureSession and multicasts them to all registered subscribers.
/// This allows multiple subscribers to process the same camera frames without duplicating
/// the AVCaptureSession.
public final class CameraFrameDistributor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    let processingQueue = DispatchQueue(label: "com.sixthsense.camera.processing", qos: .userInteractive)

    private let lock = NSLock()
    private var subscribers: [String: @Sendable (CMSampleBuffer) -> Void] = [:]

    override public init() {
        super.init()
    }

    /// Add a subscriber that will receive every camera frame.
    func addSubscriber(id: String, handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        subscribers[id] = handler
    }

    /// Remove a subscriber by ID.
    func removeSubscriber(id: String) {
        lock.lock()
        defer { lock.unlock() }
        subscribers.removeValue(forKey: id)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        let currentSubscribers = subscribers
        lock.unlock()

        for (_, handler) in currentSubscribers {
            handler(sampleBuffer)
        }
    }
}
